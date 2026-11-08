import Foundation

/// 推荐页 hero 的暂停意图，选定的那部和「接下来」的预览共用一个：
/// - 用户按了暂停就一直停着：在海报间移动、预览别的剧（停在第一帧、不出声）、离开这一行回到选定的那部，
///   都不会自己播起来，直到用户再按继续（播放键 / 继续按钮）；
/// - 预览期间选定的那部藏在后面，总是停着；预览结束时按用户的意图决定它接着播还是停着；
/// - 选定一部剧（按下海报、播完换下一部、重新进入推荐页）就是要播它：意图回到播放。
struct HeroPauseIntent: Equatable, Sendable {
    /// 用户最后一次按的是暂停。
    private(set) var userPaused = false
    private(set) var isPreviewing = false

    init() {}

    /// 选定的那部该停着吗（预览时藏在后面，也停着）。
    var mainPaused: Bool { isPreviewing || userPaused }
    /// 预览那部该停着吗（是的话起播时就停在第一帧）。
    var previewPaused: Bool { userPaused }

    /// 用户按了暂停 / 继续。visiblePaused 是看得见的那个现在是否停着（按键跟着画面走）；返回按完后它该不该停着。
    mutating func toggle(visiblePaused: Bool) -> Bool {
        userPaused = !visiblePaused
        return userPaused
    }

    /// 焦点停在「接下来」某张海报上（在海报间移动时重复调用也一样）。
    mutating func beginPreview() {
        isPreviewing = true
    }

    /// 焦点离开「接下来」。
    mutating func endPreview() {
        isPreviewing = false
    }

    /// 选定了一部剧：从播放开始。
    mutating func choose() {
        userPaused = false
        isPreviewing = false
    }
}
