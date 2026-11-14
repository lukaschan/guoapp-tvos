import Foundation

/// 同时最多放行 limit 个；多出来的按到达顺序等待（核心读请求通道用：最多 4 个一起跑）。
actor AsyncLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// 有人在等就把名额直接交给最早的那个，否则空出一个名额。
    func release() {
        if waiters.isEmpty {
            running = max(running - 1, 0)
        } else {
            waiters.removeFirst().resume()
        }
    }
}
