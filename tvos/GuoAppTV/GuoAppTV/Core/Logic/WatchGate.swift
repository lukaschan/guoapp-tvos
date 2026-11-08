import Foundation

/// 推荐页 hero 的「真正看了」门槛：随手划过的预览不该进观看记录，
/// 只有不暂停、正常往前播累计满 threshold 秒后才放行存进度。
/// 拖动 / 跳转（一次前进超过 maximumStep 秒或往回跳）不计入。
struct WatchGate: Sendable {
    /// 两次观测（约每秒一次）之间最多算多少秒：容下 3 倍速与偶尔晚到的一拍，挡住跳转。
    static let maximumStep = 4.0

    let threshold: Double
    private(set) var watched: Double = 0
    private var lastPosition: Double?

    init(threshold: Double = 30) {
        self.threshold = threshold
    }

    var isOpen: Bool { watched >= threshold }

    mutating func observe(position: Double, paused: Bool) {
        defer { lastPosition = position }
        guard !paused, let lastPosition else { return }
        let delta = position - lastPosition
        if delta > 0, delta <= Self.maximumStep {
            watched += delta
        }
    }

    mutating func reset() {
        watched = 0
        lastPosition = nil
    }
}
