import Libmpv
import QuartzCore
import SwiftUI
import UIKit

// MARK: - 弹幕浮层

/// 透明浮层，加到播放容器视图上。
/// 弹幕从右向左匀速滚动，分 6 行轮换，最多同时显示 40 条。
final class DanmakuOverlayView: UIView {
    private var rowCounter = 0

    func clear() {
        subviews.forEach { $0.removeFromSuperview() }
    }

    func emit(text: String) {
        guard bounds.width > 0, subviews.count < 40 else { return }
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 30, weight: .semibold)
        label.textColor = .white
        label.shadowColor = .black
        label.shadowOffset = CGSize(width: 1, height: 1)
        label.sizeToFit()
        let row = rowCounter % 6
        rowCounter += 1
        label.frame = CGRect(x: bounds.width, y: CGFloat(row) * 44 + 20, width: label.bounds.width, height: 40)
        addSubview(label)
        UIView.animate(withDuration: 9, delay: 0, options: .curveLinear) {
            label.frame.origin.x = -label.bounds.width
        } completion: { _ in
            label.removeFromSuperview()
        }
    }
}

// MARK: - 弹幕拉取

/// 按播放进度拉取弹幕页并在时间到达时投递到浮层。
/// 核心返回一页弹幕（`nextMs` 为下一页起点），与 Dart 侧 DanmakuPage 一致。
@MainActor
final class DanmakuEngine {
    private weak var overlay: DanmakuOverlayView?
    private var plan: PlaybackPlan?
    private var enabled = true
    private var page: DanmakuPage?
    private var fetching = false
    private var shown = Set<String>()

    func attach(_ overlay: DanmakuOverlayView) {
        self.overlay = overlay
    }

    func configure(plan: PlaybackPlan, enabled: Bool) {
        self.plan = plan
        self.enabled = enabled
        page = nil
        fetching = false
        shown.removeAll()
    }

    func reset() {
        plan = nil
        page = nil
        shown.removeAll()
    }

    func tick(positionMs: Int, durationMs: Int) {
        guard enabled, let plan else { return }
        // 窗口结束时间必须是本集总时长（与 iOS 一致），而不是固定 60 秒：
        // Go 核心要求 durationMs > startMs；之前传固定 60000，播到 60 秒后
        // 所有请求都被拒（且 try? 把错误吞了），弹幕就再也拉不到。
        // 总时长未知时用当前位置 + 60 秒，保证 end > start。
        let endMs = durationMs > positionMs ? durationMs : positionMs + 60_000
        if page == nil || positionMs >= page!.nextMs - 2000 || positionMs < page!.startMs {
            fetchPage(from: positionMs, end: endMs, plan: plan)
        }
        guard let page else { return }
        for item in page.items where !shown.contains(item.id) && item.timeMs >= positionMs
            && item.timeMs < positionMs + 1000
        {
            shown.insert(item.id)
            overlay?.emit(text: item.text)
        }
        if shown.count > 2000 { shown.removeAll() }
    }

    private func fetchPage(from positionMs: Int, end endMs: Int, plan: PlaybackPlan) {
        guard !fetching else { return }
        fetching = true
        Task {
            defer { fetching = false }
            if let result = try? await CoreClient.shared.danmaku(
                plan: plan, startMs: positionMs, durationMs: endMs
            ), self.plan?.session == plan.session {
                page = result
            }
        }
    }
}

/// 可比较的播放进度（Swift 元组无法遵循 Equatable，onChange 不能直接监听元组）。
struct PlaybackProgress: Equatable {
    var position: Double
    var duration: Double
}

// MARK: - mpv 渲染层

/// CAMetalLayer 子类：忽略 MoltenVK 偶尔写入的 1x1 无效尺寸，避免闪烁。
final class MetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            guard newValue.width > 1, newValue.height > 1 else { return }
            super.drawableSize = newValue
        }
    }
}

