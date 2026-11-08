import Testing
@testable import GuoAppLogic

private actor Gauge {
    private(set) var current = 0
    private(set) var peak = 0
    private(set) var finished = 0
    private(set) var order: [Int] = []

    func enter(_ id: Int) {
        current += 1
        peak = max(peak, current)
        order.append(id)
    }

    func leave() {
        current -= 1
        finished += 1
    }
}

struct AsyncLimiterTests {
    @Test func neverExceedsLimit() async {
        let limiter = AsyncLimiter(limit: 4)
        let gauge = Gauge()
        await withTaskGroup(of: Void.self) { group in
            for id in 0..<10 {
                group.addTask {
                    await limiter.acquire()
                    await gauge.enter(id)
                    try? await Task.sleep(for: .milliseconds(30))
                    await gauge.leave()
                    await limiter.release()
                }
            }
        }
        #expect(await gauge.peak <= 4)
        #expect(await gauge.finished == 10)
    }

    /// 限 1 个时，等待的按到达顺序依次放行。
    @Test func fifoOrder() async {
        let limiter = AsyncLimiter(limit: 1)
        let gauge = Gauge()
        await limiter.acquire()
        var tasks: [Task<Void, Never>] = []
        for id in 1...3 {
            tasks.append(Task {
                await limiter.acquire()
                await gauge.enter(id)
                await gauge.leave()
                await limiter.release()
            })
            // 让每个任务按顺序排进等待队列。
            try? await Task.sleep(for: .milliseconds(20))
        }
        await limiter.release()
        for task in tasks { await task.value }
        #expect(await gauge.order == [1, 2, 3])
    }
}
