import Combine
import Foundation

/// 推荐页 hero 的播放，两个「槽」：
/// - main：选定的这部（选集、播完换下一部、全屏观看都看它）；
/// - preview：焦点停在「接下来」某张海报上时，这一部的实时预览（有画面有声音）。
/// 预览期间 main 原地暂停、不重新加载；焦点离开这一行时预览关掉、main 回来。暂停只看用户按了什么
/// （HeroPauseIntent）：按了暂停，预览也停在第一帧，换海报、回到 main 都仍停着，直到再按继续。
/// 按下正在预览的那张海报时，预览直接转正成 main（不重新加载）并播放。
/// 两个槽的画面都一直挂着（hosts，按控制器区分，不重建），只是显示可见的那个；界面只观察这一个对象。
/// 【设计已锁定】owner 2026-11-08：推荐页 hero 的实时视频设计不要再改（含版式、观感与机制），改动须 owner 明确同意；
/// 见 docs/superpowers/specs/2026-11-08-hero-live-video-design.md。
@MainActor
final class HeroPlayback: ObservableObject {
    struct Status: Equatable {
        var videoSize: CGSize?
        /// 已出画面（时长已知）。
        var showsVideo = false
        var episode: Int?
        var fraction: Double?
        var remaining: Double?
        var isLastEpisode = false
        var paused = false
        var error: String?
    }

    /// 一个要挂在画面里的播放器；visible 的那个显示，另一个透明（不拆掉，避免重建 mpv）。
    struct Host: Identifiable, Equatable {
        let controller: PlayerController
        let visible: Bool

        var id: ObjectIdentifier { ObjectIdentifier(controller) }

        static func == (lhs: Host, rhs: Host) -> Bool {
            lhs.id == rhs.id && lhs.visible == rhs.visible
        }
    }

    /// main 槽的会话（全屏观看、转全屏前的等待都看它）。
    @Published private(set) var session: PlaybackSession?
    /// 可见那个槽的状态（预览时是预览那部的）。
    @Published private(set) var status = Status()
    @Published private(set) var hosts: [Host] = []
    @Published private(set) var isPreviewing = false
    /// main 这部剧的最后一集播完：换下一部。
    var onReachedEnd: (() -> Void)?

    private var main = HeroSlot()
    private var preview = HeroSlot()
    private var intent = HeroPauseIntent()
    private var previewTask: Task<Void, Never>?

    init() {
        wire(main)
        wire(preview)
    }

    /// main 槽正在播（或正在加载）的剧。
    var mainDramaID: String? { main.dramaID }

    /// 换到这部剧（main）：先关掉预览，停掉旧的，按观看记录定起点新建会话起播（选定就是要播，不沿用暂停）。
    func play(_ drama: Drama, store: Store) async {
        closePreview()
        intent.choose()
        await main.play(drama, store: store, paused: false)
        publish()
    }

    /// 离开推荐页 / 转全屏 / 换剧：两个槽都停（先暂停再销毁）。
    func stop() {
        closePreview()
        main.stop()
        intent.choose()
        publish()
    }

    /// 焦点停在「接下来」某张海报上：main 原地暂停（还在加载的，加载完也停着），预览那部开始实时播放；
    /// 用户按过暂停时预览停在第一帧、不出声。
    func startPreview(_ drama: Drama, store: Store) {
        if !isPreviewing {
            isPreviewing = true
            intent.beginPreview()
            main.pause()
        }
        previewTask?.cancel()
        preview.stop()
        publish()
        let slot = preview
        let paused = intent.previewPaused
        previewTask = Task { [weak self] in
            await slot.play(drama, store: store, paused: paused)
            self?.publish()
        }
    }

    /// 焦点离开「接下来」：关掉预览，main 回来——用户没按暂停才接着播。
    func endPreview() {
        guard isPreviewing else { return }
        closePreview()
        if !intent.mainPaused { main.resume() }
        publish()
    }

