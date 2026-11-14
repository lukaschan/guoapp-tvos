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
        async let first = lookup.outcome(of: part1)
        async let second = lookup.outcome(of: part2)
        let (one, two) = await (first, second)
        #expect(one.group?.partNumbers == [1, 2])
        #expect(two.group?.partNumbers == [1, 2])
        #expect(await search.calls == 1)
    }

    /// 搜索失败：报「没查成」（详情页显示重试，不当成没有其他部），也不记为已搜，下次再试。
    @Test func failureIsReportedAndRetried() async {
        let search = FakeSearch(results: nil)
        let lookup = cache(search)
        #expect(await lookup.outcome(of: part1) == .failed)
        #expect(await lookup.outcome(of: part1) == .failed)
        #expect(await search.calls == 2)
    }

    /// 同时查、搜索失败：等同一次搜索的那一边也拿到「没查成」，不是「没有其他部」。
    @Test func concurrentWaiterSeesTheFailure() async {
        let search = FakeSearch(results: nil)
        let lookup = cache(search)
        async let first = lookup.outcome(of: part1)
        async let second = lookup.outcome(of: part1)
        let (one, two) = await (first, second)
        #expect(one == .failed)
        #expect(two == .failed)
        #expect(await search.calls == 1)
    }

    /// 搜到了但没有其他部：报「单部剧」，本次运行内不再搜。
    @Test func noOtherPartsIsSingle() async {
        let search = FakeSearch(results: [part1])
        let lookup = cache(search)
        #expect(await lookup.outcome(of: part1) == .single)
        #expect(await lookup.outcome(of: part1) == .single)
        #expect(await search.calls == 1)
    }

    /// 实测搜「五灵根修仙：我有一个吞噬空间」：两部不带后缀的同名剧排在「…第1季」前面。第 1 季归写明的那部，
    /// 但从不带后缀的那部进详情也要有本系列（它自己顶第 1 季），不能查完就什么都不显示。
    @Test func bareTitleBesideExplicitFirstPartStillFindsItsSeries() async {
        let bare = Show(id: "bare", title: "五灵根修仙：我有一个吞噬空间")
        let bareBang = Show(id: "bang", title: "五灵根修仙：我有一个吞噬空间！")
        let first = Show(id: "s1", title: "五灵根修仙：我有一个吞噬空间！第1季")
        let second = Show(id: "s2", title: "五灵根修仙：我有一个吞噬空间！第二季")
        let third = Show(id: "s3", title: "五灵根修仙：我有一个吞噬空间（第三季）")
        let search = FakeSearch(results: [bare, bareBang, first, second, third])
        let lookup = cache(search)
        #expect(await lookup.outcome(of: bare).group?.parts.map(\.item.id) == ["bare", "s2", "s3"])
        #expect(await lookup.outcome(of: bareBang).group?.parts.map(\.item.id) == ["bang", "s2", "s3"])
        #expect(await lookup.outcome(of: first).group?.parts.map(\.item.id) == ["s1", "s2", "s3"])
        #expect(await lookup.outcome(of: second).group?.parts.map(\.item.id) == ["s1", "s2", "s3"])
        #expect(await search.calls == 1)
    }

    /// 同一季有两个上传（都写明第二季）：排不进系列的那一部进详情也要有本系列。
    @Test func duplicateExplicitPartStillFindsItsSeries() async {
        let other = Show(id: "b2", title: "霸总第2部")
        let search = FakeSearch(results: [part1, part2, other])
        let lookup = cache(search)
        #expect(await lookup.outcome(of: other).group?.parts.map(\.item.id) == ["a", "b2"])
        #expect(await lookup.outcome(of: part2).group?.parts.map(\.item.id) == ["a", "b"])
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
        #expect(await lookup.outcome(of: part2).group?.partNumbers == [1, 2])
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
