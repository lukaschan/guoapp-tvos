import Testing
@testable import GuoAppLogic

/// 剧场换榜单 / 分类时，请求并行后慢的那次可能晚回来：只认最后一次加载的结果。
struct LoadGenerationTests {
    @Test func onlyTheNewestLoadIsCurrent() {
        var loads = LoadGeneration()
        let first = loads.begin()
        let second = loads.begin()
        #expect(!loads.isCurrent(first))
        #expect(loads.isCurrent(second))
    }
}

/// 「大家都在看」：核心刚开始刷新推荐时存着的可能只有一两部，不够 14 部就照常去取。
struct PopularCacheTests {
    @Test func partialCachedFeedIsNotEnough() {
        #expect(!SearchCopy.cachedIsEnough(2))
        #expect(SearchCopy.cachedIsEnough(14))
        #expect(SearchCopy.cachedIsEnough(20))
    }
}

/// 「接下来」有焦点时，新推荐先存着，焦点离开这一行再接到 hero 后面（行里的海报不会突然消失、焦点不乱跳）。
struct DeferredFreshTests {
    @Test func appliesAtOnceWhenRowNotFocused() {
        var deferred = DeferredFresh<String>()
        #expect(deferred.offer(["x", "y"], rowFocused: false) == ["x", "y"])
        #expect(deferred.rowFocusEnded() == nil)
    }

    @Test func waitsWhileRowFocused() {
        var deferred = DeferredFresh<String>()
        #expect(deferred.offer(["x", "y"], rowFocused: true) == nil)
        #expect(deferred.rowFocusEnded() == ["x", "y"])
        #expect(deferred.rowFocusEnded() == nil)
    }

    @Test func newestOfferWins() {
        var deferred = DeferredFresh<String>()
        _ = deferred.offer(["x"], rowFocused: true)
        _ = deferred.offer(["y", "z"], rowFocused: true)
        #expect(deferred.rowFocusEnded() == ["y", "z"])
    }
}
