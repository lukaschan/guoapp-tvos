import CoreGraphics
import Foundation

/// 推荐页 hero 的版式（1920×1080 画布）：竖屏视频贴右边整高，横屏视频右侧居中偏上；
/// 左侧信息栏宽度随之变化。
enum HeroLayout {
    static let verticalPanel = CGRect(x: 1192, y: 0, width: 608, height: 1080)
    static let landscapePanel = CGRect(x: 860, y: 150, width: 1060, height: 596)

    /// 尺寸未知（还没出画面）时按竖屏排，短剧大多是竖屏。
    static func panel(videoSize: CGSize?) -> (frame: CGRect, vertical: Bool) {
        guard let videoSize, videoSize.width > videoSize.height else {
            return (verticalPanel, true)
        }
        return (landscapePanel, false)
    }

    static func infoWidth(vertical: Bool) -> CGFloat {
        vertical ? 1040 : 760
    }
}

/// hero 进度行的文字。
enum HeroStatus {
    /// 预告的状态行：加载中 / 已暂停 / 正在播放第几集 / 播完了。
    static func teaserLine(episode: Int?, paused: Bool, finished: Bool) -> String {
        if finished { return "预告已播完 · 按全屏观看接着看" }
        guard let episode else { return "正在加载…" }
        return paused ? "已暂停 · 按播放键继续" : playing(episode: episode)
    }

    static func playing(episode: Int) -> String {
        "正在播放 第 \(episode) 集"
    }
}
