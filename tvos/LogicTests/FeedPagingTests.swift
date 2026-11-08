import Testing
@testable import GuoAppLogic

/// 推荐流往后续：hero 接近剧单末尾、「接下来」快要绕回开头时，先取下一批，而不是循环同一批。
struct FeedPagingTests {
    @Test func loadsMoreBeforeUpNextWouldWrap() {
        #expect(FeedPaging.shouldLoadMore(currentIndex: 5, count: 15, hasMore: true, loading: false))
        #expect(!FeedPaging.shouldLoadMore(currentIndex: 0, count: 15, hasMore: true, loading: false))
    }

    @Test func noMoreWhenFeedIsExhaustedOrBusy() {
        #expect(!FeedPaging.shouldLoadMore(currentIndex: 14, count: 15, hasMore: false, loading: false))
        #expect(!FeedPaging.shouldLoadMore(currentIndex: 14, count: 15, hasMore: true, loading: true))
    }

    @Test func mergeAppendsOnlyNewItemsKeepingOrder() {
        #expect(FeedPaging.merge(existing: ["a", "b", "c"], incoming: ["a", "b", "c", "d", "e"], id: { $0 })
            == ["a", "b", "c", "d", "e"])
        #expect(FeedPaging.merge(existing: ["a", "b", "c"], incoming: ["c", "a", "f"], id: { $0 }) == ["a", "b", "c", "f"])
    }

    /// 实测：核心的 more 有时一批里没有新剧、但仍说还有更多（1→6→11→11→16→16→20）。空的一批不算到底，连续 3 批空才停。
    @Test func emptyBatchKeepsPaging() {
        #expect(FeedPaging.afterBatch(hasMore: true, grew: false, emptyBatches: 0) == FeedPaging.Progress(hasMore: true, emptyBatches: 1))
    }

    @Test func stopsAfterThreeEmptyBatches() {
        #expect(FeedPaging.afterBatch(hasMore: true, grew: false, emptyBatches: 2) == FeedPaging.Progress(hasMore: false, emptyBatches: 3))
        #expect(FeedPaging.maxEmptyBatches == 3)
    }

    @Test func growthResetsEmptyCount() {
        #expect(FeedPaging.afterBatch(hasMore: true, grew: true, emptyBatches: 2) == FeedPaging.Progress(hasMore: true, emptyBatches: 0))
    }

    @Test func coreSaysNoMore() {
        #expect(FeedPaging.afterBatch(hasMore: false, grew: true, emptyBatches: 0) == FeedPaging.Progress(hasMore: false, emptyBatches: 0))
    }

    @Test func mergeDropsItemsWithoutID() {
        #expect(FeedPaging.merge(existing: ["a"], incoming: ["", "b", "b"], id: { $0 }) == ["a", "b"])
    }
}

/// 「大家都在看」的显示状态：取回 0 部也是一种状态（给提示和重试），不能留白。
struct PopularStateTests {
    @Test func emptyResultIsItsOwnState() {
        #expect(PopularState.make(count: 0, loading: false, error: nil) == .empty)
    }

    @Test func otherStates() {
        #expect(PopularState.make(count: 14, loading: false, error: nil) == .posters)
        #expect(PopularState.make(count: 0, loading: true, error: nil) == .loading)
        #expect(PopularState.make(count: 0, loading: false, error: "x") == .failed("x"))
        // 已有海报时重新加载：照旧显示海报。
        #expect(PopularState.make(count: 14, loading: true, error: nil) == .posters)
    }
}
