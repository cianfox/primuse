import Foundation
import MusicKit
import OSLog

private let appleMusicLog = Logger(subsystem: "com.welape.yuanyin", category: "AppleMusic")

/// Apple Music 桥 ── 仅做"在搜索里多挂一组结果 + 调系统播放器开播"这件事,
/// 不试图把 Apple Music 歌混进 MusicLibrary。原因:
/// - Apple Music 是 DRM 流, 必须经 `ApplicationMusicPlayer` 才能播,我们自己
///   的 `AudioPlayerService` 走 AVAudioEngine 不能解。两个 player 各管各
///   的,共享的只有"用户在猿音 UI 里选了一首 Apple Music 歌就跳到系统侧
///   开播"这一刻。
/// - 把 Apple Music 歌持久化进库会让 CloudKit 同步逻辑、本地缓存策略、
///   metadata backfill 都得理解一种新 song type, 改动面巨大。
///
/// 当前能力:
/// 1. 申请 Apple Music 授权 (用户可在 Settings → Apple Music 入口里点)
/// 2. 用户搜索时同步查询 Apple Music catalog,搜歌结果回填给 UI
/// 3. 点 Apple Music 那条结果 → `ApplicationMusicPlayer.shared` 开播
///
/// 用户没订阅 Apple Music 时, `ApplicationMusicPlayer.play()` 会抛 error
/// (`MusicSubscriptionError.privilegesNotGranted`), 我们把它转成
/// `lastPlaybackError` 让 UI 提示用户去订阅。
@MainActor
@Observable
final class AppleMusicService {
    enum AuthState: Sendable {
        case notDetermined
        case denied
        case restricted
        case authorized
    }

    private(set) var authState: AuthState = .notDetermined
    private(set) var searchResults: [MusicKit.Song] = []
    private(set) var isSearching = false
    /// 最近一次播放调用如果失败 (未订阅 / 国家不可用 / 网络),把错误信息
    /// 暴露给 UI 弹 banner。成功后被清空。
    private(set) var lastPlaybackError: String?

    private var searchTask: Task<Void, Never>?

    init() {
        self.authState = Self.mapStatus(MusicAuthorization.currentStatus)
    }

    /// 入口走的是系统弹的授权对话框,首次调有动效, 后续调直接返回现状态。
    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        self.authState = Self.mapStatus(status)
        appleMusicLog.notice("Apple Music auth status: \(String(describing: status))")
    }

    /// 触发对 Apple Music catalog 的搜索。200ms debounce 跟 SearchView 自己的
    /// debounce 错开 (这边再叠 200ms 防止用户连击触发多次 catalog 调用)。
    /// 未授权时直接清结果,不试着 silently request 授权 (避免无端弹窗)。
    func search(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard authState == .authorized, !trimmed.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            await self.runSearch(term: trimmed)
        }
    }

    private func runSearch(term: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            var request = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
            request.limit = 25
            let response = try await request.response()
            if !Task.isCancelled {
                self.searchResults = Array(response.songs)
            }
        } catch is CancellationError {
            // user 继续打字,旧 query 失效,沉默丢弃
        } catch {
            appleMusicLog.error("Apple Music search failed: \(error.localizedDescription)")
            if !Task.isCancelled {
                self.searchResults = []
            }
        }
    }

    /// 调系统的 ApplicationMusicPlayer 开播。播放本身完全在系统侧,我们自己
    /// 的 AudioPlayerService 不参与, 跟我们当前播放的 NAS / 云盘歌互不干扰
    /// (但同一时间只能有一个 audio session active, 系统会自动让 Apple Music
    /// 暂停 / 抢占我们的)。
    ///
    /// 之前历史上有过点 row 必闪退的情况, 两个根因:
    /// 1. Info.plist 缺 `NSAppleMusicUsageDescription` → 调 MusicKit 会被 OS
    ///    直接 SIGABORT, 不走 catch。已通过 project.yml 把权限说明加回来。
    /// 2. 用户没有 Apple Music 订阅 / 区域不支持时, ApplicationMusicPlayer
    ///    的 queue 设置 + play() 在某些 iOS 版本会触发底层 assert。这里先
    ///    用 `MusicSubscription.current` 探一下能力, 不能播就直接给 UI 报
    ///    错而不是冒险调 player。
    func play(_ song: MusicKit.Song) async {
        lastPlaybackError = nil

        // 订阅探测 — 没订阅 / 不支持时直接 bail, 避免触发 player 的边界 case。
        do {
            let subscription = try await MusicSubscription.current
            guard subscription.canPlayCatalogContent else {
                lastPlaybackError = subscription.canBecomeSubscriber
                    ? String(localized: "apple_music_needs_subscription")
                    : String(localized: "apple_music_unavailable")
                return
            }
        } catch {
            appleMusicLog.error("Apple Music subscription check failed: \(error.localizedDescription)")
            lastPlaybackError = error.localizedDescription
            return
        }

        let player = ApplicationMusicPlayer.shared
        do {
            player.queue = ApplicationMusicPlayer.Queue(for: [song])
            try await player.play()
        } catch {
            appleMusicLog.error("Apple Music play failed: \(error.localizedDescription)")
            lastPlaybackError = error.localizedDescription
        }
    }

    private static func mapStatus(_ status: MusicAuthorization.Status) -> AuthState {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}
