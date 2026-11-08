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

    static let canvas = CGSize(width: 1920, height: 1080)

    /// mpv 起播时定下渲染尺寸、之后不跟随图层尺寸变化（改了图层尺寸，画面会错位、露出黑块），
    /// 所以 hero 的播放器图层固定铺满画布，由 mpv 用边距把画面摆到这个视频该在的面板上。
    static func mpvMargins(videoSize: CGSize?) -> [String: String] {
        let frame = panel(videoSize: videoSize).frame
        func ratio(_ value: CGFloat, _ total: CGFloat) -> String { String(Double(value / total)) }
        return [
            "video-margin-ratio-left": ratio(frame.minX, canvas.width),
            "video-margin-ratio-right": ratio(canvas.width - frame.maxX, canvas.width),
            "video-margin-ratio-top": ratio(frame.minY, canvas.height),
            "video-margin-ratio-bottom": ratio(canvas.height - frame.maxY, canvas.height),
        ]
    }

    static func infoWidth(vertical: Bool) -> CGFloat {
        vertical ? 1040 : 760
    }
}

/// hero 进度行的文字。
enum HeroStatus {
    static func line(episode: Int?, remaining: Double?, isLastEpisode: Bool, paused: Bool, autoAdvance: Bool) -> String {
        guard let episode else { return "正在加载…" }
        if paused { return "已暂停 · 按播放键继续" }
        guard autoAdvance, let remaining, remaining.isFinite else { return playing(episode: episode) }
        let countdown = clock(remaining)
        return isLastEpisode ? "\(countdown) 后播放下一部" : "\(countdown) 后自动播放下一集"
    }

    static func playing(episode: Int) -> String {
        "正在播放 第 \(episode) 集"
    }

    /// 剩余秒数向上取整成 MM:SS（超过一小时分钟数照写，如 75:00）。
    private static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
