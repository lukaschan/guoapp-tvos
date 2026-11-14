import Testing
@testable import GuoAppLogic

/// 全屏播放时弹幕可随时开关：关着不拉取、不发；再打开从当前位置接着发，不补关着时错过的，也不重复发过的。
struct DanmakuSchedulerTests {
    private struct Item: Equatable {
        let id: String
        let timeMs: Int
    }

    private static let items = [
        Item(id: "a", timeMs: 1_200),
        Item(id: "b", timeMs: 1_900),
        Item(id: "c", timeMs: 3_000),
        Item(id: "d", timeMs: 5_400),
    ]

    private func due(_ scheduler: inout DanmakuScheduler, at positionMs: Int) -> [String] {
        scheduler.due(Self.items, positionMs: positionMs, id: \.id, timeMs: \.timeMs).map(\.id)
    }

    @Test func startsWithThePreference() {
        #expect(DanmakuScheduler(isEnabled: true).isEnabled)
        #expect(!DanmakuScheduler(isEnabled: false).isEnabled)
    }

    @Test func sendsTheCurrentSecondOnce() {
        var scheduler = DanmakuScheduler(isEnabled: true)
        #expect(due(&scheduler, at: 1_000) == ["a", "b"])
        #expect(due(&scheduler, at: 1_100).isEmpty)
    }

    @Test func offSendsNothingAndFetchesNothing() {
        var scheduler = DanmakuScheduler(isEnabled: true)
        scheduler.setEnabled(false)
        #expect(!scheduler.isEnabled)
        #expect(due(&scheduler, at: 1_000).isEmpty)
        #expect(!scheduler.needsPage(positionMs: 1_000, page: nil))
    }

    /// 1 秒处关掉、5 秒处再打开：只发 5 秒这一秒的，2～4 秒间错过的不补。
    @Test func turningBackOnResumesAtTheCurrentPosition() {
        var scheduler = DanmakuScheduler(isEnabled: true)
        #expect(due(&scheduler, at: 1_000) == ["a", "b"])
        scheduler.setEnabled(false)
        scheduler.setEnabled(true)
        #expect(scheduler.needsPage(positionMs: 5_000, page: nil))
        #expect(due(&scheduler, at: 5_000) == ["d"])
    }

    /// 同一秒里关了又开：已经飘过的不再发一遍。
    @Test func turningBackOnDoesNotRepeat() {
        var scheduler = DanmakuScheduler(isEnabled: true)
        #expect(due(&scheduler, at: 1_000) == ["a", "b"])
        scheduler.setEnabled(false)
        scheduler.setEnabled(true)
        #expect(due(&scheduler, at: 1_000).isEmpty)
    }

    @Test func fetchesWithoutAPageNearItsEndOrAfterSeekingBack() {
        let scheduler = DanmakuScheduler(isEnabled: true)
        let page = (startMs: 10_000, nextMs: 70_000)
        #expect(scheduler.needsPage(positionMs: 0, page: nil))
        #expect(!scheduler.needsPage(positionMs: 30_000, page: page))
        #expect(scheduler.needsPage(positionMs: 68_000, page: page))
        #expect(scheduler.needsPage(positionMs: 9_000, page: page))
    }

    /// 换集（reset）后发过的记录清空，新一集同样的时间点照常发。
    @Test func resetForgetsWhatWasSent() {
        var scheduler = DanmakuScheduler(isEnabled: true)
        #expect(due(&scheduler, at: 1_000) == ["a", "b"])
        scheduler.reset()
        #expect(due(&scheduler, at: 1_000) == ["a", "b"])
    }
}
