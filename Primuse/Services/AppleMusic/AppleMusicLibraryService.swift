import Foundation
import CryptoKit
import MusicKit
import PrimuseKit

/// 把 Apple Music user library (用户已收藏 / 已添加到资料库的歌) 拉进
/// 猿音 MusicLibrary, 跟 NAS / 云盘的歌一起出现在 Library 视图。
///
/// 系统侧由 `ApplicationMusicPlayer` 负责 DRM 流播放, 我们这里只做:
/// - 用 `MusicLibraryRequest<MusicKit.Song>()` 拉一次性 + 增量
/// - 把每首 MusicKit.Song 映射成 PrimuseKit.Song (sourceID 固定为
///   `appleMusicSystemSourceID`, filePath 是 Apple Music MusicItemID)
/// - 写入 MusicLibrary, 后续 SongRowView / AlbumDetailView / NowPlaying
///   都能直接显示这些歌, 跟本地歌平等
///
/// 不做 (Phase 2+):
/// - CloudKit 同步 (Apple Music 库每个设备独立拉, 避免 sync 冲突)
/// - 跨类型 Playlist (本地 + Apple Music 混入一个 Playlist)
/// - Apple Music 歌词显示 (需新 LyricsScrollView 适配 MusicKit.Lyrics)
@MainActor
@Observable
final class AppleMusicLibraryService {
    /// Apple Music 那个虚拟 source 的固定 ID — 全猿音里 hard-code 这个值,
    /// 不走 UUID, 让 song.sourceID 一致, 多次启动 / 重装也能 match 上。
    nonisolated static let systemSourceID = "primuse.appleMusic.system"

    enum SyncState: Sendable {
        case idle
        case syncing
        case done(songCount: Int, at: Date)
        case failed(String)
    }

    private(set) var state: SyncState = .idle
    /// 最近一次完成扫描的时间, 用于 UI 显示。
    private(set) var lastSyncAt: Date?

    private let library: MusicLibrary
    private let appleMusic: AppleMusicService
    private var syncTask: Task<Void, Never>?
    /// in-memory cache: PrimuseKit.Song.filePath (= MusicItemID.rawValue)
    /// → MusicKit.Song. sync 时填, play 时查 — 让 player.play(primuseSong)
    /// 不用每次再发 catalog lookup。冷启动后 cache 空, miss 时回退到
    /// MusicCatalogResourceRequest 拉一次。
    private var songCache: [String: MusicKit.Song] = [:]

    init(library: MusicLibrary, appleMusic: AppleMusicService) {
        self.library = library
        self.appleMusic = appleMusic
    }

    /// 启动一次完整拉取。不持有任何分页 cursor — Apple Music user library 量
    /// 不大 (大部分用户几百到几千首), 一次性拉全。失败时 state=.failed, UI
    /// 显示错误并允许重试。
    func sync() {
        guard syncTask == nil else { return }
        guard appleMusic.authState == .authorized else {
            state = .failed("Apple Music 未授权, 去 Settings → Apple Music 启用")
            return
        }
        state = .syncing
        syncTask = Task { [weak self] in
            await self?.runSync()
        }
    }

    /// 用 PrimuseKit.Song 在系统侧起播 — filePath 字段实际是 MusicItemID。
    /// 缓存命中直接 play, miss 时走 catalog lookup 兜底 (冷启动场景)。
    func play(primuseSong song: PrimuseKit.Song) async {
        let amID = song.filePath
        let musicKitSong: MusicKit.Song?
        if let cached = songCache[amID] {
            musicKitSong = cached
        } else {
            let id = MusicItemID(rawValue: amID)
            do {
                let req = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
                let resp = try await req.response()
                musicKitSong = resp.items.first
                if let m = musicKitSong { songCache[amID] = m }
            } catch {
                plog("⚠️Apple Music catalog lookup failed for \(amID): \(error.localizedDescription)")
                return
            }
        }
        guard let mk = musicKitSong else {
            plog("⚠️Apple Music 找不到曲目 \(amID)")
            return
        }
        await appleMusic.play(mk)
    }

