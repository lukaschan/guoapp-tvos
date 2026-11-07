import Foundation

/// 查一部剧所在的系列（纯逻辑、可测，搜索由调用方注入）：
/// - 先看缓存（搜索页归组时会存入）；
/// - 同一系列（站源 + 规范化剧名）并发查询只搜一次，后到的等同一次搜索的结果；
/// - 搜索成功（哪怕没找到其他部）记为已搜，本次运行内不再搜；搜索失败不记，下次再试。
actor SeriesCache<Item: Sendable> {
    typealias Search = @Sendable (_ source: String, _ query: String) async -> [Item]?

    private let search: Search
    private let id: @Sendable (Item) -> String
    private let title: @Sendable (Item) -> String
    private let source: @Sendable (Item) -> String

    private var groupsByID: [String: SeriesGroup<Item>] = [:]
    private var searchedKeys: Set<String> = []
    private var inFlight: [String: Task<Void, Never>] = [:]

    init(
        search: @escaping Search,
        id: @escaping @Sendable (Item) -> String,
        title: @escaping @Sendable (Item) -> String,
        source: @escaping @Sendable (Item) -> String
    ) {
        self.search = search
        self.id = id
        self.title = title
        self.source = source
    }

    func remember(_ group: SeriesGroup<Item>) {
        for part in group.parts {
            groupsByID[id(part.item)] = group
        }
    }

    func parts(of item: Item) async -> SeriesGroup<Item>? {
        if let cached = groupsByID[id(item)] { return cached }
        let base = SeriesTitle.parse(title(item))?.base ?? title(item)
        let itemSource = source(item)
        let key = itemSource + "|" + SeriesTitle.normalize(base)
        if let running = inFlight[key] {
            await running.value
            return groupsByID[id(item)]
        }
        guard !searchedKeys.contains(key) else { return groupsByID[id(item)] }
        let search = self.search
        let task = Task {
            let results = await search(itemSource, base)
            self.store(results, including: item, key: key)
        }
        inFlight[key] = task
        await task.value
        inFlight[key] = nil
        return groupsByID[id(item)]
    }

    private func store(_ results: [Item]?, including item: Item, key: String) {
        guard var items = results else { return }
        searchedKeys.insert(key)
        if !items.contains(where: { id($0) == id(item) }) {
            items.append(item)
        }
        for case .series(let group) in SeriesGrouping.group(items, title: title, source: source) {
            remember(group)
        }
    }
}
