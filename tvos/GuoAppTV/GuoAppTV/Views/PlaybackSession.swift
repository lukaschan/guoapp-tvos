import Foundation

/// 一次看剧的分集逻辑：起播、换集、播完自动下一集、失败换线路、预取下一集、落盘进度、退出时释放会话。
/// 全屏播放页与推荐页的 hero 共用；控件、焦点、弹窗等界面留在各自的视图里。
/// （从 PlayerView 原样搬来，规则判断见 PlaybackRules。）
@MainActor
final class PlaybackSession: ObservableObject {
    let drama: Drama
    let episodes: [Episode]
    let controller: PlayerController
    private let store: Store

    @Published private(set) var currentIndex: Int
    @Published private(set) var plan: PlaybackPlan?
    /// 出错时停掉句柄：恢复屏保（避免错误页常亮），重试时照常 load() → play()。
    @Published private(set) var error: String? {
        didSet {
            if error != nil { controller.halt() }
        }
    }

    /// 每次落盘进度前调用（参数为播放位置）；推荐页 hero 换成「真正看满 30 秒」的门槛。
    var saveGate: (Double) -> Bool = { _ in true }
    /// 最后一集播完（或关了自动连播）时调用；全屏播放页传 dismiss。
    var onReachedEnd: (() -> Void)?
    /// 是否允许弹幕（再与设置里的开关相与）；推荐页 hero 的小画面不放弹幕。
    var allowsDanmaku = true

    /// 当前播放位置：已出画面时取播放器的进度，否则是本集的起播位置（转到全屏播放时用）。
    var currentPosition: Double {
        controller.progress.duration > 0 ? controller.progress.position : startPosition
    }

    private var startPosition: Double
    private var lastSavedPosition = -1.0
    /// 下一集预取好的播放计划（还剩 10 秒时后台解析好，切集时直接用）。
    private var prefetchedPlan: PlaybackPlan?
    /// 预取针对的分集下标（成功或失败都记录，避免失败后反复重试刷接口）。
    private var prefetchedIndex: Int?
    private var prefetchTask: Task<Void, Never>?
    /// 当前这次换集 / 重试的加载：新的加载开始或停止时取消旧的，
    /// 只让最后一次加载起播（load() 在解析返回后检查取消）。
    private var loadTask: Task<Void, Never>?

    init(drama: Drama, episodes: [Episode], startIndex: Int, startPosition: Double, store: Store, controller: PlayerController) {
        self.drama = drama
        self.episodes = episodes
        self.store = store
        self.controller = controller
        self.currentIndex = startIndex
        self.startPosition = startPosition
    }

    // MARK: - 偏好（与设置页的 @AppStorage 同键同默认值，调用时读取）

    private var autoAdvance: Bool { Self.preference("autoAdvance", default: true) }
    private var danmakuEnabled: Bool { allowsDanmaku && Self.preference("danmakuEnabled", default: true) }
    private var preferredQuality: Int { Self.preference("preferredQuality", default: 0) }
    private var playbackSpeed: Double { Self.preference("playbackSpeed", default: 1.0) }

    private static func preference<Value>(_ key: String, default fallback: Value) -> Value {
        UserDefaults.standard.object(forKey: key) as? Value ?? fallback
    }

    // MARK: - 起播 / 换集

    func start() {
        startLoad()
    }

    func retry() {
        startLoad()
    }

    /// 播放中选集：与详情页点分集一致，从头播放。先存好旧集进度并停掉旧句柄；
    /// 预取若不是为新位置（本集或下一集）准备的，释放掉，避免用到过期地址。
    func playEpisode(at index: Int) {
        guard index != currentIndex, episodes.indices.contains(index) else { return }
        saveProgress()
        controller.halt()
        if !PlaybackRules.keepsPrefetch(prefetchedIndex: prefetchedIndex, target: index) {
            if let stale = prefetchedPlan {
                Task { try? await CoreClient.shared.release(session: stale.session) }
            }
            prefetchedPlan = nil
            prefetchedIndex = nil
        }
        currentIndex = index
        startPosition = 0
        lastSavedPosition = -1
        startLoad()
    }

