import Testing
@testable import GuoAppLogic

/// 弹幕分行：所有弹幕同一速度，前一条整条进屏（再留一点间隔）后，这一行才放下一条，不会叠在一起；
/// 一下子来太多时，多出来的等行空出来，最多等 2 秒，等不到就不发。
/// 同一句话（不同用户发的同一句，红果一集里常有几十条）屏上最多一条：还在飘或在排队时不再发。
struct DanmakuLayoutTests {
    /// 3 行、每秒 100 pt、间隔 10 pt、屏宽 900：宽 90 的弹幕占住这一行 1 秒，在屏上飘 9.9 秒。
    private func layout(lanes: Int = 3, maxWait: Double = 2, maxWaiting: Int = 24) -> DanmakuLayout {
        DanmakuLayout(lanes: lanes, speed: 100, gap: 10, maxWait: maxWait, maxWaiting: maxWaiting, screenWidth: 900)
    }

    private func lanes(_ placements: [DanmakuLayout.Placement]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: placements.map { ($0.text, $0.lane) })
    }

    @Test func placesIntoTheTopFreeLane() {
        var layout = layout()
        #expect(lanes(layout.submit([("a", 90)], now: 0)) == ["a": 0])
        #expect(lanes(layout.submit([("b", 90)], now: 0.5)) == ["b": 1])
        #expect(lanes(layout.submit([("c", 90)], now: 1.0)) == ["c": 0])
    }

    @Test func aBurstWaitsForAFreeLane() {
        var layout = layout(lanes: 2)
        #expect(lanes(layout.submit([("a", 90), ("b", 90), ("c", 90)], now: 0)) == ["a": 0, "b": 1])
        #expect(layout.nextWake == 1.0)
        #expect(lanes(layout.drain(now: 1.0)) == ["c": 0])
        #expect(layout.nextWake == nil)
    }

    @Test func waitingTooLongIsDropped() {
        var layout = layout(lanes: 1)
        #expect(lanes(layout.submit([("a", 290), ("b", 90)], now: 0)) == ["a": 0])
        #expect(layout.nextWake == 3.0)
        #expect(layout.drain(now: 3.0).isEmpty)
        #expect(layout.nextWake == nil)
    }

    @Test func theWaitingLineIsCapped() {
        var layout = layout(lanes: 1, maxWait: 10, maxWaiting: 3)
        #expect(lanes(layout.submit([("a", 90), ("b", 90), ("c", 90), ("d", 90)], now: 0)) == ["a": 0])
        #expect(lanes(layout.drain(now: 1.0)) == ["b": 0])
        #expect(lanes(layout.drain(now: 2.0)) == ["c": 0])
        #expect(layout.drain(now: 3.0).isEmpty)
    }

    @Test func clearFreesEveryLane() {
        var layout = layout(lanes: 1)
        _ = layout.submit([("a", 90), ("b", 90)], now: 0)
        layout.clear()
        #expect(layout.nextWake == nil)
        #expect(lanes(layout.submit([("c", 90)], now: 0)) == ["c": 0])
    }

    /// 同一速度：越长的弹幕飘得越久（从右边进屏到左边完全出屏）。
    @Test func durationKeepsTheSameSpeed() {
        let layout = layout()
        #expect(layout.duration(width: 100) == 10)
        #expect(layout.duration(width: 300) == 12)
    }

    /// 实测一集里「韩：这下爽了，倒反天罡了[偷笑]」有 89 条：前一条还在屏上时，同一句不再发；飘出屏后可以再来。
    @Test func theSameLineIsNotShownWhileACopyIsOnScreen() {
        var layout = layout()
        #expect(lanes(layout.submit([("倒反天罡", 90)], now: 0)) == ["倒反天罡": 0])
        #expect(lanes(layout.submit([("倒反天罡", 90), ("别的", 90)], now: 1.0)) == ["别的": 0])
        #expect(lanes(layout.submit([("倒反天罡", 90)], now: 9.9)) == ["倒反天罡": 0])
    }

    @Test func theSameLineIsNotQueuedTwice() {
        var layout = layout(lanes: 1)
        #expect(lanes(layout.submit([("a", 90), ("x", 90), ("x", 90)], now: 0)) == ["a": 0])
        #expect(lanes(layout.drain(now: 1.0)) == ["x": 0])
        #expect(layout.nextWake == nil)
    }

    /// 排队等太久被丢掉的那句不算飘过：下一条同样的话照常排上。
    @Test func aDroppedLineDoesNotBlockTheNextCopy() {
        var layout = layout(lanes: 1)
        #expect(lanes(layout.submit([("长", 290), ("倒反天罡", 90)], now: 0)) == ["长": 0])
        #expect(layout.submit([("倒反天罡", 90)], now: 2.5).isEmpty)
        #expect(lanes(layout.drain(now: 3.0)) == ["倒反天罡": 0])
    }

    /// 已经等过头的不占排队名额：新来的照常排上。
    @Test func expiredWaitersDoNotFillTheQueue() {
        var layout = layout(lanes: 1, maxWaiting: 2)
        #expect(lanes(layout.submit([("长", 490), ("b", 90), ("c", 90)], now: 0)) == ["长": 0])
        #expect(layout.submit([("d", 90)], now: 3.0).isEmpty)
        #expect(lanes(layout.drain(now: 5.0)) == ["d": 0])
    }
}
