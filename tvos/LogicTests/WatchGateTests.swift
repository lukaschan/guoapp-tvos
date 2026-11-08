import Testing
@testable import GuoAppLogic

struct WatchGateTests {
    /// 从 0 起每秒一次观测，共 count 次（第一次只建立基准）。
    private func play(_ gate: inout WatchGate, count: Int, step: Double = 1, paused: Bool = false) {
        for index in 0..<count {
            gate.observe(position: Double(index) * step, paused: paused)
        }
    }

    @Test func closedBeforeThirtySeconds() {
        var gate = WatchGate()
        play(&gate, count: 29)
        #expect(!gate.isOpen)
    }

    @Test func opensAtThirty() {
        var gate = WatchGate()
        play(&gate, count: 31)
        #expect(gate.isOpen)
    }

    @Test func pausedTimeDoesNotCount() {
        var gate = WatchGate()
        play(&gate, count: 40, paused: true)
        #expect(!gate.isOpen)
    }

    @Test func seekJumpDoesNotCount() {
        var gate = WatchGate(threshold: 2)
        gate.observe(position: 0, paused: false)
        gate.observe(position: 25, paused: false)
        gate.observe(position: 26, paused: false)
        #expect(!gate.isOpen)
    }

    @Test func backwardJumpDoesNotCount() {
        var gate = WatchGate(threshold: 2)
        gate.observe(position: 50, paused: false)
        gate.observe(position: 0, paused: false)
        gate.observe(position: 1, paused: false)
        #expect(!gate.isOpen)
    }

    /// 3 倍速时每秒前进 3 秒，仍算在看。
    @Test func fastPlaybackCounts() {
        var gate = WatchGate()
        play(&gate, count: 11, step: 3)
        #expect(gate.isOpen)
    }

    @Test func resetCloses() {
        var gate = WatchGate()
        play(&gate, count: 31)
        #expect(gate.isOpen)
        gate.reset()
        #expect(!gate.isOpen)
        // reset 后第一次观测只建立基准，不会把跳变算进去。
        gate.observe(position: 100, paused: false)
        #expect(!gate.isOpen)
    }
}
