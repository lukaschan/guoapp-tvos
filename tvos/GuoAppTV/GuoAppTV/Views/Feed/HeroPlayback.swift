import Combine
import Foundation

/// 推荐页 hero 的播放：每部剧只放 10 秒预告（HeroTeaser），想看就全屏观看。两个「槽」：
/// - main：选定的这部（全屏观看看它）；
/// - preview：焦点在「接下来」某张海报上时这一部的预告。还没在预览时，焦点停 0.3 秒就在后台
///  （不可见、停着）开始加载，停满 1 秒才显示；已经在预览时换海报，停满 1 秒再加载。
/// 预览期间 main 原地暂停、不重新加载；焦点离开这一行时预览关掉、main 回来。暂停只看用户按了什么
/// （HeroPauseIntent）：按了暂停，预览也停在第一帧，换海报、回到 main 都仍停着，直到再按继续。
/// 按下正在预览（或已在后台加载）的那张海报，它直接转正成 main（不重新加载）并播放。
/// 预告播完淡出回到封面、释放播放器；再按播放键重播一遍。
/// 两个槽的画面都一直挂着（hosts，按控制器区分，不重建），只是显示可见的那个；界面只观察这一个对象。
@MainActor
final class HeroPlayback: ObservableObject {
    struct Status: Equatable {
        var videoSize: CGSize?
        /// 已出画面（时长已知）、预告还没播完。
        var showsVideo = false
        var episode: Int?
        /// 预告已播的比例。
        var fraction: Double?
        var paused = false
        /// 预告播完了：回到封面，按播放键重播。
        var finished = false
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

    /// main 槽的会话（转全屏前的等待看它）。
    @Published private(set) var session: PlaybackSession?
    /// 可见那个槽的状态（预览时是预览那部的）。
    @Published private(set) var status = Status()
    @Published private(set) var hosts: [Host] = []
    @Published private(set) var isPreviewing = false
    /// 可见那个槽详情补全后的剧（总集数等）；预告播完、播放器释放后也还在，信息栏不会跟着变。
    @Published private(set) var shownDrama: Drama?

    private var main = HeroSlot()
    private var preview = HeroSlot()
    private var intent = HeroPauseIntent()
    private var previewTask: Task<Void, Never>?
    private var replayTask: Task<Void, Never>?

    init() {
        main.onChange = { [weak self] in self?.publish() }
        preview.onChange = { [weak self] in self?.publish() }
    }

    /// main 槽正在播（或正在加载、已播完预告）的剧。
    var mainDramaID: String? { main.dramaID }

    /// 换到这部剧（main）：先关掉预览，停掉旧的，新建会话放预告（选定就是要播，不沿用暂停）。
    func play(_ drama: Drama, store: Store) async {
        replayTask?.cancel()
        replayTask = nil
        closePreview()
        intent.choose()
        await main.play(drama, store: store, paused: false)
        publish()
    }

    /// 离开推荐页 / 转全屏：两个槽都停（先暂停再销毁）。
    func stop() {
        replayTask?.cancel()
        replayTask = nil
        closePreview()
        main.stop()
        intent.choose()
        publish()
    }

    /// 焦点在某张海报上停了 0.3 秒、还没在预览：在后台加载它的预告（不可见、停着），main 照常播。
    func preparePreview(_ drama: Drama, store: Store) {
        guard !isPreviewing, preview.dramaID != drama.id else { return }
        loadPreview(drama, store: store, paused: true)
    }

    /// 焦点停满 1 秒：显示这一部的预告，main 原地暂停（还在加载的，加载完也停着）。
    /// 已在后台加载的直接显示；用户按过暂停时停在第一帧、不出声。
    func startPreview(_ drama: Drama, store: Store) {
        if !isPreviewing {
            isPreviewing = true
            intent.beginPreview()
            main.pause()
        }
        guard preview.dramaID != drama.id else {
            if intent.previewPaused {
                preview.pause()
            } else {
                preview.resume()
            }
            publish()
            return
        }
        loadPreview(drama, store: store, paused: intent.previewPaused)
    }