    /// 按下正在预览的那部：预览直接转正成 main（不重新加载）并播放。返回是否转正了。
    func promotePreview(dramaID: String) -> Bool {
        guard isPreviewing, preview.dramaID == dramaID else { return false }
        previewTask = nil
        main.stop()
        let promoted = preview
        preview = main
        main = promoted
        isPreviewing = false
        intent.choose()
        main.resume()
        publish()
        return true
    }

    /// 按下另一张（不是正在预览的）海报换剧：关掉预览，main 马上要被换掉，停着不再接着播。
    func abandonPreview() {
        closePreview()
        publish()
    }

    /// 播放键 / 暂停按钮：控制看得见的那个，并记下用户的选择（之后换海报、回到 main 都照这个来）。
    func togglePause() {
        let slot = isPreviewing ? preview : main
        if intent.toggle(visiblePaused: slot.isPaused) {
            slot.pause()
        } else {
            slot.resume()
        }
    }

    /// 转到全屏播放：从 main 当前这集、当前位置接着播。
    var fullScreenPresentation: PlaybackPresentation? {
        main.fullScreenPresentation
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        preview.stop()
        isPreviewing = false
        intent.endPreview()
    }

    private func wire(_ slot: HeroSlot) {
        slot.onChange = { [weak self] in self?.publish() }
        slot.onReachedEnd = { [weak self, weak slot] in
            guard let self, let slot, slot === self.main else { return }
            self.onReachedEnd?()
        }
    }

    private func publish() {
        if session !== main.session { session = main.session }
        let visible = isPreviewing ? preview : main
        if visible.status != status { status = visible.status }
        let nextHosts = [main, preview].compactMap { slot in
            slot.session.map { Host(controller: $0.controller, visible: slot === visible) }
        }
        if nextHosts != hosts { hosts = nextHosts }
    }
}

/// hero 的一个播放槽：一部剧的会话、汇总给界面的状态。不记观看进度（只有全屏播放记，owner 2026-11-08）。
/// 每换一部剧新建 PlayerController 与 PlaybackSession（会话 stop() 会让控制器不再起播，所以不复用）。
@MainActor
final class HeroSlot {
    private(set) var session: PlaybackSession?
    private(set) var status = HeroPlayback.Status()
    /// 正在播（或正在加载）的剧；加载期间就有，转正时用它认出是哪一部。
    private(set) var dramaID: String?
    /// 该停着：加载途中就记下，播放器起播时照这个停在第一帧（PlayerController.startsPaused）。
    private var wantsPaused = false

    var onChange: (() -> Void)?
    var onReachedEnd: (() -> Void)?

    private var loadError: String?
    private var subscriptions: Set<AnyCancellable> = []

    /// 看起来停着：要它停着（含还在加载的），或播放器自己停着。
    var isPaused: Bool { wantsPaused || (session?.controller.isPaused ?? false) }

    func pause() { setPaused(true) }
    func resume() { setPaused(false) }

    /// 播放器还没起播时 pause()/resume() 不起作用，所以同时改 startsPaused：加载完照这个停着或播放。
    private func setPaused(_ paused: Bool) {
        wantsPaused = paused
        if let controller = session?.controller {
            controller.startsPaused = paused
            if paused {
                controller.pause()
            } else {
                controller.resume()
            }
        }
        refreshStatus()
    }

    var fullScreenPresentation: PlaybackPresentation? {
        guard let session else { return nil }
        return PlaybackPresentation(
            drama: session.drama,
            episodes: session.episodes,
            startIndex: session.currentIndex,
            startPosition: session.currentPosition
        )
    }

