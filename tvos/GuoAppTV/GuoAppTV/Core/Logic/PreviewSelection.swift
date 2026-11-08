import Foundation

/// 「接下来」的停留预览：焦点在某张海报上停满 1 秒，hero 先预览它；按下才算选定。
/// 焦点离开这一行时回到选定的那部。
struct PreviewSelection: Equatable, Sendable {
    static let dwell: Duration = .milliseconds(1000)

    var committedID: String
    var focusedID: String?
    var previewID: String?

    init(committedID: String, focusedID: String? = nil, previewID: String? = nil) {
        self.committedID = committedID
        self.focusedID = focusedID
        self.previewID = previewID
    }

    /// hero 现在该放哪部：在预览就放预览的，否则放选定的。
    var heroID: String { previewID ?? committedID }

    /// 焦点移到某张海报；nil 表示焦点离开了这一行，预览随之取消。
    mutating func focus(_ id: String?) {
        focusedID = id
        if id == nil { previewID = nil }
    }

    /// 停留计时到了：焦点还在这张、且它不是已选定的那部，才开始预览。
    mutating func dwellElapsed(for id: String) {
        guard focusedID == id, id != committedID else { return }
        previewID = id
    }

    mutating func commit(_ id: String) {
        committedID = id
        previewID = nil
    }
}