    /// 焦点离开「接下来」：关掉预览（含后台加载、还没显示的），main 回来——用户没按暂停才接着播。
    func endPreview() {
        let wasPreviewing = isPreviewing
        closePreview()
        if wasPreviewing, !intent.mainPaused { main.resume() }
        publish()
    }

    /// 按下正在预览（或已在后台加载）的那部：直接转正成 main（不重新加载）并播放。返回是否转正了。
    func promotePreview(dramaID: String) -> Bool {
        guard preview.dramaID == dramaID else { return false }
        // 还在加载的那次交给 replayTask 管：之后 stop() / 换剧时照样能取消它。
        replayTask?.cancel()
        replayTask = previewTask
        previewTask = nil
        main.stop()
        let promoted = preview
        preview = main
        main = promoted
        isPreviewing = false
        intent.choose()
        if main.isFinished {
            replay(main)
        } else {
            main.resume()
        }
        publish()
        return true
    }

    /// 按下另一张（不是正在预览的）海报换剧：关掉预览，main 马上要被换掉，停着不再接着播。
    func abandonPreview() {
        closePreview()
        publish()
    }

    /// 播放键 / 暂停按钮：控制看得见的那个，并记下用户的选择（之后换海报、回到 main 都照这个来）；
    /// 预告播完了就重播一遍。
    func togglePause() {
        let slot = isPreviewing ? preview : main
        if slot.isFinished {
            _ = intent.toggle(visiblePaused: true)
            replay(slot)
            return
        }
        if intent.toggle(visiblePaused: slot.isPaused) {
            slot.pause()
        } else {
            slot.resume()
        }
    }

    /// 转到全屏播放：看过的回到上次看到的位置，没看过的从预告播到的地方接着播。
    var fullScreenPresentation: PlaybackPresentation? {
        main.fullScreenPresentation
    }

    private func loadPreview(_ drama: Drama, store: Store, paused: Bool) {
        previewTask?.cancel()
        preview.stop()
        publish()
        let slot = preview
        previewTask = Task { [weak self] in
            await slot.play(drama, store: store, paused: paused)
            self?.publish()
        }
    }

    private func replay(_ slot: HeroSlot) {
        let task = Task { [weak self] in
            await slot.replay()
            self?.publish()
        }
        if slot === preview {
            previewTask?.cancel()
            previewTask = task
        } else {
            replayTask?.cancel()
            replayTask = task
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        previewTask = nil
        preview.stop()
        isPreviewing = false
        intent.endPreview()
    }

    private func publish() {
        if session !== main.session { session = main.session }
        let visible = isPreviewing ? preview : main
        if visible.status != status { status = visible.status }
        let drama = visible.resolvedDrama
        if drama != shownDrama { shownDrama = drama }
        let nextHosts = [main, preview].compactMap { slot in
            slot.session.map { Host(controller: $0.controller, visible: slot === visible) }
        }
        if nextHosts != hosts { hosts = nextHosts }
    }
}

/// hero 的一个播放槽：一部剧的预告会话、汇总给界面的状态。
/// 每换一部剧新建 PlayerController 与 PlaybackSession（会话 stop() 会让控制器不再起播，所以不复用）。
/// 预告不记观看进度、不接着播下一集：这一集的播完事件和 10 秒到点一样，都是预告播完。
@MainActor
final class HeroSlot {
    /// 播完后淡出封面的时间，之后才释放播放器（与 HeroVideoPanel 的封面淡入一致）。
    static let fadeOut: Duration = .milliseconds(500)

    private(set) var session: PlaybackSession?
    private(set) var status = HeroPlayback.Status()
    /// 正在放（或正在加载、已播完）预告的剧；加载期间就有，转正时用它认出是哪一部。
    private(set) var dramaID: String?
    /// 预告播完了（淡出后释放会话，保留全屏观看与重播要用的信息）。
    private(set) var isFinished = false

    var onChange: (() -> Void)?