    /// 离开播放：存好进度、销毁句柄、取消加载与预取，释放核心里的播放会话。
    func stop() {
        saveProgress()
        controller.stop()
        prefetchTask?.cancel()
        prefetchTask = nil
        loadTask?.cancel()
        loadTask = nil
        let sessions = [plan?.session, prefetchedPlan?.session].compactMap { $0 }
        prefetchedPlan = nil
        prefetchedIndex = nil
        Task {
            for session in sessions {
                try? await CoreClient.shared.release(session: session)
            }
        }
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    private func load() async {
        guard currentIndex < episodes.count else {
            onReachedEnd?()
            return
        }
        error = nil
        let episode = episodes[currentIndex]
        // 优先用预取好的计划（上一集还剩 10 秒时已后台解析好），
        // 切集时免去再等解析地址，是衔接卡顿的主因之一。
        if prefetchedIndex == currentIndex {
            let cached = prefetchedPlan
            prefetchedPlan = nil
            prefetchedIndex = nil
            if let cached {
                plan = cached
                controller.play(plan: cached, start: startPosition, danmakuEnabled: danmakuEnabled, speed: playbackSpeed)
                return
            }
            // 预取失败过：直接走正常解析（不重试预取）。
        }
        do {
            let resolved = try await CoreClient.shared.resolve(
                drama: drama, episode: episode, quality: preferredQuality
            )
            guard !Task.isCancelled else { return }
            plan = resolved
            controller.play(plan: resolved, start: startPosition, danmakuEnabled: danmakuEnabled, speed: playbackSpeed)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    // MARK: - 播放器事件

    func handleEnded() {
        if autoAdvance, currentIndex + 1 < episodes.count {
            currentIndex += 1
            startPosition = 0
            lastSavedPosition = -1
            startLoad()
        } else {
            onReachedEnd?()
        }
    }

    func handleFailed() async {
        guard let plan else { return }
        if plan.hasAlternative {
            do {
                let next = try await CoreClient.shared.fallback(plan: plan)
                self.plan = next
                controller.play(plan: next, start: 0, danmakuEnabled: danmakuEnabled, speed: playbackSpeed)
            } catch {
                self.error = error.localizedDescription
            }
        } else {
            let detail = controller.lastError.isEmpty ? controller.debugInfo : controller.lastError
            self.error = detail.isEmpty ? "播放失败，请返回重试" : "播放失败，请返回重试（\(detail)）"
        }
    }

    func handleProgress(position: Double, duration: Double) {
        guard position > 0, duration > 0 else { return }
        maybePrefetchNext(position: position, duration: duration)
        // 与 Dart 侧一致：约每 5 秒落一次进度，避免频繁写盘。
        guard PlaybackRules.shouldSaveProgress(position: position, lastSaved: lastSavedPosition) else { return }
        lastSavedPosition = position
        saveProgress(position: position, duration: duration)
    }

    /// 当前集还剩 10 秒时，后台解析下一集播放地址（预取）。
    /// 切集时直接用预取好的计划，免去再等解析地址。
    private func maybePrefetchNext(position: Double, duration: Double) {
        guard let nextIndex = PlaybackRules.prefetchIndex(
            position: position,
            duration: duration,
            currentIndex: currentIndex,
            episodeCount: episodes.count,
            prefetchedIndex: prefetchedIndex,
            prefetchInFlight: prefetchTask != nil
        ) else { return }
        prefetchedIndex = nextIndex
        let episode = episodes[nextIndex]
        prefetchTask = Task {
            defer { prefetchTask = nil }
            guard let plan = try? await CoreClient.shared.resolve(
                drama: drama, episode: episode, quality: preferredQuality
            ) else { return }
            // 解析完成时若用户已不在触发那集（已切集/已退出），
            // 预取的计划用不上，释放其会话避免泄漏。
            guard !Task.isCancelled, currentIndex + 1 == nextIndex else {
                try? await CoreClient.shared.release(session: plan.session)
                return
            }
            prefetchedPlan = plan
        }
    }

    func saveProgress(position: Double? = nil, duration: Double? = nil) {
        guard currentIndex < episodes.count else { return }
        let position = position ?? controller.progress.position
        let duration = duration ?? controller.progress.duration
        guard position > 0, duration > 0, saveGate(position) else { return }
        let episode = episodes[currentIndex]
        store.saveProgress(WatchProgress(
            drama: drama,
            episode: episode.number,
            episodeTitle: episode.title,
            position: position,
            duration: duration,
            updatedAt: Date()
        ))
    }
}
