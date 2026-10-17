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

// MARK: - mpv 事件

/// wakeup 回调的上下文：只在创建时写入、此后只读，随句柄一起释放。
/// 回调在任意线程触发，只能通过它拿到控制器与句柄，不能碰 @MainActor 状态。
private struct MpvWakeupContext {
    var controller: Unmanaged<PlayerController>
    var handle: OpaquePointer
}

// MARK: - 播放控制器

/// 持有 mpv 句柄，负责换集、进度上报、播完 / 失败通知、弹幕调度。
/// 原版应用用 mpv + decryption_key 解密 CENC 播放；AVPlayer 没有传原始密钥
/// 解密 CENC 的接口，所以这里直接用 MPVKit 的 libmpv，与原版一致。
/// 每次 play() 都新建句柄：decryption-key 必须在 mpv_initialize 之前设置，
/// 而密钥随内容变化，复用句柄无法换密钥。
@MainActor
final class PlayerController: NSObject, ObservableObject {
    @Published var progress = PlaybackProgress(position: 0, duration: 0)
    @Published var endedToken = 0
    @Published var failedToken = 0
    /// 临时诊断面板内容：播放状态、音视频编码、硬解、解密、播放地址。
    @Published var debugInfo = ""

    /// 事件队列：mpv 事件泵跑在这里；销毁时同步等它排空，避免句柄悬空。
    nonisolated let eventQueue = DispatchQueue(label: "com.duanju.guoapp.tv.mpv-events")

    private var mpv: OpaquePointer?
    private var wakeupContext: UnsafeMutablePointer<MpvWakeupContext>?
    private var metalLayer: CAMetalLayer?
    private var currentURL: URL?
    private var hasDecryptionKey = false
    private var lastError = ""
    private var activePlan: PlaybackPlan?
    private var activeDanmakuEnabled = true
    private var pendingPlay: (plan: PlaybackPlan, start: Double, danmakuEnabled: Bool, speed: Double)?
    private let overlay = DanmakuOverlayView()
    private let danmaku = DanmakuEngine()
    private var overlayAttached = false
    private var progressTimer: Timer?
    private var backgroundObservers: [NSObjectProtocol] = []
    private var backgroundObserversInstalled = false
    private var wasPlayingBeforeBackground = false

    /// 容器视图建好后由 PlayerHostView 调用；play() 若先到则在此补启动。
    func attach(to container: PlayerHostContainerView) {
        let newLayer = container.metalLayer
        let layerChanged = metalLayer.map { $0 !== newLayer } ?? false
        metalLayer = newLayer
        if !overlayAttached {
            overlay.frame = container.bounds
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(overlay)
            danmaku.attach(overlay)
            overlayAttached = true
        }
        installBackgroundObservers()
        if layerChanged, let activePlan {
            // 视图重建导致 Metal 层换了：mpv 需重建并指向新层，从当前位置续播。
            startPlayback(plan: activePlan, start: progress.position, danmakuEnabled: activeDanmakuEnabled)
            return
        }
        if let pending = pendingPlay {
            pendingPlay = nil
            startPlayback(plan: pending.plan, start: pending.start, danmakuEnabled: pending.danmakuEnabled, speed: pending.speed)
        }
    }

    func play(plan: PlaybackPlan, start: Double, danmakuEnabled: Bool, speed: Double = 1.0) {
        guard metalLayer != nil else {
            pendingPlay = (plan, start, danmakuEnabled, speed)
            debugInfo = "正在加载…"
            return
        }
        startPlayback(plan: plan, start: start, danmakuEnabled: danmakuEnabled, speed: speed)
    }

    func stop() {
        destroyMpv()
        pendingPlay = nil
        activePlan = nil
        danmaku.reset()
        overlay.clear()
        for observer in backgroundObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        backgroundObservers.removeAll()
        backgroundObserversInstalled = false
    }

    func togglePause() {
        guard mpv != nil else { return }
        setFlag("pause", !getFlag("pause"))
        updateIdleTimer()
    }

