#if os(macOS)
import SwiftUI
import AppKit
import PrimuseKit

/// 1.6 重设计后的 macOS 根布局: 自定义 TitleBar + Sidebar + Detail + BottomBar 四件套,
/// 不再依赖 NavigationSplitView。窗口设了 `.windowStyle(.hiddenTitleBar)`,
/// 顶部导航、搜索和窗口控制点都由 `PMTitleBar` 按设计稿绘制。
struct MacContentView: View {
    @State private var selection: MacRoute = .home
    @State private var sidebarCollapsed: Bool = false
    @State private var savedSidebarCollapsed: Bool = false
    @State private var nowPlayingPresented = false
    @State private var queuePresented = false
    @State private var searchText = ""
    @State private var preferences = MacUIPreferences.shared

    @Environment(\.openWindow) private var openWindow
    @Environment(SourcesStore.self) private var sourcesStore
    @AppStorage("primuse.hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            PMTitleBar(
                searchText: $searchText,
                sidebarCollapsed: $sidebarCollapsed,
                selection: $selection,
                onAddSource: { selectRoute(.sources) },
                onAudioOutput: { /* 由 BottomBar 右侧的喇叭按钮 popover 接管 */ }
            )

            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    MacSidebar(selection: $selection)
                        .frame(width: preferences.sidebarWidth)
                        // 拖拽改宽的命中区直接盖在侧栏与正文的原有边界上 (overlay 不占
                        // 布局宽度), 不再额外画一条分割线。
                        .overlay(alignment: .trailing) {
                            SidebarResizeHandle(preferences: preferences)
                                .frame(width: 10)
                                .frame(maxHeight: .infinity)
                                // 右移半个宽度让命中区跨在侧栏与正文的边界上。
                                .offset(x: 5)
                        }
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                ZStack {
                    MacDetailContainer(route: selection, searchText: $searchText)
                        .background(PMColor.bg.ignoresSafeArea())

                    if nowPlayingPresented {
                        MacNowPlayingView(onClose: {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                nowPlayingPresented = false
                            }
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if queuePresented {
                    MacQueuePanel(onClose: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            queuePresented = false
                        }
                    })
                    .frame(width: 380)
                    .transition(.move(edge: .trailing))
                }
            }
            // BottomBar 用 safeAreaInset 挂在内容 HStack 底部, 而不是当 VStack 的
            // 第三行 —— 后者会让底栏自带一条等高的窗口底色 (PMColor.bg) 横条, 浮动
            // 卡片的圆角和左右留白处透出的就是这条底色, 跟上方 sidebar 的玻璃色对不上,
            // 看着像卡片背后压了一个方块。改成 safeAreaInset 后 sidebar / detail 的
            // ignoresSafeArea 背景会一直延伸到窗口底部、铺到卡片背后, 圆角处透出的就是
            // 各自那一列的背景色, 卡片真正"浮"在内容上。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MacBottomBar(
                    isExpanded: nowPlayingPresented,
                    isQueueShown: queuePresented,
                    onToggleNowPlaying: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            nowPlayingPresented.toggle()
                        }
                    },
                    onToggleQueue: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            queuePresented.toggle()
                        }
                    },
                    onMiniPlayer: {
                        PrimuseAppDelegate.shared?.toggleMiniPlayer()
                    },
                    onFullScreen: {
                        PrimuseAppDelegate.shared?.toggleFullScreenPlayer()
                    }
                )
            }
        }
        .environment(\.pmAppearance, preferences.appearance)
        .background(PMColor.bg.ignoresSafeArea())
        .background(PMWindowChromeConfigurator())
        .ignoresSafeArea(.container, edges: .top)
        .sheet(isPresented: onboardingPresented) {
            OnboardingView()
                .frame(minWidth: 720, minHeight: 560)
        }
        .task { MainWindowOpener.register(openWindow) }
        .onReceive(NotificationCenter.default.publisher(for: .primuseRequestExpandNowPlaying)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                nowPlayingPresented = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .primuseSelectScrobble)) { _ in
            selectRoute(.scrobble)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            savedSidebarCollapsed = sidebarCollapsed
            withAnimation(.easeInOut(duration: 0.25)) {
                sidebarCollapsed = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                sidebarCollapsed = savedSidebarCollapsed
            }
        }
    }

    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding && sourcesStore.sources.isEmpty },
            set: { isPresented in
                if !isPresented { hasSeenOnboarding = true }
            }
        )
    }

    private func selectRoute(_ route: MacRoute) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selection = route
        }
    }
}

// MARK: - Sidebar resize handle

/// 侧栏宽度拖拽手柄。设计稿里侧栏可在 180–300pt 之间拖动调整。
///
/// 用 AppKit NSView 而不是 SwiftUI DragGesture: 主窗口开了
/// `isMovableByWindowBackground`, 任何落在"背景"上的拖拽都会被窗口抢去当成
/// 移动窗口 —— 之前的 DragGesture 既改不动宽度, 又跟窗口移动打架, 表现为
/// 拖整个窗口 + 宽度一抖一抖。这里的 NSView 把 `mouseDownCanMoveWindow`
/// 返回 false, 明确告诉窗口"别在我身上发起移动", 拖拽完全由它自己处理,
/// 实时改 `MacUIPreferences.sidebarWidth` (夹到 [min, max] 并持久化)。
private struct SidebarResizeHandle: NSViewRepresentable {
    let preferences: MacUIPreferences

    func makeNSView(context: Context) -> NSView {
        ResizeHandleNSView(preferences: preferences)
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// overlay 默认贴在侧栏 trailing 内侧, 右移半个宽度让 10pt 命中区跨在边界线上。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: 10, height: proposal.height ?? 0)
    }
}

private final class ResizeHandleNSView: NSView {
    private let preferences: MacUIPreferences
    private var startWidth: CGFloat = 0
    private var startX: CGFloat = 0

    init(preferences: MacUIPreferences) {
        self.preferences = preferences
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 关键: 落在手柄上的 mouseDown 不触发窗口移动。
    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        startWidth = preferences.sidebarWidth
        startX = event.locationInWindow.x
    }

    override func mouseDragged(with event: NSEvent) {
        // 用窗口坐标系里的绝对位移算, 避免 deltaX 累加在夹紧后产生死区。
        let dx = event.locationInWindow.x - startX
        preferences.sidebarWidth = min(
            PMSize.sidebarMax,
            max(PMSize.sidebarMin, startWidth + dx)
        )
    }
}
#endif
