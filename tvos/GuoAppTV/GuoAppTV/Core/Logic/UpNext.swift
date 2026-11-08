import Foundation

/// 推荐页「接下来」：当前这部之后的 limit 部（到底后从头接上），不含当前这部。
enum UpNext {
    static let defaultLimit = 10

    static func window(count: Int, current: Int, limit: Int = UpNext.defaultLimit) -> [Int] {
        guard count > 1, limit > 0 else { return [] }
        let length = min(limit, count - 1)
        return (1...length).map { (current + $0) % count }
    }
}

/// 「接下来」一行有焦点时冻结内容：hero 变了（预览、播完换下一部）这一行也不跟着跳，
/// 焦点不会被挤走；只有按下切换时主动刷新成新 hero 之后的那一组（refresh），
/// 自动预览由 PreviewSelection 的静默期挡住。焦点离开这一行再按当前这部刷新。
struct UpNextFreeze: Equatable, Sendable {
    private(set) var frozenIDs: [String]?

    init() {}

    mutating func rowFocusChanged(isFocused: Bool, currentIDs: [String]) {
        if !isFocused {
            frozenIDs = nil
        } else if frozenIDs == nil {
            frozenIDs = currentIDs
        }
    }

    func visibleIDs(current: [String]) -> [String] {
        frozenIDs ?? current
    }

    /// 按下切换后：行有焦点时换成新 hero 之后的那一组（像以前一样刷新），之后照旧保持到焦点离开。
    mutating func refresh(currentIDs: [String]) {
        if frozenIDs != nil { frozenIDs = currentIDs }
    }
}
