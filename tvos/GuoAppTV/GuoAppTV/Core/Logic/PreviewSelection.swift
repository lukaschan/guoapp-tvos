import Foundation

/// 「接下来」的停留预览：焦点在某张海报上停满 1 秒，hero 先预览它；按下才算选定。
/// 焦点离开这一行时回到选定的那部。按下切换后 1.5 秒内不自动预览：这一行随之刷新，
/// 焦点被挤到旁边那张时，不会停 1 秒就自己换成它。
struct PreviewSelection: Equatable, Sendable {
    static let dwell: Duration = .milliseconds(1000)
    static let quietAfterCommit: TimeInterval = 1.5

    var committedID: String
    var focusedID: String?
    var previewID: String?
    /// 这个时间之前到点的停留不预览（按下切换时设定）。
    private(set) var quietUntil: Date?

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

    /// 停留计时到了：焦点还在这张、它不是已选定的那部、且不在按下切换后的静默期里，才开始预览。
    mutating func dwellElapsed(for id: String, at now: Date = Date()) {
        guard willPreview(id, at: now) else { return }
        previewID = id
    }

    /// 到 now 这个时间点停留计时到了的话，会不会预览这张（提前在后台加载预告前先问一下）。
    func willPreview(_ id: String, at now: Date = Date()) -> Bool {
        guard focusedID == id, id != committedID else { return false }
        if let quietUntil, now < quietUntil { return false }
        return true
    }

    mutating func commit(_ id: String, at now: Date = Date()) {
        committedID = id
        previewID = nil
        quietUntil = now.addingTimeInterval(Self.quietAfterCommit)
    }
}
