#if os(macOS)
import AppKit
import SwiftUI
import PrimuseKit

/// Owns the menu bar status item and its popover. Survives for the lifetime
/// of the app — the popover view is rebuilt on demand so SwiftUI sees fresh
/// observable state every time the user opens it.
@MainActor
final class MacMenuBarController: NSObject, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var iconObserver: NSObjectProtocol?

    /// Toggle whether the status item shows the current song title next to
    /// the icon. Stored in UserDefaults so it survives launches; users who
    /// prefer a clean menu bar can turn it off.
    @AppStorage("menuBarShowTitle") private var showTitle: Bool = true
    /// Max characters of song title shown in the status bar — Apple's
    /// system bar caps text width and squeezes other items if too long.
    private let titleLimit = 28

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = statusBarImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        self.statusItem = item

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 320, height: 360)
        pop.delegate = self
        pop.contentViewController = NSHostingController(
            rootView: MenuBarPlayerView(onOpenMainWindow: { [weak self] in
                self?.activateMainWindow()
                self?.popover?.performClose(nil)
            })
            .applyPrimuseEnvironments()
        )
        self.popover = pop

        observePlayerState()
        refreshStatusItem()
        observeAppIconChange()
    }

    /// App 图标切换后强制重画状态项图标 —— refreshStatusItem 平时只在 image == nil
    /// 时设, 不会主动跟着换, 所以这里收到通知直接覆盖。
    private func observeAppIconChange() {
        iconObserver = NotificationCenter.default.addObserver(
            forName: .primuseAppIconChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.statusItem?.button?.image = self?.statusBarImage()
            }
        }
    }

    /// Re-arms whenever any of the tracked observable values changes.
    /// Each fire re-evaluates the status item text + icon, then re-registers
    /// the tracking closure so we keep listening.
    private func observePlayerState() {
        let player = AppServices.shared.playerService
        withObservationTracking {
            _ = player.currentSong?.id
            _ = player.currentSong?.title
            _ = player.currentSong?.artistName
            _ = player.isPlaying
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshStatusItem()
                self?.observePlayerState()
            }
        }
    }

    /// 菜单栏图标:用 App 自己的图标(猿音品牌图),而不是通用音符符号。
    /// 全彩、非模板(品牌图不做单色着色)。取不到时兜底回音符模板符号。
    private func statusBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        if let icon = NSApp.applicationIconImage, icon.isValid {
            let img = NSImage(size: size)
            img.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: size),
                      from: .zero, operation: .sourceOver, fraction: 1.0)
            img.unlockFocus()
            img.isTemplate = false
            return img
        }
        let fallback = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Primuse") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let player = AppServices.shared.playerService

        // 图标固定用 App 品牌图(播放状态在 popover 里体现,不再切音符/播放/暂停)。
        if button.image == nil { button.image = statusBarImage() }

        if showTitle, let title = player.currentSong?.title, !title.isEmpty {
            // Title 旁边一个空格,避免和图标贴在一起。
            button.title = " " + truncate(title, max: titleLimit)
            button.toolTip = [title, player.currentSong?.artistName].compactMap { $0 }.joined(separator: " — ")
        } else {
            button.title = ""
            button.toolTip = "Primuse"
        }
    }

    private func truncate(_ s: String, max: Int) -> String {
        guard s.count > max else { return s }
        let idx = s.index(s.startIndex, offsetBy: max - 1)
        return String(s[..<idx]) + "…"
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = existingMainWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            return
        }
        // 主窗口已被用户关掉(红灯), SwiftUI 把 WindowGroup 实例销毁了,
        // NSApp.windows 找不到任何可 makeKey 的内容窗口。走 SwiftUI 的
        // openWindow(id:) 让 WindowGroup 重新建一份;桥接的 action 在
        // MacContentView.task 里已经注册过。
        MainWindowOpener.openMainWindow()
    }

    /// 找到当前 SwiftUI 主窗口。排除 mini player / 桌面歌词 / Settings /
    /// 各种 NSPanel 副窗口。Settings 也是 canBecomeMain 的 NSWindow,
    /// 必须用 identifier / autosaveName / title 联合过滤,不能只看
    /// canBecomeMain。
    private func existingMainWindow() -> NSWindow? {
        NSApp.windows.first { window in
            guard window.canBecomeMain,
                  !(window is NSPanel),
                  !window.styleMask.contains(.utilityWindow) else { return false }
            // Settings 场景的 identifier 形如 "com_apple_SwiftUI_Settings_window"。
            if let id = window.identifier?.rawValue, id.contains("Settings") {
                return false
            }
            if window.frameAutosaveName == "PrimuseMiniPlayer" ||
                window.frameAutosaveName == "PrimuseDesktopLyrics" {
                return false
            }
            return true
        }
    }
}

/// Helper to mirror the same environment objects PrimuseApp injects into
/// the main scene, so the popover view sees the same services.
extension View {
    func applyPrimuseEnvironments() -> some View {
        let services = AppServices.shared
        // No global tint here: same reasoning as PrimuseApp.injectServices
        // — macOS ships native control colors, the brand purple only
        // belongs on hand-styled brand surfaces.
        return self
            .environment(services.themeService)
            .environment(services.playerService)
            .environment(services.playerService.audioEngine)
            .environment(services.playerService.equalizerService)
            .environment(services.playerService.audioEffectsService)
            .environment(services.musicLibrary)
            .environment(services.sourcesStore)
            .environment(services.sourceManager)
            .environment(services.scraperSettingsStore)
            .environment(services.scraperService)
            .environment(services.playbackSettingsStore)
            .environment(services.scanService)
            .environment(services.cloudSync)
            .environment(services.metadataBackfill)
            // 下面这些是 MacSettingsView 各 tab 需要的, 菜单栏 popover 用不到也无害。
            .environment(services.updateChecker)
            .environment(services.coverTintProvider)
            .environment(services.appleMusic)
            .environment(services.appleMusicLibrary)
            .environment(services.dlnaRenderer)
            .environment(services.visualizer)
            .environment(services.duplicateCleanup)
    }
}
#endif
