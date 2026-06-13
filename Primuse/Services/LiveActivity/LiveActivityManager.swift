#if os(iOS)
import ActivityKit
import Foundation
import UIKit
import PrimuseKit

@MainActor
@Observable
final class LiveActivityManager {
    private var currentActivity: Activity<PlaybackActivityAttributes>?

    /// 当前活动对应的歌曲 id。ActivityKit 的 `attributes` 一旦 request 就不可变,
    /// 所以换歌必须 end 旧的再 start 新的 —— 用它来区分"换歌(重启)"还是
    /// "同一首歌的状态变化(只 update)"。
    private var activeSongID: Song.ID?

    /// 把 Live Activity 绑到播放器状态上。系统侧 / `AppServices` 只需在启动时
    /// 调一次,之后 start / update / end 全部由 observation 自动驱动 ——
    /// 跟 `MacMenuBarController.observePlayerState` 是同一个 re-arm 模式。
    private weak var observedPlayer: AudioPlayerService?

    /// 进度推送 task。只在播放中按固定间隔把 `currentTime` 同步进活动状态,
    /// 让锁屏进度条 / 灵动岛跟着走。换歌或停播时取消重建。
    private var progressTask: Task<Void, Never>?

    // MARK: - Observation wiring

    /// 开始观察播放器并据此驱动 Live Activity。重复调用是幂等的。
    func start(observing player: AudioPlayerService) {
        guard observedPlayer !== player else { return }
        observedPlayer = player
        observePlayerState()
    }

