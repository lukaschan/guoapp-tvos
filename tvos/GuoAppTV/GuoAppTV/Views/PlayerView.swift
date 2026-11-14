import Libmpv
import QuartzCore
import SwiftUI
import UIKit

// MARK: - 弹幕浮层

/// 透明浮层，加到播放容器视图上。
/// 弹幕从右向左同一速度飘过，分 6 行；放哪一行、什么时候放、要不要放由 DanmakuLayout 决定：
/// 前一条整条进屏后这一行才放下一条，不会叠在一起，一下子来太多时多出来的最多等 2 秒、等不到就不发；
/// 同一句话屏上最多一条。很长的弹幕截到 1200 pt（末尾「…」），免得一条占住一行二十几秒。
final class DanmakuOverlayView: UIView {
    private static let font = UIFont.systemFont(ofSize: 30, weight: .semibold)
    private static let maxLabelWidth: CGFloat = 1200
    private static let laneHeight: CGFloat = 44
    private static let topInset: CGFloat = 20

    private var layout = DanmakuLayout()
    /// 有弹幕在排队时，等到有行空出来再放。
    private var wakeTask: Task<Void, Never>?

    func clear() {
        wakeTask?.cancel()
        wakeTask = nil
        layout.clear()
        subviews.forEach { $0.removeFromSuperview() }
    }

    func emit(texts: [String]) {
        guard bounds.width > 0, !texts.isEmpty else { return }
        let comments = texts.map { text in
            let measured = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width)
            return (text: text, width: Double(min(measured, Self.maxLabelWidth)))
        }
        layout.screenWidth = Double(bounds.width)
        show(layout.submit(comments, now: CACurrentMediaTime()))
    }

    private func show(_ placements: [DanmakuLayout.Placement]) {
        for placement in placements {
            let label = UILabel()
            label.text = placement.text
            label.font = Self.font
            label.textColor = .white
            label.shadowColor = .black
            label.shadowOffset = CGSize(width: 1, height: 1)
            label.lineBreakMode = .byTruncatingTail
            let width = CGFloat(placement.width)
            let y = CGFloat(placement.lane) * Self.laneHeight + Self.topInset
            label.frame = CGRect(x: bounds.width, y: y, width: width, height: 40)
            addSubview(label)
            let duration = layout.duration(width: placement.width)
            UIView.animate(withDuration: duration, delay: 0, options: .curveLinear) {
                label.frame.origin.x = -width
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
        scheduleWake()
    }

    private func scheduleWake() {
        wakeTask?.cancel()
        wakeTask = nil
        guard let wake = layout.nextWake else { return }
        let delay = max(0.05, wake - CACurrentMediaTime())
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.show(self.layout.drain(now: CACurrentMediaTime()))
        }
    }
}

// MARK: - 弹幕拉取

/// 按播放进度拉取弹幕页并在时间到达时投递到浮层；开关、拉取时机与投递窗口见 DanmakuScheduler。
/// 核心返回一页弹幕（`nextMs` 为下一页起点），与 Dart 侧 DanmakuPage 一致。
@MainActor
final class DanmakuEngine {
    private weak var overlay: DanmakuOverlayView?
    private var plan: PlaybackPlan?
    private var scheduler = DanmakuScheduler(isEnabled: true)
    private var page: DanmakuPage?
    private var fetching = false

    func attach(_ overlay: DanmakuOverlayView) {
        self.overlay = overlay
    }

    func configure(plan: PlaybackPlan, enabled: Bool) {
        self.plan = plan
        scheduler = DanmakuScheduler(isEnabled: enabled)
        page = nil
        fetching = false
    }

    /// 播放中开关（全屏播放控件的「弹幕」按钮）：关掉时清掉屏上正在飘的，再打开从当前位置接着发。
    func setEnabled(_ enabled: Bool) {
        scheduler.setEnabled(enabled)
        if !enabled { overlay?.clear() }
    }