    /// 该停着：加载途中就记下，播放器起播时照这个停在第一帧（PlayerController.startsPaused）。
    private var wantsPaused = false
    private var loadError: String?
    private var subscriptions: Set<AnyCancellable> = []
    private var teaser: Teaser?
    private var store: Store?
    private var releaseTask: Task<Void, Never>?
    /// 这次起播的计时：开始放、详情取回的时间；出画面时写一行到 HeroTimingLog。
    private var timing: (title: String, start: Date, detail: Date?, paused: Bool)?

    /// 这次预告：放的是哪一集、看过时的续播目标、播到的位置与画面尺寸。
    private struct Teaser {
        /// 传进来的剧（重播用）与详情补全后的剧（全屏观看用）。
        let drama: Drama
        let resolved: Drama
        let episodes: [Episode]
        let index: Int
        let saved: ResumeTarget?
        var position: Double = 0
        var videoSize: CGSize?
    }

    /// 详情补全后的剧（放预告期间与播完后都有）。
    var resolvedDrama: Drama? { teaser?.resolved }

    /// 看起来停着：要它停着（含还在加载的），或播放器自己停着。
    var isPaused: Bool { wantsPaused || (session?.controller.isPaused ?? false) }

    func pause() { setPaused(true) }
    func resume() { setPaused(false) }

    var fullScreenPresentation: PlaybackPresentation? {
        guard let teaser else { return nil }
        let position = isFinished ? teaser.position : session?.currentPosition ?? 0
        let start = HeroTeaser.fullScreenStart(saved: teaser.saved, teaserIndex: teaser.index, teaserPosition: position)
        return PlaybackPresentation(
            drama: teaser.resolved,
            episodes: teaser.episodes,
            startIndex: start.index,
            startPosition: start.position
        )
    }

    /// 放这部剧的预告：停掉旧的，取详情（「接下来」一出现就已后台取好），从看到的那一集开头起播；
    /// paused 时停在第一帧（加载途中按了暂停 / 继续也照最新的来）。
    func play(_ drama: Drama, store: Store, paused: Bool) async {
        stop()
        dramaID = drama.id
        wantsPaused = paused
        self.store = store
        timing = (drama.title, Date(), nil, paused)
        refreshStatus()
        do {
            let detail = try await DetailPrefetch.shared.detail(for: drama)
            guard !Task.isCancelled, dramaID == drama.id else { return }
            timing?.detail = Date()
            let latest = store.latestProgress(for: drama.id)
            let numbers = detail.episodes.map(\.number)
            let releaseStatus = detail.drama.releaseStatus
            guard let start = HeroTeaser.start(
                episodeNumbers: numbers,
                latestEpisode: latest?.episode,
                position: latest?.position ?? 0,
                duration: latest?.duration ?? 0,
                releaseStatus: releaseStatus
            ) else {
                fail("暂无可播放的分集")
                return
            }
            let saved = latest.flatMap {
                ResumeTarget.playbackStart(
                    episodeNumbers: numbers, latestEpisode: $0.episode,
                    position: $0.position, duration: $0.duration, releaseStatus: releaseStatus
                )
            }
            // 与播放启动器一致：用详情里的剧信息（补上总集数），解析不出 id 时退回传入的剧。
            let resolved = PlaybackLauncher.withEpisodeCount(
                detail.drama.id.isEmpty ? drama : detail.drama, detail.episodes.count
            )
            let controller = PlayerController()
            // 屏保按电视的设置照常出现（owner 2026-11-08），不像全屏播放那样一直亮屏。
            controller.keepsScreenAwake = false
            controller.startsPaused = wantsPaused
            controller.readAheadBytes = HeroTeaser.readAheadBytes
            let session = PlaybackSession(
                drama: resolved,
                episodes: detail.episodes,
                startIndex: start.index,
                startPosition: 0,
                store: store,
                controller: controller
            )
            // 预告不算看过：不记进度。
            session.saveGate = { _ in false }
            session.allowsDanmaku = false
            teaser = Teaser(drama: drama, resolved: resolved, episodes: detail.episodes, index: start.index, saved: saved)
            self.session = session
            bind(session)
            session.start()
            refreshStatus()
        } catch {
            guard !Task.isCancelled, dramaID == drama.id else { return }
            fail(UserFacingError.message(for: error))
        }
    }

