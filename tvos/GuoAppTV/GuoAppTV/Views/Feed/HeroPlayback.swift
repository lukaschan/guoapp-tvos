import Combine
import Foundation

/// 推荐页 hero 的播放：每换一部剧新建一个 PlayerController 与 PlaybackSession
/// （会话 stop() 会让控制器不再起播，所以控制器不复用），只有「真正看满 30 秒」才存进度。
/// 把播放器事件接到会话上，并汇总成一份 status 给界面；界面只观察这一个对象，
/// 换剧时按钮与「接下来」一行不会重建，焦点不丢。
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

    @Published private(set) var session: PlaybackSession?
    @Published private(set) var status = Status()
    /// 这部剧的最后一集播完：换下一部。
    var onReachedEnd: (() -> Void)?

    private var gate = WatchGate()
    /// 「接下来」预览期间这部原地暂停、预览结束原样回来（PreviewHold）。
    private var hold = PreviewHold()
    /// 这部已经出过画面（用来分辨「预览期间才出画面」）。
    private var videoShown = false
    private var loadError: String?
    private var subscriptions: Set<AnyCancellable> = []

    var controller: PlayerController? { session?.controller }

    /// 换到这部剧：停掉旧的，取详情、按观看记录定起点（没看过从第 1 集开头），新建会话起播。
    func play(_ drama: Drama, store: Store) async {
        stop()
        do {
            let detail = try await CoreClient.shared.detail(drama: drama)
            guard !Task.isCancelled else { return }
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
            let session = PlaybackSession(
                drama: resolved,
                episodes: detail.episodes,
                startIndex: target.index,
                startPosition: target.position,
                store: store,
                controller: controller
            )
            gate.reset()
            session.saveGate = { [weak self] _ in self?.gate.isOpen ?? false }
            session.allowsDanmaku = false
            session.onReachedEnd = { [weak self] in self?.onReachedEnd?() }
            self.session = session
            bind(session)
            session.start()
        } catch {
            guard !Task.isCancelled else { return }
            fail(UserFacingError.message(for: error))
        }
    }

    /// 离开推荐页 / 转全屏 / 换剧：存进度（过了 30 秒门槛才存）、销毁句柄、释放会话。
    func stop() {
        subscriptions.removeAll()
        // 先暂停再销毁：mpv 在 Apple TV 上的音频输出缓冲约 2 秒，直接销毁时这段声音会接着响完。
        session?.controller.pause()
        session?.stop()
        hold.reset()
        videoShown = false
        session = nil
        loadError = nil
        refreshStatus()
    }

    /// 焦点停在「接下来」某张海报上（预览）：只换封面和介绍，这部原地暂停（正在播的才暂停，之后接着播）。
    func beginPreview() {
        guard let controller else { return }
        if hold.begin(playing: videoShown && !controller.isPaused) { controller.pause() }
    }

    /// 按下海报换剧：这部马上要被换掉，预览结束时不要再让它接着播（否则会响一下再停）。
    func dropPreviewHold() {
        hold.reset()
    }

    /// 焦点离开「接下来」：这部原样回来——原本在播的接着播，用户自己暂停的仍暂停。
    func endPreview() {
        if hold.end() { controller?.resume() }
    }

    func togglePause() {
        guard let controller else { return }
        if controller.isPaused {
            controller.resume()
        } else {
            controller.pause()
        }
    }

    /// 转到全屏播放：从 hero 当前这集、当前位置接着播。
    var fullScreenPresentation: PlaybackPresentation? {
        guard let session else { return nil }
        return PlaybackPresentation(
            drama: session.drama,
            episodes: session.episodes,
            startIndex: session.currentIndex,
            startPosition: session.currentPosition
        )
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
        // 先计入门槛，再交给会话（会话这一拍若要存进度，看到的是最新的门槛）。
        if progress.duration > 0, !videoShown {
            videoShown = true
            // 预览期间才出画面：先停住，预览结束再接着播。
            if hold.videoStarted() { session.controller.pause() }
        }
        gate.observe(position: progress.position, paused: session.controller.isPaused)
        session.handleProgress(position: progress.position, duration: progress.duration)
    }

    private func refreshStatus() {
        var next = Status()
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
            next.paused = controller.isPaused
            next.error = session.error.map { UserFacingError.message(for: $0) }
        } else {
            next.error = loadError
        }
        if next != status { status = next }
    }
}
