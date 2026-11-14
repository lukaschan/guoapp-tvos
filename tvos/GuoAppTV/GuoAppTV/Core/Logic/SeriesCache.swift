import Foundation

/// 查一部剧所在的系列（纯逻辑、可测，搜索由调用方注入）：
/// - 先看缓存（搜索页归组时会存入）；
/// - 同一系列（站源 + 规范化剧名）并发查询只搜一次，后到的等同一次搜索的结果；
/// - 搜索成功（哪怕没找到其他部）记为已搜，本次运行内不再搜；搜索失败不记，下次再试。
/// - 结果分三种（SeriesOutcome）：详情页据此显示本系列、什么都不显示、或「没查到 · 重试」——
///   搜索失败不能当成「没有其他部」，否则看的人会以为这部剧没有续集。
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

    /// 系列里每一部都记下本系列；部数相同、没排进系列的同名剧（group.alternates）也记，
    /// 它看到的本系列由它自己顶替同部数的那一部——否则从它进详情，查完就什么都不显示。
    func remember(_ group: SeriesGroup<Item>) {
        for part in group.parts {
            groupsByID[id(part.item)] = group
        }
        for alternate in group.alternates {
            groupsByID[id(alternate.item)] = group.substituting(alternate)
        }
    }

    func outcome(of item: Item) async -> SeriesOutcome<Item> {
        if let cached = groupsByID[id(item)] { return .found(cached) }
        let base = SeriesTitle.parse(title(item))?.base ?? title(item)
        let itemSource = source(item)
        let key = itemSource + "|" + SeriesTitle.normalize(base)
        if let running = inFlight[key] {
            await running.value
            return settled(item, key: key)
        }
        guard !searchedKeys.contains(key) else { return settled(item, key: key) }
        let search = self.search
        let task = Task {
            let results = await search(itemSource, base)
            self.store(results, including: item, key: key)
        }
        inFlight[key] = task
        await task.value
        inFlight[key] = nil
        return settled(item, key: key)
    }

    /// 这一系列搜过之后的结果：搜成功了看有没有归进系列，没搜成就是「没查成」。
    private func settled(_ item: Item, key: String) -> SeriesOutcome<Item> {
        if let group = groupsByID[id(item)] { return .found(group) }
        return searchedKeys.contains(key) ? .single : .failed
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

/// 查本系列的结果。
enum SeriesOutcome<Item> {
    /// 找到了同一系列的其他部。
    case found(SeriesGroup<Item>)
    /// 搜过了，没有其他部（单部剧）。
    case single
    /// 搜索失败，没查成（下次再试）。
    case failed

    var group: SeriesGroup<Item>? {
        if case .found(let group) = self { return group }
        return nil
    }
}

extension SeriesOutcome: Sendable where Item: Sendable {}
extension SeriesOutcome: Equatable where Item: Equatable {}
