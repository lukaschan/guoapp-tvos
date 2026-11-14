import Foundation

/// 弹幕分行（纯规则）：DanmakuOverlayView 按它决定每条弹幕放哪一行、什么时候放、要不要放。
/// - 所有弹幕同一速度，后一条追不上前一条；前一条整条进屏、再留出间隔后，这一行才放下一条——不会叠在一起。
/// - 放在最上面的空行。一下子来太多（实测一秒 27 条）时，多出来的排队等行空出来，最多等 maxWait 秒，
///   等不到就不发；排队最多 maxWaiting 条，再多的直接不发（已经等过头的先清掉，不占名额）。
/// - 合并相同弹幕：同一句话（不同用户发的同一句，红果一集里常有几十条）屏上最多一条——还在飘或在排队时不再发，
///   飘出屏后可以再来；排队等过头被丢掉的不算飘过。
/// 时间单位为秒（调用方用 CACurrentMediaTime），宽度、屏宽与速度为 pt。
struct DanmakuLayout {
    struct Placement: Equatable {
        let text: String
        let width: Double
        let lane: Int
    }

    let lanes: Int
    let speed: Double
    let gap: Double
    let maxWait: Double
    let maxWaiting: Int
    /// 屏宽：决定一条弹幕在屏上飘多久（浮层尺寸变了由调用方更新）。
    var screenWidth: Double

    /// 每一行最早能放下一条的时间。
    private var freeAt: [Double]
    private var waiting: [(text: String, width: Double, since: Double)] = []
    /// 屏上每句话最后一条完全飘出屏的时间。
    private var onScreenUntil: [String: Double] = [:]

    init(
        lanes: Int = 6, speed: Double = 240, gap: Double = 48, maxWait: Double = 2, maxWaiting: Int = 24,
        screenWidth: Double = 1920
    ) {
        self.lanes = lanes
        self.speed = speed
        self.gap = gap
        self.maxWait = maxWait
        self.maxWaiting = maxWaiting
        self.screenWidth = screenWidth
        freeAt = Array(repeating: 0, count: lanes)
    }

    /// 从右边进屏到左边完全出屏要飘多久。
    func duration(width: Double) -> Double {
        (screenWidth + width) / speed
    }

    /// 还有弹幕在排队时，最早哪个时间有行空出来（到时调 drain）；没有排队为 nil。
    var nextWake: Double? {
        waiting.isEmpty ? nil : freeAt.min()
    }

    /// 新来的弹幕排到队尾（同一句还在屏上或已在排队的跳过），返回现在就能放上的（先放排得早的）。
    mutating func submit(_ comments: [(text: String, width: Double)], now: Double) -> [Placement] {
        dropExpired(now: now)
        for comment in comments where waiting.count < maxWaiting {
            let onScreen = (onScreenUntil[comment.text] ?? 0) > now
            guard !onScreen, !waiting.contains(where: { $0.text == comment.text }) else { continue }
            waiting.append((comment.text, comment.width, now))
        }
        return drain(now: now)
    }

    /// 排队的弹幕再放一次：等太久的丢掉，其余按顺序放进空出来的行。
    mutating func drain(now: Double) -> [Placement] {
        dropExpired(now: now)
        var placed: [Placement] = []
        while let next = waiting.first, let lane = freeAt.firstIndex(where: { $0 <= now }) {
            waiting.removeFirst()
            freeAt[lane] = now + (next.width + gap) / speed
            onScreenUntil[next.text] = now + duration(width: next.width)
            placed.append(Placement(text: next.text, width: next.width, lane: lane))
        }
        return placed
    }

    /// 关弹幕、换集、退出：清空所有行、排队与屏上记录。
    mutating func clear() {
        freeAt = Array(repeating: 0, count: lanes)
        waiting.removeAll()
        onScreenUntil.removeAll()
    }

    private mutating func dropExpired(now: Double) {
        waiting.removeAll { now - $0.since > maxWait }
        if onScreenUntil.count > 200 {
            onScreenUntil = onScreenUntil.filter { $0.value > now }
        }
    }
}
