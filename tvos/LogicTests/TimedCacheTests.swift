import Foundation
import os
import Testing
@testable import GuoAppLogic

/// 可手动拨动的时钟。
private final class ManualClock: Sendable {
    private let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_000))
    var now: Date { current.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

private actor Counter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private struct Boom: Error {}

struct TimedCacheTests {
    @Test func reusesFreshValue() async throws {
        let counter = Counter()
        let cache = TimedCache<Int>(maxAge: 180)
        let first = try await cache.value(for: "a") { await counter.increment(); return 1 }
        let second = try await cache.value(for: "a") { await counter.increment(); return 2 }
        #expect(first == 1 && second == 1)
        #expect(await counter.count == 1)
    }

    @Test func refetchesAfterMaxAge() async throws {
        let clock = ManualClock()
        let counter = Counter()
        let cache = TimedCache<Int>(maxAge: 180, now: { clock.now })
        _ = try await cache.value(for: "a") { await counter.increment(); return 1 }
        clock.advance(181)
        #expect(await cache.cachedValue(for: "a") == nil)
        let refreshed = try await cache.value(for: "a") { await counter.increment(); return 2 }
        #expect(refreshed == 2)
        #expect(await counter.count == 2)
    }

    @Test func sharesInFlight() async throws {
        let counter = Counter()
        let cache = TimedCache<Int>(maxAge: 180)
        let slowFetch: @Sendable () async throws -> Int = {
            await counter.increment()
            try await Task.sleep(for: .milliseconds(80))
            return 7
        }
        async let first = cache.value(for: "a", fetch: slowFetch)
        async let second = cache.value(for: "a", fetch: slowFetch)
        let values = try await (first, second)
        #expect(values == (7, 7))
        #expect(await counter.count == 1)
    }

    @Test func failureNotCached() async throws {
        let counter = Counter()
        let cache = TimedCache<Int>(maxAge: 180)
        await #expect(throws: Boom.self) {
            try await cache.value(for: "a") { await counter.increment(); throw Boom() }
        }
        let value = try await cache.value(for: "a") { await counter.increment(); return 3 }
        #expect(value == 3)
        #expect(await counter.count == 2)
    }

    /// 分集列表不小：最多留 maxEntries 部，超出时丢掉最早存的。
    @Test func evictsOldestBeyondLimit() async throws {
        let clock = ManualClock()
        let cache = TimedCache<Int>(maxAge: 180, maxEntries: 2, now: { clock.now })
        _ = try await cache.value(for: "a") { 1 }
        clock.advance(1)
        _ = try await cache.value(for: "b") { 2 }
        clock.advance(1)
        _ = try await cache.value(for: "c") { 3 }
        #expect(await cache.cachedValue(for: "a") == nil)
        #expect(await cache.cachedValue(for: "b") == 2)
        #expect(await cache.cachedValue(for: "c") == 3)
    }
}
