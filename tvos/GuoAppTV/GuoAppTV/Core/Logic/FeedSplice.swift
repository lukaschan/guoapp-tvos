import Foundation

/// 启动时先显示核心存着的推荐，新取到的推荐回来后接到 hero 后面：
/// hero 和它之前的（已经看过 / 正在看的）原样保留，后面换成新的推荐（去重、丢掉没有 id 的）。
/// 正在播的不会被打断，「接下来」换成新的一批。
/// 新推荐回来时「接下来」若有焦点就先存着，焦点离开这一行再接上：
/// 否则行里的海报会在焦点下面消失、焦点乱跳。只留最新的一份。
struct DeferredFresh<Item: Sendable>: Sendable {
    private var pending: [Item]?

    init() {}

    /// 返回要现在接上的一份；行有焦点时存着、返回 nil。
    mutating func offer(_ fresh: [Item], rowFocused: Bool) -> [Item]? {
        guard rowFocused else {
            pending = nil
            return fresh
        }
        pending = fresh
        return nil
    }

    /// 焦点离开这一行：返回存着的那份（没有就是 nil）。
    mutating func rowFocusEnded() -> [Item]? {
        defer { pending = nil }
        return pending
    }
}

enum FeedSplice {
    static func splice<Item>(existing: [Item], currentIndex: Int, fresh: [Item], id: (Item) -> String) -> [Item] {
        let kept = existing.indices.contains(currentIndex) ? Array(existing[...currentIndex]) : []
        var seen = Set(kept.map(id))
        var result = kept
        for item in fresh {
            let key = id(item)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(item)
        }
        return result
    }
}
