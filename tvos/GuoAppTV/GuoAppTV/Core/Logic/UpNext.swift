import Foundation

/// 推荐页「接下来」：当前这部之后的 limit 部（到底后从头接上），不含当前这部。
enum UpNext {
    static func window(count: Int, current: Int, limit: Int = 10) -> [Int] {
        guard count > 1, limit > 0 else { return [] }
        let length = min(limit, count - 1)
        return (1...length).map { (current + $0) % count }
    }
}

/// 「接下来」一行有焦点时冻结内容：按下切换后，推荐流的「接下来」会跟着新的 hero 变，
/// 被按下的海报若从行里消失，焦点会被挤到旁边的海报上、1 秒后自己开始预览另一部。
/// 所以行有焦点期间保持进入时的那一组，焦点离开这一行再按当前这部刷新。
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
}