    /// 正在播放时禁止系统空闲计时器，避免 tvOS 屏保在看剧时弹出；
    /// 暂停 / 停止 / 切后台时恢复，屏保才能正常出现。
    /// 注意：mpv 不是 AVPlayer，系统不知道在播视频，必须手动关空闲计时器。
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = mpv != nil && !getFlag("pause")
    }

    func seek(by seconds: Double) {
        command(["seek", "\(seconds)", "relative"])
    }

    // MARK: - 播放启动

    private func startPlayback(plan: PlaybackPlan, start: Double, danmakuEnabled: Bool, speed: Double = 1.0) {
        destroyMpv()
        danmaku.configure(plan: plan, enabled: danmakuEnabled)
        guard let url = URL(string: plan.url) else {
            debugInfo = "播放地址无效"
            failedToken += 1
            return
        }
        guard let layer = metalLayer else {
            pendingPlay = (plan, start, danmakuEnabled, speed)
            debugInfo = "正在加载…"
            return
        }
        currentURL = url
        hasDecryptionKey = !plan.decryptionKey.isEmpty
        lastError = ""
        activePlan = plan
        activeDanmakuEnabled = danmakuEnabled
        progress = PlaybackProgress(position: 0, duration: 0)
        debugInfo = "正在加载…"

        guard let handle = mpv_create() else {
            debugInfo = "创建播放器失败"
            failedToken += 1
            return
        }
        mpv = handle
        var layerRef = layer
        _ = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layerRef)
        _ = mpv_set_option_string(handle, "vo", "gpu-next")
        _ = mpv_set_option_string(handle, "gpu-api", "vulkan")
        _ = mpv_set_option_string(handle, "gpu-context", "moltenvk")
        _ = mpv_set_option_string(handle, "hwdec", "videotoolbox")
        _ = mpv_set_option_string(handle, "subs-match-os-language", "yes")
        _ = mpv_set_option_string(handle, "subs-fallback", "yes")
        _ = mpv_set_option_string(handle, "video-rotate", "no")
        if start > 0 {
            _ = mpv_set_option_string(handle, "start", "\(start)")
        }
        // 与 iOS 端 player_screen.dart 一致的 demuxer 选项：重试、实验特性、
        // 扩展名、协议白名单（local 与否的分支与 iOS 相同）、解密密钥。
        // 注意：不要用 mpv 自身的 decryption-key 选项——在此构建下它不生效
        // （时长能读出但时间一直停在 0、无画面无声）。iOS 端用的是下面
        // demuxer-lavf-o 这一路，把密钥作为 FFmpeg demuxer 选项直接传给 libavformat。
        var lavfOptions = [
            "seg_max_retry=3",
            "strict=experimental",
            "allowed_extensions=ALL",
            plan.local
                ? "protocol_whitelist=[file,crypto,data]"
                : "protocol_whitelist=[http,https,tcp,tls,crypto,data,file]",
        ]
        if hasDecryptionKey {
            lavfOptions.append("decryption_key=\(plan.decryptionKey)")
        }
        _ = mpv_set_option_string(handle, "demuxer-lavf-o", lavfOptions.joined(separator: ","))
        _ = mpv_set_option_string(handle, "network-timeout", "20")
        // 播放倍速：来自设置里的播放倍速，打开剧集时生效。
        if speed != 1.0 {
            _ = mpv_set_option_string(handle, "speed", "\(speed)")
        }
        if !plan.local, !plan.headers.isEmpty {
            // 本地代理地址由 Go 核心转发请求头；直连地址才由 mpv 自己带头。
            // 注意：字段值含逗号时 mpv 会按逗号切分，站源的 UA/Referer 通常不含逗号。
            let fields = plan.headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
            _ = mpv_set_option_string(handle, "http-header-fields", fields)
        }
        _ = mpv_request_log_messages(handle, "no")
        let initStatus = mpv_initialize(handle)
        guard initStatus >= 0 else {
            debugInfo = "初始化失败: \(String(cString: mpv_error_string(initStatus)))"
            failedToken += 1
            destroyMpv()
            return
        }
        let contextPointer = UnsafeMutablePointer<MpvWakeupContext>.allocate(capacity: 1)
        contextPointer.initialize(to: MpvWakeupContext(
            controller: Unmanaged.passUnretained(self), handle: handle
        ))
        wakeupContext = contextPointer
        mpv_set_wakeup_callback(handle, { rawContext in
            guard let rawContext else { return }
            let context = rawContext.assumingMemoryBound(to: MpvWakeupContext.self).pointee
            let controller = context.controller.takeUnretainedValue()
            controller.eventQueue.async {
                controller.drainEvents(handle: context.handle)
            }
        }, contextPointer)
        command(["loadfile", url.absoluteString, "replace"])
        startProgressTimer()
        updateIdleTimer()
    }

    private func destroyMpv() {
        progressTimer?.invalidate()
        progressTimer = nil
        // 播放器销毁时恢复系统空闲计时器，屏保才能正常出现。
        UIApplication.shared.isIdleTimerDisabled = false
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        // 同步等事件队列排空，保证没有 drain 正在用该句柄，再销毁。
        eventQueue.sync {
            mpv_terminate_destroy(handle)
        }
        if let contextPointer = wakeupContext {
            contextPointer.deinitialize(count: 1)
            contextPointer.deallocate()
            wakeupContext = nil
        }
    }

    // MARK: - mpv 事件泵（事件队列线程，不碰 @MainActor 状态）

    /// 排空挂起的 mpv 事件；只处理播完 / 失败，其余忽略。
    /// wait_event 超时 0 = 立即返回，不阻塞。
    nonisolated func drainEvents(handle: OpaquePointer) {
        while true {
            guard let event = mpv_wait_event(handle, 0) else { return }
            let eventId = event.pointee.event_id
            if eventId == MPV_EVENT_NONE || eventId == MPV_EVENT_SHUTDOWN { return }
            if eventId == MPV_EVENT_END_FILE {
                let endFile = event.pointee.data
                    .assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if endFile.reason == MPV_END_FILE_REASON_EOF {
                    Task { @MainActor [weak self] in self?.endedToken += 1 }
                } else if endFile.reason == MPV_END_FILE_REASON_ERROR {
                    let message = String(cString: mpv_error_string(endFile.error))
                    Task { @MainActor [weak self] in
                        self?.lastError = message
                        self?.failedToken += 1
                    }
                }
                // STOP / QUIT / REDIRECT：忽略。
            }
        }
    }

    // MARK: - 进度与诊断

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard mpv != nil else { return }
        let position = getDouble("time-pos")
        let duration = getDouble("duration")
        progress = PlaybackProgress(
            position: position.isFinite ? position : 0,
            duration: duration.isFinite ? duration : 0
        )
        danmaku.tick(
            positionMs: Int(position * 1000),
            durationMs: (duration.isFinite && duration > 0) ? Int(duration * 1000) : 0
        )
        updateDebugInfo(position: position, duration: duration)
    }

    /// 每秒刷新诊断面板：状态、编码、硬解、解密、播放地址。
    private func updateDebugInfo(position: Double, duration: Double) {
        guard mpv != nil else {
            debugInfo = "无播放器"
            return
        }
        var lines: [String] = []
        let paused = getFlag("pause")
        let buffering = getFlag("paused-for-cache")
        let state = paused ? "已暂停" : (buffering ? "缓冲中" : "播放中")
        lines.append("状态: \(state)")
        lines.append("视频: \(getString("video-codec").orDash) 硬解: \(getString("hwdec-current").orDash)")
        lines.append("音频: \(getString("audio-codec").orDash)")
        lines.append("进度: \(Int(position)) / \(Int(duration)) 秒")
        lines.append("解密: \(hasDecryptionKey ? "有" : "无")")
        if let url = currentURL {
            lines.append("地址: \(url.host ?? "-")\(url.path)")
        }
        if !lastError.isEmpty {
            lines.append("错误: \(lastError)")
        }
        debugInfo = lines.joined(separator: "\n")
    }

    // MARK: - 后台 / 前台

    private func installBackgroundObservers() {
        guard !backgroundObserversInstalled else { return }
        backgroundObserversInstalled = true
        let center = NotificationCenter.default
        backgroundObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enterBackground() }
        })
        backgroundObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.enterForeground() }
        })
    }

    /// 切后台时暂停并停掉视频输出；切回前台时恢复输出并续播（防回前台黑屏）。
    private func enterBackground() {
        guard let handle = mpv else { return }
        wasPlayingBeforeBackground = !getFlag("pause")
        setFlag("pause", true)
        UIApplication.shared.isIdleTimerDisabled = false
        _ = mpv_set_option_string(handle, "vid", "no")
    }

    private func enterForeground() {
        guard let handle = mpv else { return }
        _ = mpv_set_option_string(handle, "vid", "auto")
        if wasPlayingBeforeBackground {
            setFlag("pause", false)
        }
        updateIdleTimer()
    }

    // MARK: - mpv 属性读写

    private func command(_ args: [String]) {
        guard let handle = mpv else { return }
        // 逐个追加：strdup 返回可变指针，append 的参数类型触发单值隐式转换；
        // 用 map 时闭包返回值类型推断不到不可变指针，编译报错。
        var cArgs: [UnsafePointer<CChar>?] = []
        cArgs.reserveCapacity(args.count + 1)
        for arg in args {
            cArgs.append(strdup(arg))
        }
        cArgs.append(nil)
        cArgs.withUnsafeMutableBufferPointer { buffer in
            _ = mpv_command(handle, buffer.baseAddress)
        }
        for pointer in cArgs {
            if let pointer {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
    }

    private func getDouble(_ name: String) -> Double {
        guard let handle = mpv else { return 0 }
        var value = Double(0)
        let status = mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value)
        return status >= 0 ? value : 0
    }

    private func getFlag(_ name: String) -> Bool {
        guard let handle = mpv else { return false }
        var value: Int32 = 0
        let status = mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value)
        return status >= 0 && value != 0
    }

    private func setFlag(_ name: String, _ value: Bool) {
        guard let handle = mpv else { return }
        var flag: Int32 = value ? 1 : 0
        _ = mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
    }

    private func getString(_ name: String) -> String {
        guard let handle = mpv else { return "" }
        guard let cString = mpv_get_property_string(handle, name) else { return "" }
        defer { mpv_free(cString) }
        return String(cString: cString)
    }
}