    /// 每当被跟踪的 observable 变化就重新求值一次:有 currentSong 就 start /
    /// update,没有就 end,然后重新注册 tracking 继续监听。
    private func observePlayerState() {
        guard let player = observedPlayer else { return }
        withObservationTracking {
            _ = player.currentSong?.id
            _ = player.isPlaying
            _ = player.coverRevision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.syncWithPlayerState()
                self?.observePlayerState()
            }
        }
        // 首次注册后立刻对齐一次,避免错过 arm 之前已发生的状态。
        syncWithPlayerState()
    }

    /// 把播放器当前状态投射到 Live Activity:换歌重启、同曲只更新、无曲结束。
    /// 全部经一个串行 Task 落地,避免 end/start 与进度更新交错出竞态。
    private func syncWithPlayerState() {
        guard let player = observedPlayer else { return }

        guard let song = player.currentSong else {
            // 没有在播曲目 —— 收掉活动。
            if currentActivity != nil || activeSongID != nil {
                Task { await self.endActivity() }
            }
            return
        }

        let isPlaying = player.isPlaying
        let elapsed = player.currentTime

        if activeSongID != song.id {
            // 换歌:attributes 不可变,先收旧的再开新的。activeSongID 立即占位,
            // 防止下一次 observation fire 把同一首歌再当成换歌处理。
            activeSongID = song.id
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.currentActivity != nil { await self.teardownActivity() }
                // teardown 后若 song 仍是当前曲才开,避免快速连切时开错活动。
                guard self.observedPlayer?.currentSong?.id == song.id else { return }
                self.startActivity(song: song, isPlaying: isPlaying)
                self.restartProgressUpdates()
            }
        } else {
            // 同一首歌的播放/暂停切换 —— 只更新状态,并据此重排进度推送。
            Task { @MainActor [weak self] in
                await self?.updateActivity(isPlaying: isPlaying, elapsedTime: elapsed)
                self?.restartProgressUpdates()
            }
        }
    }

    /// 播放中每秒把 `currentTime` 推进活动状态;暂停 / 无活动时不跑。
    private func restartProgressUpdates() {
        progressTask?.cancel()
        guard let player = observedPlayer, player.isPlaying, currentActivity != nil else {
            progressTask = nil
            return
        }
        progressTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, let player = self.observedPlayer,
                      player.isPlaying, self.currentActivity != nil else { return }
                await self.updateActivity(isPlaying: true, elapsedTime: player.currentTime)
            }
        }
    }

    /// 结束当前活动但**保留** `activeSongID`(换歌场景用),区别于公开的
    /// `endActivity()`(那个会把 bookkeeping 全清空)。
    private func teardownActivity() async {
        progressTask?.cancel()
        progressTask = nil
        guard let currentActivity else { return }
        nonisolated(unsafe) let activityToEnd = currentActivity
        self.currentActivity = nil

        let state = PlaybackActivityAttributes.ContentState(
            isPlaying: false,
            elapsedTime: 0
        )
        let content = ActivityContent(state: state, staleDate: nil)
        await activityToEnd.end(content, dismissalPolicy: .default)
        cleanupSharedCover()
    }

    /// App Group shared container URL
    private static let containerURL: URL? = {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PrimuseConstants.appGroupIdentifier)
    }()

    // MARK: - Cover directory (via MetadataAssetStore)


    // MARK: - Public API

    func startActivity(song: Song, isPlaying: Bool) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Write cover image to App Group shared container
        let coverName = writeCoverToSharedContainer(song: song)

        let attributes = PlaybackActivityAttributes(
            songTitle: song.title,
            artistName: song.artistName ?? "",
            albumTitle: song.albumTitle ?? "",
            duration: song.duration,
            coverImageName: coverName
        )

        let state = PlaybackActivityAttributes.ContentState(
            isPlaying: isPlaying,
            elapsedTime: 0
        )

        let content = ActivityContent(state: state, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    func updateActivity(isPlaying: Bool, elapsedTime: TimeInterval, nextSong: String? = nil) async {
        guard let currentActivity else { return }
        nonisolated(unsafe) let activityToUpdate = currentActivity

        let state = PlaybackActivityAttributes.ContentState(
            isPlaying: isPlaying,
            elapsedTime: elapsedTime,
            nextSongTitle: nextSong
        )

        let content = ActivityContent(state: state, staleDate: nil)
        await activityToUpdate.update(content)
    }

    func endActivity() async {
        activeSongID = nil
        await teardownActivity()
    }

    // MARK: - Cover Image Handling

    /// Writes a downscaled cover image to the App Group shared container.
    /// Returns the filename if successful, nil otherwise.
    private func writeCoverToSharedContainer(song: Song) -> String? {
        guard let containerURL = Self.containerURL else { return nil }

        let store = MetadataAssetStore.shared

        // Try songID-based cache first (works with source path references)。
        // 走 readCoverData(named:) 而不是直 Data(contentsOf:),后者会读到
        // 41 字节 redirect 字符串。
        var coverData: Data?
        let hashedName = store.expectedCoverFileName(for: song.id)
        coverData = store.readCoverData(named: hashedName)

        // Fallback: legacy local filename (no "/" or "://")
        if coverData == nil, let ref = song.coverArtFileName, !ref.isEmpty,
           !ref.contains("/"), !ref.contains("://") {
            coverData = store.readCoverData(named: ref)
        }

        guard let data = coverData, let originalImage = UIImage(data: data) else {
            return nil
        }

        // Downscale to 80×80 for Live Activity (Apple recommends ~84px max)
        let targetSize = CGSize(width: 80, height: 80)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))

            // Center-crop to square
            let sourceAspect = originalImage.size.width / originalImage.size.height
            let drawRect: CGRect
            if sourceAspect > 1 {
                let scaledWidth = targetSize.height * sourceAspect
                let xOffset = (targetSize.width - scaledWidth) / 2
                drawRect = CGRect(x: xOffset, y: 0, width: scaledWidth, height: targetSize.height)
            } else {
                let scaledHeight = targetSize.width / sourceAspect
                let yOffset = (targetSize.height - scaledHeight) / 2
                drawRect = CGRect(x: 0, y: yOffset, width: targetSize.width, height: scaledHeight)
            }
            originalImage.draw(in: drawRect)
        }

        // Save as PNG (more reliable in Widget Extensions per Apple forums)
        guard let pngData = resizedImage.pngData() else { return nil }

        let sharedFileName = "live_activity_cover.png"
        let destinationURL = containerURL.appendingPathComponent(sharedFileName)

        do {
            try pngData.write(to: destinationURL, options: .atomic)
            return sharedFileName
        } catch {
            print("Failed to write cover to shared container: \(error)")
            return nil
        }
    }

    /// Removes the cover file from the shared container
    private func cleanupSharedCover() {
        guard let containerURL = Self.containerURL else { return }
        let fileURL = containerURL.appendingPathComponent("live_activity_cover.png")
        try? FileManager.default.removeItem(at: fileURL)
    }
}

#endif