    /// 预告播完后按播放键：从头再放一遍。
    func replay() async {
        guard let teaser, let store else { return }
        await play(teaser.drama, store: store, paused: false)
    }

    /// 停掉：先暂停再销毁（mpv 在 Apple TV 上的音频输出缓冲约 2 秒，直接销毁时这段声音会接着响完），释放会话。
    func stop() {
        releaseTask?.cancel()
        releaseTask = nil
        subscriptions.removeAll()
        session?.controller.pause()
        session?.stop()
        session = nil
        dramaID = nil
        wantsPaused = false
        isFinished = false
        teaser = nil
        timing = nil
        loadError = nil
        refreshStatus()
    }

    /// 播放器还没起播时 pause()/resume() 不起作用，所以同时改 startsPaused：加载完照这个停着或播放。
    /// 预告播完后不再动（重播走 replay）。
    private func setPaused(_ paused: Bool) {
        guard !isFinished else { return }
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

    private func fail(_ message: String) {
        loadError = message
        refreshStatus()
    }

    /// 预告播满（或这一集先播完）：停住、封面淡入，淡出后释放播放器。
    private func finish() {
        guard !isFinished, let session else { return }
        isFinished = true
        session.controller.pause()
        teaser?.position = session.currentPosition
        teaser?.videoSize = session.controller.videoSize
        refreshStatus()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.fadeOut)
            guard !Task.isCancelled else { return }
            self?.releaseFinished()
        }
    }

    private func releaseFinished() {
        guard isFinished else { return }
        subscriptions.removeAll()
        session?.stop()
        session = nil
        refreshStatus()
        // 状态没变（已是播完），但画面里要拿掉这个播放器。
        onChange?()
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
            .sink { [weak self] _ in self?.finish() }
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
        guard progress.duration > 0 else { return }
        if let timing, let session {
            HeroTimingLog.record(
                title: timing.title, start: timing.start, detail: timing.detail,
                playerStarted: session.controller.startedAt, paused: timing.paused
            )
            self.timing = nil
        }
        guard HeroTeaser.isFinished(position: progress.position, ended: false) else { return }
        finish()
    }

    private func refreshStatus() {
        var next = HeroPlayback.Status()
        if isFinished, let teaser {
            next.videoSize = teaser.videoSize
            next.episode = teaser.episodes.indices.contains(teaser.index) ? teaser.episodes[teaser.index].number : nil
            next.fraction = 1
            next.paused = true
            next.finished = true
        } else if let session {
            let controller = session.controller
            let progress = controller.progress
            let index = session.currentIndex
            let hasDuration = progress.duration > 0
            next.videoSize = controller.videoSize
            next.showsVideo = hasDuration
            next.episode = session.episodes.indices.contains(index) ? session.episodes[index].number : nil
            next.fraction = hasDuration ? HeroTeaser.fraction(position: progress.position) : nil
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

/// 推荐页预告的起播耗时，一部一行写到 Caches/hero-timing.log（排查「预览出画面慢」用，可从电视上拷出来）：
/// 详情多久取回、多久开始起播（解析地址 + 挂上画面）、起播后多久出画面（mpv 初始化 + 取流 + 解码）。
@MainActor
enum HeroTimingLog {
    private static let maxBytes = 64 * 1024

    static func record(title: String, start: Date, detail: Date?, playerStarted: Date?, paused: Bool) {
        let now = Date()
        func ms(_ from: Date?, _ to: Date?) -> String {
            guard let from, let to else { return "-" }
            return String(Int(to.timeIntervalSince(from) * 1000))
        }
        let stamp = ISO8601DateFormatter().string(from: now)
        let line = "\(stamp) detail=\(ms(start, detail))ms start=\(ms(detail, playerStarted))ms "
            + "video=\(ms(playerStarted, now))ms total=\(ms(start, now))ms \(paused ? "preloaded" : "visible") \(title)\n"
        guard let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("hero-timing.log") else { return }
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        text += line
        if text.utf8.count > maxBytes { text = String(text.suffix(maxBytes / 2)) }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
