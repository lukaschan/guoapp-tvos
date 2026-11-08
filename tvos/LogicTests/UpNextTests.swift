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
