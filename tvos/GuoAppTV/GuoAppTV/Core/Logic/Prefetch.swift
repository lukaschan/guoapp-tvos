import Foundation

/// 焦点预取的单通道：同一时间最多一个在取，等待的只留最新那一个
///（核心是串行队列，快速扫过一排海报不能把请求堆起来，挡住封面和起播）。
struct PrefetchSlot<Item: Equatable & Sendable>: Equatable, Sendable {
    private(set) var isBusy = false
    private(set) var queued: Item?

    init() {}

    /// 空闲时返回 item（现在就开始，进入忙碌）；忙碌时把它排上（替换先前排着的），返回 nil。
    mutating func request(_ item: Item) -> Item? {
        if isBusy {
            queued = item
            return nil
        }
        isBusy = true
        return item
    }

    /// 当前这个取完了：有排着的就返回它（继续忙碌），否则回到空闲、返回 nil。
    mutating func finished() -> Item? {
        if let next = queued {
            queued = nil
            return next
        }
        isBusy = false
        return nil
    }
}

/// 海报获得焦点时预先加载哪些封面：它后面的 ahead 张（网格里差不多是本行余下 + 下一行开头）。
enum PosterPrefetchPlan {
    static let ahead = 8

    static func items<Item>(after id: String, in items: [Item], id identifier: (Item) -> String) -> [Item] {
        guard let index = items.firstIndex(where: { identifier($0) == id }) else { return [] }
        return Array(items[(index + 1)...].prefix(ahead))
    }
}