    /// 播这部剧：停掉旧的，取详情、按观看记录定起点（没看过从第 1 集开头），新建会话起播；
    /// paused 时停在第一帧（加载途中按了暂停 / 继续也照最新的来）。
    func play(_ drama: Drama, store: Store, paused: Bool) async {
        stop()
        dramaID = drama.id
        wantsPaused = paused
        refreshStatus()
        do {
            let detail = try await CoreClient.shared.detail(drama: drama)
            guard !Task.isCancelled, dramaID == drama.id else { return }
            let latest = store.latestProgress(for: drama.id)
            guard let target = ResumeTarget.playbackStart(
                episodeNumbers: detail.episodes.map(\.number),
                latestEpisode: latest?.episode,
                position: latest?.position ?? 0,
                duration: latest?.duration ?? 0,
                releaseStatus: detail.drama.releaseStatus
            ) else {
                fail("暂无可播放的分集")
                return
            }
            // 与播放启动器一致：用详情里的剧信息（补上总集数），解析不出 id 时退回传入的剧。
            let resolved = PlaybackLauncher.withEpisodeCount(
                detail.drama.id.isEmpty ? drama : detail.drama, detail.episodes.count
            )
            let controller = PlayerController()
            // 屏保按电视的设置照常出现（owner 2026-11-08），不像全屏播放那样一直亮屏。
            controller.keepsScreenAwake = false
            // 图层固定铺满画布，画面由 mpv 按视频方向摆到面板上（mpv 不跟随图层尺寸变化）。
            controller.framing = { HeroLayout.mpvMargins(videoSize: $0) }
            controller.startsPaused = wantsPaused
            let session = PlaybackSession(
                drama: resolved,
                episodes: detail.episodes,
                startIndex: target.index,
                startPosition: target.position,
                store: store,
                controller: controller
            )
            // 推荐页的播放不算看过：观看记录、「看过的剧」、继续观看只来自全屏播放（owner 2026-11-08）。
            session.saveGate = { _ in false }
            session.allowsDanmaku = false
            session.onReachedEnd = { [weak self] in self?.onReachedEnd?() }
            self.session = session
            bind(session)
            session.start()
            refreshStatus()
        } catch {
            guard !Task.isCancelled, dramaID == drama.id else { return }
            fail(UserFacingError.message(for: error))
        }
    }

    /// 停掉：先暂停再销毁（mpv 在 Apple TV 上的音频输出缓冲约 2 秒，直接销毁时这段声音会接着响完），
    /// 释放会话（不存进度）。
    func stop() {
        subscriptions.removeAll()
        session?.controller.pause()
        session?.stop()
        session = nil
        dramaID = nil
        wantsPaused = false
        loadError = nil
        refreshStatus()
    }

    private func fail(_ message: String) {
        loadError = message
        refreshStatus()
    }

    /// 播放器的 @Published 在 willSet 时发出，统一切到下一轮主队列再读状态，读到的是改完后的值，
    /// 也避免在播放器自己改状态的途中同步重入会话。
    private func bind(_ session: PlaybackSession) {
        let controller = session.controller
        controller.$progress
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.progressed(value) }
            .store(in: &subscriptions)
        controller.$endedToken
            .dropFirst()
            .removeDuplicates()
            .filter { $0 > 0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak session] _ in session?.handleEnded() }
            .store(in: &subscriptions)
        controller.$failedToken
            .dropFirst()
            .removeDuplicates()
            .filter { $0 > 0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak session] _ in
                Task { await session?.handleFailed() }
            }
            .store(in: &subscriptions)
        controller.objectWillChange
            .merge(with: session.objectWillChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshStatus() }
            .store(in: &subscriptions)
    }

    private func progressed(_ progress: PlaybackProgress) {
        guard let session else { return }
        // 交给会话：预取下一集等照常（存进度被 saveGate 挡掉）。
        session.handleProgress(position: progress.position, duration: progress.duration)
    }

    private func refreshStatus() {
        var next = HeroPlayback.Status()
        if let session {
            let controller = session.controller
            let progress = controller.progress
            let index = session.currentIndex
            let hasDuration = progress.duration > 0
            next.videoSize = controller.videoSize
            next.showsVideo = hasDuration
            next.episode = session.episodes.indices.contains(index) ? session.episodes[index].number : nil
            next.fraction = hasDuration ? min(max(progress.position / progress.duration, 0), 1) : nil
            next.remaining = hasDuration ? max(progress.duration - progress.position, 0) : nil
            next.isLastEpisode = index >= session.episodes.count - 1
            next.paused = isPaused
            next.error = session.error.map { UserFacingError.message(for: $0) }
        } else {
            next.paused = wantsPaused
            next.error = loadError
        }
        guard next != status else { return }
        status = next
        onChange?()
    }
}
