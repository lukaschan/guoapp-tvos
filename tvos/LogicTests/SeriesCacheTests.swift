import Testing
@testable import GuoAppLogic

private struct Show: Sendable, Equatable {
    let id: String
    let title: String
}

/// 记录被调用了几次的假搜索。
private actor FakeSearch {
    private(set) var calls = 0
    let results: [Show]?
    init(results: [Show]?) { self.results = results }
    func run() async -> [Show]? {
        calls += 1
        try? await Task.sleep(for: .milliseconds(50))
        return results
    }
}

private func cache(_ search: FakeSearch) -> SeriesCache<Show> {
    SeriesCache(search: { _, _ in await search.run() }, id: { $0.id }, title: { $0.title }, source: { _ in "hongguo" })
}

struct SeriesCacheTests {
    private let part1 = Show(id: "a", title: "霸总")
    private let part2 = Show(id: "b", title: "霸总 第二部")

    /// 同一系列同时查两次（退出又进详情、或同时打开另一部）：只搜一次，两边都拿到本系列。
    @Test func concurrentLookupsSearchOnce() async {
        let search = FakeSearch(results: [part1, part2])
        let lookup = cache(search)
        async let first = lookup.parts(of: part1)
        async let second = lookup.parts(of: part2)
        let (one, two) = await (first, second)
        #expect(one?.partNumbers == [1, 2])
        #expect(two?.partNumbers == [1, 2])
        #expect(await search.calls == 1)
    }

    /// 搜索失败不记为已搜，下次再试。
    @Test func failureIsRetried() async {
        let search = FakeSearch(results: nil)
        let lookup = cache(search)
        #expect(await lookup.parts(of: part1) == nil)
        #expect(await lookup.parts(of: part1) == nil)
        #expect(await search.calls == 2)
    }

    /// 搜索页存入的系列直接命中，不再搜索。
    @Test func rememberedGroupSkipsSearch() async {
        let search = FakeSearch(results: [])
        let lookup = cache(search)
        guard case .series(let group)? = SeriesGrouping.group([part1, part2], title: \.title, source: { _ in "hongguo" }).first else {
            Issue.record("expected a series")
            return
        }
        await lookup.remember(group)
        #expect(await lookup.parts(of: part2)?.partNumbers == [1, 2])
        #expect(await search.calls == 0)
    }
}

struct EpisodeCountTests {
    /// 目录 / 详情里的剧信息没给总集数（0）时，用详情分集列表的数量补上。
    @Test func backfillsUnknownTotal() {
        #expect(EpisodeCount.effective(reported: 0, detailCount: 42) == 42)
        #expect(EpisodeCount.effective(reported: 80, detailCount: 79) == 80)
        #expect(EpisodeCount.effective(reported: 0, detailCount: 0) == 0)
    }
}