/// 承载 Metal 渲染层的容器视图：自身的 layer 就是 MetalLayer。
final class PlayerHostContainerView: UIView {
    override class var layerClass: AnyClass { MetalLayer.self }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        metalLayer.framebufferOnly = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? 1.0
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
}

private struct PlayerHostView: UIViewRepresentable {
    let controller: PlayerController

    func makeUIView(context: Context) -> PlayerHostContainerView {
        let view = PlayerHostContainerView()
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PlayerHostContainerView, context: Context) {}
}

// MARK: - 播放页

struct PlayerView: View {
    let drama: Drama
    let episodes: [Episode]
    let startIndex: Int
    let startPosition: Double

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @AppStorage("danmakuEnabled") private var danmakuEnabled = true
    @AppStorage("autoAdvance") private var autoAdvance = true
    @AppStorage("playbackDiagnostics") private var diagnosticsEnabled = false
    @AppStorage("preferredQuality") private var preferredQuality = 0
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0

    @AppStorage("playerScreenMode") private var screenModeRaw = PlayerScreenMode.fit.rawValue

    @StateObject private var controller = PlayerController()
    /// 播放控件（进度条 / 倍速 / 画面 / 选集）的显示与自动隐藏，见 PlayerControlsView.swift。
    @StateObject private var controls = PlayerControlsState()
    @FocusState private var focus: PlayerFocus?
    @State private var activeSheet: PlayerSheet?
    @State private var currentIndex: Int
    @State private var start: Double
    @State private var plan: PlaybackPlan?
    @State private var error: String?
    @State private var lastSavedPosition = -1.0

    /// 倍速档位：与设置页 speedOptions 一致，改动时两边同步。
    private static let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    /// 下一集预取好的播放计划（还剩 10 秒时后台解析好，切集时直接用）。
    @State private var prefetchedPlan: PlaybackPlan?
    /// 预取针对的分集下标（成功或失败都记录，避免失败后反复重试刷接口）。
    @State private var prefetchedIndex: Int?
    @State private var prefetchTask: Task<Void, Never>?
    /// 当前这次换集 / 重试的加载：新的加载开始或离开页面时取消旧的，
    /// 只让最后一次加载起播（load() 在解析返回后检查取消）。
    @State private var loadTask: Task<Void, Never>?

    init(drama: Drama, episodes: [Episode], startIndex: Int, startPosition: Double) {
        self.drama = drama
        self.episodes = episodes
        self.startIndex = startIndex
        self.startPosition = startPosition
        _currentIndex = State(initialValue: startIndex)
        _start = State(initialValue: startPosition)
    }