    /// 查这首歌在 Apple Music 上**是否有歌词** (only 一个 bool 信号)。
    /// Apple MusicKit 公开 API 不暴露歌词内容 (`Song.hasLyrics` 是 Bool, 没有
    /// `.lyrics` 文本字段, time-synced lyrics 更是完全闭源)。UI 用这个返回值
    /// 决定要不要显示 "在 Apple Music 中看歌词" 按钮 — 真要看歌词只能跳到
    /// Apple Music App。
    func fetchHasLyrics(forFilePath amID: String) async -> Bool {
        let id = MusicItemID(rawValue: amID)
        let request = MusicCatalogResourceRequest<MusicKit.Song>(matching: \.id, equalTo: id)
        do {
            let resp = try await request.response()
            return resp.items.first?.hasLyrics ?? false
        } catch {
            plog("⚠️Apple Music hasLyrics check failed for \(amID): \(error.localizedDescription)")
            return false
        }
    }

    func cancel() {
        syncTask?.cancel()
        syncTask = nil
        state = .idle
    }

    private func runSync() async {
        defer { syncTask = nil }
        do {
            // MusicLibraryRequest 一次性拉 user library 内 Song。limit 设到
            // 上限 (默认 25, 调大到 100 一页), 后续翻页直到 nextBatch 为 nil。
            var request = MusicLibraryRequest<MusicKit.Song>()
            request.limit = 100
            let response = try await request.response()
            var allMusicKitSongs: [MusicKit.Song] = []
            allMusicKitSongs.append(contentsOf: response.items)

            // 翻页接口在 MusicItemCollection 上 (不是 response 上)。直到
            // 当前 collection 没有 nextBatch 为止。
            var currentBatch = response.items
            while currentBatch.hasNextBatch {
                if Task.isCancelled { return }
                guard let next = try await currentBatch.nextBatch() else { break }
                allMusicKitSongs.append(contentsOf: next)
                currentBatch = next
            }

            if Task.isCancelled { return }
            plog("🎵 Apple Music library fetched: \(allMusicKitSongs.count) songs")

            // 把 MusicKit.Song 缓存住, play 时直接喂给 ApplicationMusicPlayer
            // 不用走 catalog lookup。
            for s in allMusicKitSongs {
                songCache[s.id.rawValue] = s
            }
            let songs = allMusicKitSongs.map { Self.toPrimuseSong($0) }
            // 把这些歌加进 library, sourceIDs 限定 Apple Music, 让 addSongs
            // 自己处理删除 (Apple Music 删歌的 case 会被检测到)。
            library.addSongs(
                songs,
                affectedSourceIDs: [Self.systemSourceID],
                notifyRemovals: true
            )

            lastSyncAt = Date()
            state = .done(songCount: songs.count, at: lastSyncAt!)
            plog("🎵 Apple Music library synced: \(songs.count) songs")
        } catch is CancellationError {
            state = .idle
        } catch {
            plog("⚠️Apple Music library sync failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// MusicKit.Song → PrimuseKit.Song 映射。
    /// - songID 用 sha256(sourceID + AppleMusicID) — 跟 NAS 歌的 id 算法一致,
    ///   保证全局唯一且稳定 (同一首 Apple Music 歌每次 sync 都得到同一个 id)。
    /// - fileFormat: Apple Music 走系统 player, 实际格式由 ApplicationMusicPlayer
    ///   决定, 我们填 `.aac` 占位 (大部分 Apple Music 是 AAC)。
    nonisolated static func toPrimuseSong(_ s: MusicKit.Song) -> PrimuseKit.Song {
        let sourceID = Self.systemSourceID
        let amID = s.id.rawValue
        let songID = hashSongID(sourceID: sourceID, path: amID)
        return PrimuseKit.Song(
            id: songID,
            title: s.title,
            albumTitle: s.albumTitle,
            artistName: s.artistName,
            trackNumber: s.trackNumber,
            discNumber: s.discNumber,
            duration: s.duration ?? 0,
            fileFormat: .aac,
            filePath: amID,
            sourceID: sourceID,
            fileSize: 0,
            bitRate: nil,
            sampleRate: nil,
            bitDepth: nil,
            genre: s.genreNames.first,
            year: s.releaseDate.flatMap {
                Calendar.current.component(.year, from: $0)
            },
            lastModified: nil,
            dateAdded: s.libraryAddedDate ?? Date(),
            coverArtFileName: nil,
            lyricsFileName: nil
        )
    }

    /// 跟项目里其他 scanner 一样的 song.id 算法 — sha256(sourceID:path) 前 16 字节 hex。
    nonisolated private static func hashSongID(sourceID: String, path: String) -> String {
        let hash = SHA256.hash(data: Data("\(sourceID):\(path)".utf8))
        return hash.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
