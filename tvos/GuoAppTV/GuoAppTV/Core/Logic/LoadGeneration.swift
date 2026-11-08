import Foundation

/// 每次加载领一个号，只有最新的号算数：请求并行后，换了榜单 / 分类时慢的那次可能晚回来，
/// 晚回来的结果不能盖掉现在这一次的。
struct LoadGeneration: Equatable, Sendable {
    private(set) var current = 0

    init() {}

    mutating func begin() -> Int {
        current += 1
        return current
    }

    func isCurrent(_ generation: Int) -> Bool {
        generation == current
    }
}
