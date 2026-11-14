import Foundation

/// 推荐流往后续（与上游「发现」页一致：用 more 继续取，而不是循环同一批）。
enum FeedPaging {
    /// hero 之后剩下的不够填满「接下来」（10 部）时，先取下一批；没有更多或正在取时不取。
    static func shouldLoadMore(currentIndex: Int, count: Int, hasMore: Bool, loading: Bool) -> Bool {
        guard hasMore, !loading else { return false }
        let remaining = count - currentIndex - 1
        return remaining < UpNext.defaultLimit
    }

    /// 连续这么多批都没有新剧才认为暂时取完（实测核心的 more 偶尔会空一批，但后面还有）。
    static let maxEmptyBatches = 3

    struct Progress: Equatable, Sendable {
        let hasMore: Bool
        let emptyBatches: Int
    }

    /// 取完一批之后：有新剧就清零空批计数；空的一批记一次，连续 maxEmptyBatches 批空才停；核心说没有更多就停。
    static func afterBatch(hasMore: Bool, grew: Bool, emptyBatches: Int) -> Progress {
        guard hasMore else { return Progress(hasMore: false, emptyBatches: grew ? 0 : emptyBatches) }
        if grew { return Progress(hasMore: true, emptyBatches: 0) }
        let empties = emptyBatches + 1
        return Progress(hasMore: empties < maxEmptyBatches, emptyBatches: empties)
    }

    /// 把新取到的（核心返回的是累积的整份列表）接在已有的后面：已有的顺序不变，只追加新的，丢掉没有 id 的。
    static func merge<Item>(existing: [Item], incoming: [Item], id: (Item) -> String) -> [Item] {
        var seen = Set(existing.map(id))
        var merged = existing
        for item in incoming {
            let key = id(item)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            merged.append(item)
        }
        return merged
    }
}