    var body: some View {
        ZStack {
            if plan != nil {
                PlayerHostView(controller: controller)
                    .ignoresSafeArea()
                    // 遥控器按键的前提：播放画面必须是可聚焦且已获得焦点。
                    // 控件显示时画面让出焦点（焦点在进度条 / 按钮行），隐藏后再拿回。
                    .focusable(!controls.visible && error == nil)
                    .focused($focus, equals: .surface)
                    .onAppear { focus = .surface }
                    .onMoveCommand { direction in
                        // 与系统播放器一致：← → 快退 / 快进 10 秒，↑ ↓ 调出控件。
                        switch direction {
                        case .left: seek(by: -10)
                        case .right: seek(by: 10)
                        default: revealControls()
                        }
                    }
                    // 遥控器点按（Select）切暂停，并显示控件。
                    .onTapGesture { togglePause() }
                if controller.progress.duration <= 0 && error == nil {
                    ProgressView()
                        .allowsHitTesting(false)
                }
                if controls.visible && error == nil {
                    PlayerControlsOverlay(
                        title: drama.title,
                        subtitle: episodeSubtitle,
                        progress: controller.progress,
                        isPaused: controller.isPaused,
                        speed: playbackSpeed,
                        screenMode: screenMode,
                        showsEpisodes: episodes.count > 1,
                        focus: $focus,
                        onSeek: seek(by:),
                        onTogglePause: togglePause,
                        onOpen: openSheet
                    )
                    .transition(.opacity)
                }
                if diagnosticsEnabled && !controller.debugInfo.isEmpty {
                    Text(controller.debugInfo)
                        .font(.system(size: 22))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .padding(16)
                        .background(Color.black.opacity(0.65))
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(48)
                        .allowsHitTesting(false)
                }
            }
            // 出错时盖在画面之上（播放中换集 / 换线路失败也能看到并重试），不拆掉播放视图。
            if let error {
                VStack(spacing: 28) {
                    TVStatusView(
                        icon: "exclamationmark.triangle.fill",
                        title: "播放失败",
                        message: error,
                        expands: false
                    )
                    HStack(spacing: 20) {
                        TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                            startLoad()
                        }
                        TVSecondaryButton(title: "返回", icon: "chevron.left") {
                            dismiss()
                        }
                    }
                }
                .padding(60)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
            } else if plan == nil {
                TVLoadingView("正在解析播放地址…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: controls.visible)
        .onPlayPauseCommand { togglePause() }
        .onExitCommand {
            // Menu：先收起控件，再按一次才退出播放。
            if controls.visible && error == nil {
                controls.hide()
            } else {
                dismiss()
            }
        }
        .sheet(item: $activeSheet, onDismiss: revealControls) { sheet in
            playerSheet(sheet)
        }
        .task {
            controller.setScreenMode(screenMode)
            await load()
        }
        .onChange(of: controls.visible) { visible in
            // 控件出现时焦点落到进度条；隐藏时还给画面（下一轮再设，等可聚焦状态生效）。
            DispatchQueue.main.async { focus = visible ? .scrubber : .surface }
        }
        .onChange(of: focus) { _ in
            // 在控件间移动焦点也算操作：重新计时自动隐藏。
            if controls.visible { revealControls() }
        }
        .onChange(of: controller.isPaused) { _ in
            if controls.visible { revealControls() }
        }
        .onChange(of: error) { value in
            // 出错时收起控件并停掉句柄：恢复屏保（避免错误页常亮），重试时照常 load() → play()。
            guard value != nil else { return }
            controls.hide()
            controller.halt()
        }
        .onChange(of: playbackSpeed) { speed in
            controller.setSpeed(speed)
        }
        .onChange(of: screenModeRaw) { _ in
            controller.setScreenMode(screenMode)
        }
        .onChange(of: controller.endedToken) { token in
            guard token > 0 else { return }
            handleEnded()
        }
        .onChange(of: controller.failedToken) { token in
            guard token > 0 else { return }
            Task { await handleFailed() }
        }
        .onChange(of: controller.progress) { value in
            handleProgress(position: value.position, duration: value.duration)
        }
        .onDisappear {
            saveProgress()
            controller.stop()
            prefetchTask?.cancel()
            prefetchTask = nil
            loadTask?.cancel()
            loadTask = nil
            Task {
                if let plan {
                    try? await CoreClient.shared.release(session: plan.session)
                }
                if let prefetchedPlan {
                    try? await CoreClient.shared.release(session: prefetchedPlan.session)
                }
            }
        }
    }

    // MARK: - 播放控件

    private var screenMode: PlayerScreenMode {
        PlayerScreenMode(rawValue: screenModeRaw) ?? .fit
    }

    private var episodeSubtitle: String {
        guard episodes.indices.contains(currentIndex) else { return "" }
        return "第 \(episodes[currentIndex].number) 集 · 共 \(episodes.count) 集"
    }

    /// 显示控件并重新计时；暂停或开着弹窗时不自动隐藏。
    private func revealControls() {
        guard error == nil else { return }
        controls.show(autoHide: !controller.isPaused && activeSheet == nil)
    }

    private func togglePause() {
        controller.togglePause()
        revealControls()
    }

    private func seek(by seconds: Double) {
        controller.seek(by: seconds)
        revealControls()
    }

    private func openSheet(_ sheet: PlayerSheet) {
        activeSheet = sheet
        controls.show(autoHide: false)
    }

    @ViewBuilder
    private func playerSheet(_ sheet: PlayerSheet) -> some View {
        switch sheet {
        case .speed:
            TVOptionSheet(
                title: "播放倍速",
                options: Self.speedOptions.map { TVOption(value: $0, label: String(format: "%.2fx", $0)) },
                selection: $playbackSpeed
            )
        case .screenMode:
            TVOptionSheet(
                title: "画面",
                options: PlayerScreenMode.allCases.map { TVOption(value: $0.rawValue, label: $0.optionLabel) },
                selection: $screenModeRaw
            )
        case .episodes:
            PlayerEpisodeSheet(
                episodes: episodes,
                currentIndex: currentIndex,
                progress: episodeProgress,
                onSelect: playEpisode(at:)
            )
        }
    }

    private func episodeProgress(_ episode: Episode) -> Double? {
        guard let saved = store.progress(for: drama.id, episode: episode.number), saved.duration > 0 else {
            return nil
        }
        let fraction = saved.position / saved.duration
        return fraction > 0.005 ? min(fraction, 1) : nil
    }

    /// 播放中选集：与详情页点分集一致，从头播放。先存好旧集进度并停掉旧句柄；
    /// 预取若不是为新位置（本集或下一集）准备的，释放掉，避免用到过期地址。
    private func playEpisode(at index: Int) {
        guard index != currentIndex, episodes.indices.contains(index) else { return }
        saveProgress()
        controller.halt()
        if prefetchedIndex != index && prefetchedIndex != index + 1 {
            if let stale = prefetchedPlan {
                Task { try? await CoreClient.shared.release(session: stale.session) }
            }
            prefetchedPlan = nil
            prefetchedIndex = nil
        }
        currentIndex = index
        start = 0
        lastSavedPosition = -1
        startLoad()
    }

    private func startLoad() {
        loadTask?.cancel()
        loadTask = Task { await load() }
    }

    private func load() async {
        guard currentIndex < episodes.count else {
            dismiss()
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
                controller.play(plan: cached, start: start, danmakuEnabled: danmakuEnabled, speed: playbackSpeed)
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
            controller.play(plan: resolved, start: start, danmakuEnabled: danmakuEnabled, speed: playbackSpeed)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    private func handleEnded() {
        if autoAdvance, currentIndex + 1 < episodes.count {
            currentIndex += 1
            start = 0
            lastSavedPosition = -1
            startLoad()
        } else {
            dismiss()
        }
    }

    private func handleFailed() async {
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
            self.error = "播放失败，请返回重试"
        }
    }

    private func handleProgress(position: Double, duration: Double) {
        guard position > 0, duration > 0 else { return }
        maybePrefetchNext(position: position, duration: duration)
        // 与 Dart 侧一致：约每 5 秒落一次进度，避免频繁写盘。
        guard abs(position - lastSavedPosition) >= 5 else { return }
        lastSavedPosition = position
        saveProgress(position: position, duration: duration)
    }

    /// 当前集还剩 10 秒时，后台解析下一集播放地址（预取）。
    /// 切集时直接用预取好的计划，免去再等解析地址。
    private func maybePrefetchNext(position: Double, duration: Double) {
        let remaining = duration - position
        guard remaining <= 10, remaining > 0 else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < episodes.count else { return }
        guard prefetchedIndex != nextIndex, prefetchTask == nil else { return }
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

    private func saveProgress(position: Double? = nil, duration: Double? = nil) {
        guard currentIndex < episodes.count else { return }
        let position = position ?? controller.progress.position
        let duration = duration ?? controller.progress.duration
        guard position > 0, duration > 0 else { return }
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
