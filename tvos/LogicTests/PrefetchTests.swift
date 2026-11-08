import Testing
@testable import GuoAppLogic

struct PrefetchTests {
    @Test func idleStartsImmediately() {
        var slot = PrefetchSlot<String>()
        #expect(slot.request("a") == "a")
    }

    @Test func busyQueuesOnlyTheNewest() {
        var slot = PrefetchSlot<String>()
        #expect(slot.request("a") == "a")
        #expect(slot.request("b") == nil)
        #expect(slot.request("c") == nil)
        #expect(slot.finished() == "c")
        #expect(slot.finished() == nil)
        // 空闲后新的请求又能立刻开始。
        #expect(slot.request("d") == "d")
    }

    @Test func finishedWhenIdleReturnsNil() {
        var slot = PrefetchSlot<String>()
        #expect(slot.finished() == nil)
    }

    @Test func planTakesTheNextEight() {
        let items = (0..<12).map { "d\($0)" }
        #expect(PosterPrefetchPlan.items(after: "d2", in: items, id: { $0 }) == (3...10).map { "d\($0)" })
        #expect(PosterPrefetchPlan.ahead == 8)
    }

    @Test func planNearTheEndTakesWhatIsLeft() {
        let items = (0..<12).map { "d\($0)" }
        #expect(PosterPrefetchPlan.items(after: "d10", in: items, id: { $0 }) == ["d11"])
    }

    @Test func planEmptyForUnknownID() {
        #expect(PosterPrefetchPlan.items(after: "zz", in: ["a", "b"], id: { $0 }).isEmpty)
    }
}