    func reset() {
        plan = nil
        page = nil
        scheduler.reset()
    }

    func tick(positionMs: Int, durationMs: Int) {
        guard let plan else { return }
        // 窗口结束时间必须是本集总时长（与 iOS 一致），而不是固定 60 秒：
        // Go 核心要求 durationMs > startMs；之前传固定 60000，播到 60 秒后
        // 所有请求都被拒（且 try? 把错误吞了），弹幕就再也拉不到。
        // 总时长未知时用当前位置 + 60 秒，保证 end > start。
        let endMs = durationMs > positionMs ? durationMs : positionMs + 60_000
        if scheduler.needsPage(positionMs: positionMs, page: page.map { ($0.startMs, $0.nextMs) }) {
            fetchPage(from: positionMs, end: endMs, plan: plan)
        }
        guard let page else { return }
        let due = scheduler.due(page.items, positionMs: positionMs, id: \.id, timeMs: \.timeMs)
        overlay?.emit(texts: due.map(\.text))
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

// MARK: - 播放页

/// 全屏播放页：持有这次播放的 PlaybackSession（分集逻辑）与其 PlayerController（mpv）。
/// 界面在 PlayerScreen 里，它同时观察会话与控制器。
struct PlayerView: View {
    @StateObject private var session: PlaybackSession

    init(drama: Drama, episodes: [Episode], startIndex: Int, startPosition: Double, store: Store) {
        _session = StateObject(wrappedValue: PlaybackSession(
            drama: drama,
            episodes: episodes,
            startIndex: startIndex,
            startPosition: startPosition,
            store: store,
            controller: PlayerController()
        ))
    }

    var body: some View {
        PlayerScreen(session: session, controller: session.controller)
    }
}

private struct PlayerScreen: View {
    @ObservedObject var session: PlaybackSession
    @ObservedObject var controller: PlayerController

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: Store
    @AppStorage("playbackDiagnostics") private var diagnosticsEnabled = false
    @AppStorage("playbackSpeed") private var playbackSpeed = 1.0
    /// 与「我的」里的弹幕开关同一个设置（PlaybackSession 起播时读它）；控件里的「弹幕」按钮直接改它。
    @AppStorage("danmakuEnabled") private var danmakuEnabled = true

    /// 播放控件（进度条 / 倍速 / 弹幕 / 选集）的显示与自动隐藏，见 PlayerControlsView.swift。
    @StateObject private var controls = PlayerControlsState()
    @FocusState private var focus: PlayerFocus?
    @State private var activeSheet: PlayerSheet?

    /// 开发验证用：启动参数 -GUOAppShowControls YES 让播放控件一直显示、不自动隐藏（只对这次启动有效）。
    private static let pinsControls = UserDefaults.standard.bool(forKey: "GUOAppShowControls")

    /// 倍速档位：与设置页 speedOptions 一致，改动时两边同步。
    private static let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private var drama: Drama { session.drama }
    private var episodes: [Episode] { session.episodes }

    var body: some View {
        ZStack {
            if session.plan != nil {
                PlayerHostView(controller: controller)
                    .ignoresSafeArea()
                    // 遥控器按键的前提：播放画面必须是可聚焦且已获得焦点。
                    // 控件显示时画面让出焦点（焦点在进度条 / 按钮行），隐藏后再拿回。
                    .focusable(!controls.visible && session.error == nil)
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
                if controller.progress.duration <= 0 && session.error == nil {
                    ProgressView()
                        .allowsHitTesting(false)
                }
                if controls.visible && session.error == nil {
                    PlayerControlsOverlay(
                        title: drama.title,
                        subtitle: episodeSubtitle,
                        progress: controller.progress,
                        isPaused: controller.isPaused,
                        speed: playbackSpeed,
                        danmakuOn: danmakuEnabled,
                        showsEpisodes: episodes.count > 1,
                        focus: $focus,
                        onSeek: seek(by:),
                        onTogglePause: togglePause,
                        onToggleDanmaku: toggleDanmaku,
                        onOpen: openSheet
                    )
                    .transition(.opacity)
                }
                if diagnosticsEnabled && !controller.debugInfo.isEmpty {
                    Text(controller.debugInfo)
                        .font(.system(size: TVTheme.TextSize.caption2))
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
            if let error = session.error {
                VStack(spacing: 28) {
                    TVStatusView(
                        icon: "exclamationmark.triangle.fill",
                        title: "播放失败",
                        message: UserFacingError.message(for: error),
                        expands: false
                    )
                    HStack(spacing: 20) {
                        TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                            session.retry()
                        }
                        TVSecondaryButton(title: "返回", icon: "chevron.left") {
                            dismiss()
                        }
                    }
                }
                .padding(60)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(TVTheme.background.ignoresSafeArea())
            } else if session.plan == nil {
                TVLoadingView("正在解析播放地址…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.25), value: controls.visible)
        .onPlayPauseCommand { togglePause() }
        .onExitCommand {
            // Menu：先收起控件，再按一次才退出播放。
            if controls.visible && session.error == nil {
                controls.hide()
            } else {
                dismiss()
            }
        }
        .sheet(item: $activeSheet, onDismiss: revealControls) { sheet in
            playerSheet(sheet)
        }
        .task {
            session.onReachedEnd = { dismiss() }
            session.start()
            if Self.pinsControls { revealControls() }
            // 开发验证用：启动参数 -GUOAppToggleDanmakuAfter N 在打开播放页 N 秒后按一下「弹幕」（参数只对这次启动有效，
            // 但和真按按钮一样会改掉保存的弹幕设置——验证时要再按回来）。
            if let delay = Int(UserDefaults.standard.string(forKey: "GUOAppToggleDanmakuAfter") ?? "") {
                try? await Task.sleep(for: .seconds(delay))
                if !Task.isCancelled { toggleDanmaku() }
            }
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
        .onChange(of: session.error) { value in
            // 出错时收起控件（句柄由会话在出错时停掉）。
            guard value != nil else { return }
            controls.hide()
        }
        .onChange(of: playbackSpeed) { speed in
            controller.setSpeed(speed)
        }
        .onChange(of: danmakuEnabled) { enabled in
            controller.setDanmakuEnabled(session.allowsDanmaku && enabled)
        }
        .onChange(of: controller.endedToken) { token in
            guard token > 0 else { return }
            session.handleEnded()
        }
        .onChange(of: controller.failedToken) { token in
            guard token > 0 else { return }
            Task { await session.handleFailed() }
        }
        .onChange(of: controller.progress) { value in
            session.handleProgress(position: value.position, duration: value.duration)
        }
        .onDisappear {
            session.stop()
        }
    }

    // MARK: - 播放控件

    private var episodeSubtitle: String {
        guard episodes.indices.contains(session.currentIndex) else { return "" }
        return "第 \(episodes[session.currentIndex].number) 集 · 共 \(episodes.count) 集"
    }

    /// 显示控件并重新计时；暂停或开着弹窗时不自动隐藏。
    private func revealControls() {
        guard session.error == nil else { return }
        controls.show(autoHide: !Self.pinsControls && !controller.isPaused && activeSheet == nil)
    }

    private func togglePause() {
        controller.togglePause()
        revealControls()
    }

    private func seek(by seconds: Double) {
        controller.seek(by: seconds)
        revealControls()
    }

    /// 「弹幕」按钮：开 / 关并重新计时自动隐藏（焦点留在按钮上，可以连按）。
    private func toggleDanmaku() {
        danmakuEnabled.toggle()
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
        case .episodes:
            PlayerEpisodeSheet(
                episodes: episodes,
                currentIndex: session.currentIndex,
                progress: episodeProgress,
                onSelect: session.playEpisode(at:)
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
}