private extension String {
    var orDash: String { isEmpty ? "-" : self }
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

    @StateObject private var controller = PlayerController()
    @FocusState private var playerFocused: Bool
    @State private var currentIndex: Int
    @State private var start: Double
    @State private var plan: PlaybackPlan?
    @State private var error: String?
    @State private var lastSavedPosition = -1.0

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
                    // 之前这里没有任何可聚焦视图，onPlayPauseCommand / onMoveCommand
                    // 收不到事件，所以暂停、快进都不生效。
                    .focusable()
                    .focused($playerFocused)
                    .onAppear { playerFocused = true }
                    .onPlayPauseCommand { controller.togglePause() }
                    .onMoveCommand { direction in
                        switch direction {
                        case .left: controller.seek(by: -10)
                        case .right: controller.seek(by: 10)
                        default: break
                        }
                    }
                    // 遥控器点按（Select）也切暂停。
                    .onTapGesture { controller.togglePause() }
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
            } else if let error {
                VStack(spacing: 24) {
                    Text("播放失败").font(.title)
                    Text(error).foregroundColor(.secondary).multilineTextAlignment(.center)
                    HStack(spacing: 20) {
                        Button("重试") { Task { await load() } }
                        Button("返回") { dismiss() }
                    }
                }
                .padding(60)
            } else {
                ProgressView("正在解析播放地址…")
            }
        }
        .task {
            await load()
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
            Task {
                if let plan {
                    try? await CoreClient.shared.release(session: plan.session)
                }
            }
        }
    }

    private func load() async {
        guard currentIndex < episodes.count else {
            dismiss()
            return
        }
        error = nil
        let episode = episodes[currentIndex]
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
            Task { await load() }
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
        // 与 Dart 侧一致：约每 5 秒落一次进度，避免频繁写盘。
        guard abs(position - lastSavedPosition) >= 5 else { return }
        lastSavedPosition = position
        saveProgress(position: position, duration: duration)
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
