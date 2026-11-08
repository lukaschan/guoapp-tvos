import Foundation

/// 带有效期的小缓存：新鲜（存入不到 maxAge 秒）的直接返回；同一个键并发请求共用一次获取；
/// 失败不缓存；最多留 maxEntries 项，超出时丢掉最早存入的（详情带整份分集列表，不能无限增长）。
actor TimedCache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    private let maxAge: TimeInterval
    private let maxEntries: Int
    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var inFlight: [String: Task<Value, any Error>] = [:]

    init(maxAge: TimeInterval, maxEntries: Int = 40, now: @escaping @Sendable () -> Date = { Date() }) {
        self.maxAge = maxAge
        self.maxEntries = max(maxEntries, 1)
        self.now = now
    }

    func cachedValue(for key: String) -> Value? {
        guard let entry = entries[key], now().timeIntervalSince(entry.storedAt) < maxAge else { return nil }
        return entry.value
    }

    func value(for key: String, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if let fresh = cachedValue(for: key) { return fresh }
        if let running = inFlight[key] { return try await running.value }
        let task = Task { try await fetch() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let value = try await task.value
        store(value, for: key)
        return value
    }

    private func store(_ value: Value, for key: String) {
        let time = now()
        entries = entries.filter { time.timeIntervalSince($0.value.storedAt) < maxAge }
        entries[key] = Entry(value: value, storedAt: time)
        while entries.count > maxEntries, let oldest = entries.min(by: { $0.value.storedAt < $1.value.storedAt }) {
            entries[oldest.key] = nil
        }
    }
}
