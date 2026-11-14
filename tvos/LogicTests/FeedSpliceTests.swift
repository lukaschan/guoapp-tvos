import Testing
@testable import GuoAppLogic

/// 启动时先显示存着的推荐，新的推荐回来后：hero 和它之前的不动，后面换成新的（不打断正在播的）。
struct FeedSpliceTests {
    @Test func keepsHeroAndEarlierThenFresh() {
        #expect(FeedSplice.splice(existing: ["a", "b", "c", "d", "e"], currentIndex: 1, fresh: ["x", "b", "y", "z"], id: { $0 })
            == ["a", "b", "x", "y", "z"])
    }

    @Test func outOfRangeIndexTakesFresh() {
        #expect(FeedSplice.splice(existing: [String](), currentIndex: 0, fresh: ["x", "x", "y"], id: { $0 }) == ["x", "y"])
    }

    @Test func dropsEmptyIDs() {
        #expect(FeedSplice.splice(existing: ["a"], currentIndex: 0, fresh: ["", "b"], id: { $0 }) == ["a", "b"])
    }
}
