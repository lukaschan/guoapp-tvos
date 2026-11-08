import SwiftUI

/// 推荐页（redfruit 的 FeedHeroScreen）：整屏 hero 播放推荐流里的剧，左侧信息栏，底部「接下来」。
/// - 进页面 / 换剧时从观看记录续播；离开页面（切标签、进详情、转全屏）就停掉，回来再按观看记录重新起播，
///   全屏播放里看的进度不会被 hero 回退；
/// - hero 只有真正看满 30 秒才存进度（HeroPlayback）；
/// - 播放键在本页任何位置都是 hero 的暂停 / 继续。
struct FeedHeroView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @AppStorage("autoAdvance") private var autoAdvance = true

    @StateObject private var feed = FeedModel()
    @StateObject private var hero = HeroPlayback()

    @State private var selection = PreviewSelection(committedID: "")
    @State private var path: [Drama] = []
    @State private var fullScreen: PlaybackPresentation?
    @State private var isVisible = false
    @State private var rowFocused = false
    @State private var upNextFreeze = UpNextFreeze()
    @State private var loadedSource: String?
    @State private var heroTask: Task<Void, Never>?
    /// hero 还在加载时按了「全屏观看」：会话一建好就转全屏。
    @State private var pendingFullScreen = false
    @State private var dwellTask: Task<Void, Never>?
    @Namespace private var focusScope

    var body: some View {
        NavigationStack(path: $path) {
            screen
                .navigationDestination(for: Drama.self) { drama in
                    DetailView(drama: drama)
                }
        }
    }

    private var screen: some View {
        ZStack(alignment: .topLeading) {
            TVTheme.background.ignoresSafeArea()
            switch feed.state {
            case .loading:
                FeedSkeleton()
            case .empty:
                VStack(spacing: 28) {
                    TVStatusView(icon: "sparkles", title: "暂时没有可播放的短剧", message: "稍后再来看看吧", expands: false)
                    TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                        Task { await loadFeed(force: true) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failure(message)
            case .loaded:
                if let drama = heroDrama {
                    stage(drama)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .focusScope(focusScope)
        .task(id: appState.selectedSource) {
            await loadFeed(force: false)
        }
        .onAppear {
            isVisible = true
            // 这部剧最后一集播完：推荐流换下一部（selection 跟着 commit，hero 随之换剧）。
            hero.onReachedEnd = { [feed] in feed.advance() }
            startHero()
        }
        .onDisappear {
            isVisible = false
            pendingFullScreen = false
            dwellTask?.cancel()
            stopHero()
        }
        .onReceive(hero.$session) { session in
            guard pendingFullScreen, session != nil else { return }
            // 等这一轮发布结束、hero.session 已经赋值后再转全屏。
            DispatchQueue.main.async { watchFullScreen() }
        }
        .onChange(of: feed.current?.id) { id in
            if let id { selection.commit(id) }
        }
        .onChange(of: selection.heroID) { _ in
            pendingFullScreen = false
            startHero()
        }
        .onPlayPauseCommand {
            hero.togglePause()
        }
        // 焦点在顶部标签栏时 SwiftUI 收不到播放键，由标签栏容器转发过来（见 KeepAliveTabBarController）。
        .onReceive(NotificationCenter.default.publisher(for: .feedHeroTogglePlayback)) { _ in
            if isVisible { hero.togglePause() }
        }
        .fullScreenCover(item: $fullScreen, onDismiss: startHero) { presentation in
            PlayerView(
                drama: presentation.drama,
                episodes: presentation.episodes,
                startIndex: presentation.startIndex,
                startPosition: presentation.startPosition,
                store: store
            )
        }
    }

    // MARK: - 布局

    private func stage(_ drama: Drama) -> some View {
        let shown = hero.session?.drama.id == drama.id ? hero.session?.drama ?? drama : drama
        let layout = HeroLayout.panel(videoSize: hero.status.videoSize)
        return ZStack(alignment: .topLeading) {
            HeroVideoPanel(drama: drama, videoSize: hero.status.videoSize, showsVideo: hero.status.showsVideo) {
                if let controller = hero.controller {
                    PlayerHostView(controller: controller)
                        .id(ObjectIdentifier(controller))
                }
            }
            // 信息栏与「接下来」放在同一列、底部对齐，中间固定留 40 pt：标题两行时也不会被海报挡住；
            // 有焦点时整列一起上移 40 pt（信息栏同时变淡），两者始终错开。
            VStack(alignment: .leading, spacing: Self.infoToRowSpacing) {
                HeroInfoPanel(
                    drama: shown,
                    isPreview: selection.previewID != nil,
                    status: hero.status,
                    autoAdvance: autoAdvance,
                    width: HeroLayout.infoWidth(vertical: layout.vertical),
                    isFollowing: store.isFollowing(shown),
                    defaultFocus: focusScope,
                    onWatch: watchFullScreen,
                    onRetry: startHero,
                    onTogglePause: hero.togglePause,
                    onFollow: { store.toggleFollow(shown) },
                    onEpisodes: { path.append(shown) }
                )
                .opacity(rowFocused ? 0.55 : 1)
                if !upNextDramas.isEmpty {
                    UpNextRow(dramas: upNextDramas, onFocus: focusUpNext, onCommit: commit)
                }
            }
            .padding(.leading, 80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .offset(y: columnOffset)
            .animation(.easeOut(duration: 0.3), value: rowFocused)
        }
        .frame(width: HeroVideoPanel<EmptyView>.canvas.width, height: HeroVideoPanel<EmptyView>.canvas.height, alignment: .topLeading)
    }

    /// 信息栏底部到「接下来」标题之间的固定间距。
    private static let infoToRowSpacing: CGFloat = 40

    /// 整列的纵向偏移：有「接下来」时海报底部压在屏幕下缘外 70 pt（行内上下各留 20 pt 给焦点放大），
    /// 有焦点时上移 40 pt；没有「接下来」时信息栏停在底部安全区（60 pt）之上。
    private var columnOffset: CGFloat {
        guard !upNextDramas.isEmpty else { return -80 }
        return rowFocused ? 50 : 90
    }

    private func failure(_ message: String) -> some View {
        TVFailureView(message: message) {
            Task { await loadFeed(force: true) }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - 状态

    /// 「接下来」实际显示的剧：行有焦点时是进入时的那一组（见 UpNextFreeze）。
    private var upNextDramas: [Drama] {
        let current = feed.upNext
        let ids = upNextFreeze.visibleIDs(current: current.map(\.id))
        return ids.compactMap { id in feed.dramas.first { $0.id == id } }
    }

    /// hero 现在放的剧：在预览就是预览的那部，否则是推荐流当前这部。
    private var heroDrama: Drama? {
        feed.dramas.first { $0.id == selection.heroID } ?? feed.current
    }

    private func loadFeed(force: Bool) async {
        let source = appState.selectedSource
        // 切回本页时 .task 会再跑一次：同一站源已加载过就不再请求。
        guard force || loadedSource != source || feed.dramas.isEmpty else { return }
        // 启动时用核心存着的推荐（立刻有内容）；往后由 FeedPaging 接着取新的。每次启动都强制刷新要等
        // 约 11 秒才凑够一屏（实测），留到第四阶段：先显示缓存、后台刷新接在后面。重试时才强制刷新。
        await feed.load(source: source, force: force)
        loadedSource = source
    }

    private func startHero() {
        heroTask?.cancel()
        heroTask = nil
        guard isVisible, fullScreen == nil, let drama = heroDrama else { return }
        heroTask = Task { await hero.play(drama, store: store) }
    }

    private func stopHero() {
        heroTask?.cancel()
        heroTask = nil
        hero.stop()
    }

    private func watchFullScreen() {
        guard let presentation = hero.fullScreenPresentation else {
            // 详情还没取回：记下来，会话建好后再转（不默默吞掉这次按键）。
            pendingFullScreen = true
            return
        }
        pendingFullScreen = false
        stopHero()
        fullScreen = presentation
    }

    private func focusUpNext(_ id: String?) {
        rowFocused = id != nil
        upNextFreeze.rowFocusChanged(isFocused: id != nil, currentIDs: feed.upNext.map(\.id))
        selection.focus(id)
        dwellTask?.cancel()
        guard let id else { return }
        dwellTask = Task {
            try? await Task.sleep(for: PreviewSelection.dwell)
            guard !Task.isCancelled else { return }
            selection.dwellElapsed(for: id)
        }
    }

    private func commit(_ drama: Drama) {
        dwellTask?.cancel()
        selection.commit(drama.id)
        feed.select(drama)
        // 像以前一样刷新这一行（换成新 hero 之后的那一组）；按下后 1.5 秒内不自动预览（PreviewSelection）。
        upNextFreeze.refresh(currentIDs: feed.upNext.map(\.id))
    }
}

extension Notification.Name {
    /// 焦点在标签栏、选中推荐页时按了播放/暂停键。
    static let feedHeroTogglePlayback = Notification.Name("guoapp.feedHeroTogglePlayback")
}

/// 推荐页骨架：左侧信息栏各行 + 右侧竖屏面板，整体扫光（见 Skeleton.swift）。
private struct FeedSkeleton: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(TVTheme.surfaceDim)
                .frame(width: HeroLayout.verticalPanel.width, height: HeroLayout.verticalPanel.height)
                .offset(x: HeroLayout.verticalPanel.minX, y: HeroLayout.verticalPanel.minY)
            VStack(alignment: .leading, spacing: 22) {
                block(width: 96, height: 34)
                block(width: 420, height: 28)
                block(width: 860, height: 84)
                block(width: 620, height: 84)
                block(width: 900, height: 28)
                block(width: 700, height: 28)
                HStack(spacing: 24) {
                    block(width: 250, height: 72)
                    block(width: 170, height: 72)
                    block(width: 160, height: 72)
                }
                .padding(.top, 8)
            }
            .padding(.leading, 80)
            .padding(.top, 250)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shimmering()
    }

    private func block(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(TVTheme.surface)
            .frame(width: width, height: height)
    }
}
