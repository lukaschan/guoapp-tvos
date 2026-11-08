import Foundation

/// 「接下来」预览期间正在播的这部怎么办：预览只换 hero 的封面和介绍（不重新加载），
/// 这部原地暂停；离开这一行时原样回来——用户自己暂停的仍暂停，原本在播的接着播。
struct PreviewHold: Equatable, Sendable {
    private(set) var isActive = false
    private var resumeAfter = false

    init() {}

    /// 预览开始（或在海报间移动）：第一次时若正在播，返回 true 表示现在暂停、之后接着播。
    mutating func begin(playing: Bool) -> Bool {
        guard !isActive else { return false }
        isActive = true
        resumeAfter = playing
        return playing
    }

    /// 预览期间这部才出画面（之前还在加载）：返回 true 表示现在暂停、之后接着播。
    mutating func videoStarted() -> Bool {
        guard isActive, !resumeAfter else { return false }
        resumeAfter = true
        return true
    }

    /// 预览结束：返回 true 表示接着播。
    mutating func end() -> Bool {
        guard isActive else { return false }
        isActive = false
        defer { resumeAfter = false }
        return resumeAfter
    }

    /// 换了一部剧（新会话）：之前的暂停记录作废。
    mutating func reset() {
        isActive = false
        resumeAfter = false
    }
}
