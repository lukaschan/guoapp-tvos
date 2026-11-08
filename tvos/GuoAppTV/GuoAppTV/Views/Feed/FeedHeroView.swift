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
    /// 「我的」→ 进入推荐页自动播放；关掉时 hero 先停在封面，按播放键或「播放」才开始（不联网）。
    @AppStorage("heroAutoplay") private var heroAutoplay = true
    /// 自动播放关着时，用户这次进入推荐页后已经按过播放：之后照常连播、换剧，离开本页再重置。
    @State private var userStartedHero = false

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
            userStartedHero = false
            pendingFullScreen = false
            dwellTask?.cancel()
            stopHero()
        }
        .onReceive(hero.$session) { session in
            guard pendingFullScreen, session != nil else { return }
            // 等这一轮发布结束、hero.session 已经赋值后再转全屏。
            DispatchQueue.main.async { watchFullScreen() }
        }
        .onChange(of: feed.state) { state in
            // 推荐页第一屏出来了（缓存或新取的）：后台检查追剧更新（6 小时内查过的跳过）。
            if state == .loaded { FollowUpdateChecker.shared.checkIfDue(store: store) }
        }
        .onChange(of: feed.current?.id) { id in
            if let id { selection.commit(id) }
        }
        // 只有选定的剧变了（按下海报、播完换下一部）才换会话；预览只换封面和介绍，不重新加载。
        .onChange(of: selection.committedID) { _ in
            pendingFullScreen = false
            startHero()
        }
        // 预览：焦点停 1 秒的那部开始实时播放，选定的这部原地暂停；焦点离开这一行时它回来。
        // 用户按过暂停时预览停在第一帧，换海报、回来都仍停着，直到再按继续（HeroPauseIntent）。
        // 自动播放关着、还没开始时不预览（不联网、不出声）。
        .onChange(of: selection.previewID) { previewID in
            guard let previewID else {
                hero.endPreview()
                return
            }
            guard !isIdle, let drama = feed.dramas.first(where: { $0.id == previewID }) else { return }
            hero.startPreview(drama, store: store)
        }
        // 切到别的标签时立刻停（不等页面消失的回调，免得推荐的声音再响一两秒）；切回来再起播。
        .onReceive(NotificationCenter.default.publisher(for: .tabSelectionChanged)) { note in
            guard let index = note.object as? Int else { return }
            if index == KeepAliveTabBarController.feedTabIndex {
                startHero()
            } else {
                stopHero()
            }
        }
        .onPlayPauseCommand {
            togglePlayback()
        }
        // 焦点在顶部标签栏时 SwiftUI 收不到播放键，由标签栏容器转发过来（见 KeepAliveTabBarController）。
        .onReceive(NotificationCenter.default.publisher(for: .feedHeroTogglePlayback)) { _ in
            if isVisible { togglePlayback() }
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
            // 两个播放器（选定的这部、预览那部）的画面都一直挂着，只显示看得见的那个：
            // 切换时不拆掉 mpv、不重新加载；预览出画面之前先显示它的封面。
            HeroVideoPanel(drama: drama, videoSize: hero.status.videoSize, showsVideo: hero.status.showsVideo) {
                ForEach(hero.hosts) { host in
                    PlayerHostView(controller: host.controller)
                        .opacity(host.visible ? 1 : 0)
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
                    onRetry: {
                        stopHero()
                        startHero()
                    },
                    onTogglePause: togglePlayback,
                    isIdle: isIdle,
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
        // 先显示核心存着的推荐（立刻有内容），这次启动第一次加载这个站源（或点了重试）时在后台
        // 让核心取一份新的，接到 hero 后面（FeedModel.load）。
        await feed.load(source: source, force: force || loadedSource != source)
        loadedSource = source
    }

    /// 自动播放关着、用户还没按过播放：hero 停在封面，不取详情、不起播。
    private var isIdle: Bool { !heroAutoplay && !userStartedHero }

    /// 播放键 / 「暂停 · 继续 · 播放」按钮：停在封面时开始播放，否则暂停 / 继续。
    private func togglePlayback() {
        if isIdle {
            userStartedHero = true
            startHero()
        } else {
            hero.togglePause()
        }
    }

    /// 会话播的剧：选定的那部（预览不换会话）。
    private var committedDrama: Drama? {
        feed.dramas.first { $0.id == selection.committedID } ?? feed.current
    }

    private func startHero() {
        guard isVisible, fullScreen == nil, !isIdle, let drama = committedDrama else { return }
        // 已经在播（或正在加载）这一部：不重来（例如预览转正、在推荐页上又选中了推荐标签）。
        guard hero.mainDramaID != drama.id else { return }
        heroTask?.cancel()
        heroTask = nil
        heroTask = Task { await hero.play(drama, store: store) }
    }

    private func stopHero() {
        heroTask?.cancel()
        heroTask = nil
        hero.stop()
    }

    private func watchFullScreen() {
        guard let presentation = hero.fullScreenPresentation else {
            // 详情还没取回：记下来，会话建好后再转（不默默吞掉这次按键）；停在封面时先开始。
            pendingFullScreen = true
            if isIdle {
                userStartedHero = true
                startHero()
            }
            return
        }
        pendingFullScreen = false
        // 用户主动转全屏看这部：追剧更新的角标消失（自动播放和预览不算）。
        store.acknowledgeUpdate(dramaID: presentation.drama.id)
        stopHero()
        fullScreen = presentation
    }

    private func focusUpNext(_ id: String?) {
        rowFocused = id != nil
        feed.setRowFocused(id != nil)
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
        // 按下的正是在预览的那部：预览直接转正（不重新加载）；按下别的：选定的这部马上被换掉，不必再接着播。
        if drama.id != selection.committedID, !hero.promotePreview(dramaID: drama.id) {
            hero.abandonPreview()
        }
        selection.commit(drama.id)
        feed.select(drama)
        // 像以前一样刷新这一行（换成新 hero 之后的那一组）；按下后 1.5 秒内不自动预览（PreviewSelection）。
        upNextFreeze.refresh(currentIDs: feed.upNext.map(\.id))
    }
}

extension Notification.Name {
    /// 焦点在标签栏、选中推荐页时按了播放/暂停键。
    static let feedHeroTogglePlayback = Notification.Name("guoapp.feedHeroTogglePlayback")
    /// 标签切换了（object 为新选中的下标，见 KeepAliveTabBarController）。
    static let tabSelectionChanged = Notification.Name("guoapp.tabSelectionChanged")
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
