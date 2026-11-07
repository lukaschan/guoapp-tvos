import Libmpv
import QuartzCore
import SwiftUI
import UIKit

// mpv 播放控制器（从 PlayerView.swift 原样拆出，逻辑未改）：句柄生命周期、事件泵、
// 进度、倍速、画面模式、后台 / 前台处理。

// MARK: - mpv 事件

/// libmpv 句柄的 Sendable 包装，用于把句柄交给事件队列。
/// libmpv 客户端 API 自身线程安全（mpv client.h："the client API is generally
/// fully thread-safe"）；唯一要求单线程调用的 mpv_wait_event 只在串行的
/// eventQueue 上调用，因此这里的 @unchecked Sendable 有库的线程安全保证兜底。
private struct MpvHandle: @unchecked Sendable {
    let raw: OpaquePointer
}

/// wakeup 回调的上下文：只在创建时写入、此后只读，随句柄一起释放。
/// 回调在任意线程触发，只能通过它拿到控制器与句柄，不能碰 @MainActor 状态。
private struct MpvWakeupContext: Sendable {
    let controller: Unmanaged<PlayerController>
    let handle: MpvHandle
}

/// mpv 的 wakeup 回调。mpv 在自己的 core 线程上调用它，所以必须是非隔离的顶层函数：
/// 若写成 @MainActor 方法里的闭包，Swift 6 会把闭包推断为主线程隔离并在入口插入
/// 运行时检查，mpv 一调就崩（EXC_BREAKPOINT，dispatch_assert_queue 失败）。
/// 这里只把排空事件的工作转交给串行的 eventQueue，不碰任何 @MainActor 状态。
private func mpvWakeup(_ rawContext: UnsafeMutableRawPointer?) {
    guard let rawContext else { return }
    let context = rawContext.assumingMemoryBound(to: MpvWakeupContext.self).pointee
    let controller = context.controller.takeUnretainedValue()
    let handle = context.handle
    controller.eventQueue.async {
        controller.drainEvents(handle: handle.raw)
    }
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
    /// 是否已暂停（播放控件显示暂停 / 播放图标、暂停时不自动隐藏控件）。
    @Published private(set) var isPaused = false

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
    private var screenMode: PlayerScreenMode = .fit

    /// 容器视图建好后由 PlayerHostView 调用；play() 若先到则在此补启动。
    func attach(to container: PlayerHostContainerView) {
        let newLayer = container.metalLayer
        let layerChanged = metalLayer.map { $0 !== newLayer } ?? false
        if layerChanged {
            // 先销毁仍指向旧图层的 mpv 句柄、再换图层：保证旧句柄销毁前旧图层仍被强引用。
            destroyMpv()
        }
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
        isPaused = getFlag("pause")
        updateIdleTimer()
    }

    /// 手动选集时先停掉当前句柄：旧集不再上报进度（否则会记到新集名下），
    /// 新集地址解析好后照常 play()。不动后台观察者与弹幕浮层。
    func halt() {
        destroyMpv()
        activePlan = nil
        pendingPlay = nil
        progress = PlaybackProgress(position: 0, duration: 0)
    }

    /// 画面模式（适应 / 填充 / 拉伸）：记下来，每次新建句柄都套用；正在播放时立即生效。
    func setScreenMode(_ mode: PlayerScreenMode) {
        screenMode = mode
        guard let handle = mpv else { return }
        applyScreenMode(to: handle)
    }

    private func applyScreenMode(to handle: OpaquePointer) {
        _ = mpv_set_property_string(handle, "keepaspect", screenMode.keepAspect ? "yes" : "no")
        _ = mpv_set_property_string(handle, "panscan", String(screenMode.panscan))
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

    /// 播放中实时改倍速（mpv 的 speed 属性可热改，不用重建播放器）。
    ///
    /// 改完原地精确跳转一次，丢掉已排队的旧倍速音频：Apple TV 的 HDMI 输出上 mpv 的 audiounit
    /// 初始化失败（取声道布局报 -10879），回退到 avfoundation 音频输出，而它固定预读 2 秒
    /// （mpv ao_avfoundation.m：device_buffer = samplerate * 2）。只改 speed 时这 2 秒旧倍速音频
    /// 要先播完，画面停顿或音画不同步 2～4 秒；跳转会清空缓冲、重新对齐音画，新倍速立即生效。
    func setSpeed(_ speed: Double) {
        guard let handle = mpv else { return }
        let previous = getDouble("speed")
        var value = speed
        let status = mpv_set_property(handle, "speed", MPV_FORMAT_DOUBLE, &value)
        guard status >= 0, abs(previous - speed) > 0.001 else { return }
        command(["seek", "0", "relative+exact"])
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
        // wid 是 int64，内容为 CAMetalLayer 的对象地址（mpv 不持有引用；
        // 本控制器的 metalLayer 强引用该图层，句柄销毁前图层一直有效）。
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        _ = mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
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
        applyScreenMode(to: handle)
        let contextPointer = UnsafeMutablePointer<MpvWakeupContext>.allocate(capacity: 1)
        contextPointer.initialize(to: MpvWakeupContext(
            controller: Unmanaged.passUnretained(self), handle: MpvHandle(raw: handle)
        ))
        wakeupContext = contextPointer
        mpv_set_wakeup_callback(handle, mpvWakeup, contextPointer)
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
        let paused = getFlag("pause")
        if paused != isPaused { isPaused = paused }
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
