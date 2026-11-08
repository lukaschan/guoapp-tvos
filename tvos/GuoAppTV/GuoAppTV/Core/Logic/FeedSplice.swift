import Foundation

/// 启动时先显示核心存着的推荐，新取到的推荐回来后接到 hero 后面：
/// hero 和它之前的（已经看过 / 正在看的）原样保留，后面换成新的推荐（去重、丢掉没有 id 的）。
/// 正在播的不会被打断，「接下来」换成新的一批。
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
