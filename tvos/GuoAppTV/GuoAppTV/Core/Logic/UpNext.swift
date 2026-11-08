import Foundation

/// 推荐页「接下来」：当前这部之后的 limit 部（到底后从头接上），不含当前这部。
enum UpNext {
    static func window(count: Int, current: Int, limit: Int = 10) -> [Int] {
        guard count > 1, limit > 0 else { return [] }
        let length = min(limit, count - 1)
        return (1...length).map { (current + $0) % count }
    }
}
