import Foundation

/// 查一部剧所在的系列（同名剧的第 N 部 / 季）：先看缓存（搜索页归组时会存入），没有就用剧名搜一次
/// （核心搜索会补齐缺失的分部），结果按系列缓存到应用退出。单部剧也只搜一次。
actor SeriesLookup {
    static let shared = SeriesLookup()

    /// 剧 id → 所在系列。
    private var groupsByDrama: [String: SeriesGroup<Drama>] = [:]
    /// 已搜过的「站源|规范化剧名」，避免重复搜索。
    private var searchedKeys: Set<String> = []

    /// 搜索页归组后存入，进详情页时直接命中。
    func remember(_ group: SeriesGroup<Drama>) {
        for part in group.parts {
            groupsByDrama[part.item.id] = group
        }
    }

    func parts(of drama: Drama) async -> SeriesGroup<Drama>? {
        if let cached = groupsByDrama[drama.id] { return cached }
        let base = SeriesTitle.parse(drama.title)?.base ?? drama.title
        let searchKey = drama.source + "|" + SeriesTitle.normalize(base)
        guard searchedKeys.insert(searchKey).inserted else { return groupsByDrama[drama.id] }
        guard let page = try? await CoreClient.shared.catalog(source: drama.source, query: base) else {
            // 搜索失败不记为已搜，下次进详情页再试。
            searchedKeys.remove(searchKey)
            return nil
        }
        var items = page.items
        if !items.contains(where: { $0.id == drama.id }) {
            items.append(drama)
        }
        for entry in SeriesGrouping.group(items, title: \.title, source: \.source) {
            if case .series(let group) = entry {
                remember(group)
            }
        }
        return groupsByDrama[drama.id]
    }
}
