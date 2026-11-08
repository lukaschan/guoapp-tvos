import Testing
@testable import GuoAppLogic

struct UpNextTests {
    @Test func nextTenAfterCurrent() {
        #expect(UpNext.window(count: 15, current: 0) == Array(1...10))
    }

    @Test func wrapsAroundAndSkipsCurrent() {
        #expect(UpNext.window(count: 5, current: 3) == [4, 0, 1, 2])
    }

    @Test func singleDramaHasNoUpNext() {
        #expect(UpNext.window(count: 1, current: 0) == [])
    }

    @Test func emptyFeed() {
        #expect(UpNext.window(count: 0, current: 0) == [])
    }

    @Test func respectsLimit() {
        #expect(UpNext.window(count: 15, current: 12, limit: 4) == [13, 14, 0, 1])
    }
}

/// 「接下来」行有焦点时冻结内容：按下切换后被选中的海报不被挤走，焦点不会落到别的海报上自己开始预览。
struct UpNextFreezeTests {
    @Test func showsCurrentWhenRowNotFocused() {
        let freeze = UpNextFreeze()
        #expect(freeze.visibleIDs(current: ["b", "c"]) == ["b", "c"])
    }

    @Test func committedPosterStaysWhileRowFocused() {
        var freeze = UpNextFreeze()
        freeze.rowFocusChanged(isFocused: true, currentIDs: ["b", "c", "d"])
        // 按下 b：b 成为 hero，推荐流的「接下来」变成 c、d、a——行里仍是进入时的 b、c、d。
        #expect(freeze.visibleIDs(current: ["c", "d", "a"]) == ["b", "c", "d"])
    }

    @Test func movingWithinRowKeepsFrozenList() {
        var freeze = UpNextFreeze()
        freeze.rowFocusChanged(isFocused: true, currentIDs: ["b", "c", "d"])
        freeze.rowFocusChanged(isFocused: true, currentIDs: ["c", "d", "a"])
        #expect(freeze.visibleIDs(current: ["c", "d", "a"]) == ["b", "c", "d"])
    }

    @Test func refreshesAfterLeavingRow() {
        var freeze = UpNextFreeze()
        freeze.rowFocusChanged(isFocused: true, currentIDs: ["b", "c", "d"])
        freeze.rowFocusChanged(isFocused: false, currentIDs: ["c", "d", "a"])
        #expect(freeze.visibleIDs(current: ["c", "d", "a"]) == ["c", "d", "a"])
    }
}
