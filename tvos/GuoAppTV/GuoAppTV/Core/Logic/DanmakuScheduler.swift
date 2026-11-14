import Foundation

/// 弹幕调度（纯规则）：开关、要不要拉一页、这一秒该发哪几条。DanmakuEngine 按它拉取和投递。
/// 全屏播放时可随时开关：关着不拉取、不发；再打开从当前位置接着发，不补关着时错过的，也不重复已经发过的。
/// 同一句话不同用户发的多条，在 DanmakuLayout 里合并（屏上最多一条）。
struct DanmakuScheduler {
    /// 每次投递当前位置起 1 秒内的弹幕（进度每秒刷新一次）。
    static let windowMs = 1_000
    /// 离本页结尾还剩 2 秒时拉下一页。
    static let fetchLeadMs = 2_000
    /// 发过的记录超过这么多条就清空，免得一直涨。
    static let sentLimit = 2_000

    private(set) var isEnabled: Bool
    private var sent = Set<String>()

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// 播放中开关弹幕。发过的记录保留：同一秒里关了又开，已经飘过的不再发一遍。
    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }

    /// 换集 / 换线路：清空发过的记录。
    mutating func reset() {
        sent.removeAll()
    }

    /// 要不要拉一页：还没有、快到本页结尾、或跳回到本页之前。关着时不拉。
    func needsPage(positionMs: Int, page: (startMs: Int, nextMs: Int)?) -> Bool {
        guard isEnabled else { return false }
        guard let page else { return true }
        return positionMs >= page.nextMs - Self.fetchLeadMs || positionMs < page.startMs
    }

    /// 到点该发的弹幕（当前位置起 1 秒内、还没发过的），并记为已发。关着时为空。
    mutating func due<Item>(
        _ items: [Item],
        positionMs: Int,
        id: (Item) -> String,
        timeMs: (Item) -> Int
    ) -> [Item] {
        guard isEnabled else { return [] }
        if sent.count > Self.sentLimit { sent.removeAll() }
        var result: [Item] = []
        for item in items {
            let time = timeMs(item)
            guard time >= positionMs, time < positionMs + Self.windowMs, sent.insert(id(item)).inserted else {
                continue
            }
            result.append(item)
        }
        return result
    }
}
