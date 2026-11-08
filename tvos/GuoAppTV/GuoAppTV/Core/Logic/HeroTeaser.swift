import Foundation

/// 推荐页 hero 只是预告：每部剧放 10 秒，想看就按全屏观看（owner 2026-11-08：hero 上看不到 5 秒）。
/// - 从看到的那一集开头播（没看过的从第 1 集），起点固定，后台能提前加载；
/// - 按实际播放的位置计时（暂停时位置不动，也就不计时），播满或这一集先播完就回到封面；
/// - 不记观看进度、不接着播下一集；全屏观看：看过的回到上次看到的位置，没看过的从预告播到的地方接着播。
enum HeroTeaser {
    static let length: Double = 10
    /// hero 播放器最多预读这么多（约 15–30 秒视频，实测码率 0.5–1.1 Mbps）：不再整集下载。
    static let readAheadBytes = 2 << 20
    /// 焦点在「接下来」某张海报上停这么久，就在后台（不可见、停着）开始加载它的预告；停满 1 秒才显示。
    static let warmDelay: Duration = .milliseconds(300)

    static func start(
        episodeNumbers: [Int], latestEpisode: Int?, position: Double, duration: Double, releaseStatus: String = ""
    ) -> ResumeTarget? {
        ResumeTarget.playbackStart(
            episodeNumbers: episodeNumbers, latestEpisode: latestEpisode,
            position: position, duration: duration, releaseStatus: releaseStatus
        ).map { ResumeTarget(index: $0.index, position: 0) }
    }

    static func isFinished(position: Double, ended: Bool) -> Bool {
        ended || position >= length
    }

    /// 预告已播的比例（进度条）。
    static func fraction(position: Double) -> Double {
        min(max(position / length, 0), 1)
    }

    /// saved：看过这部剧时的续播目标（ResumeTarget.playbackStart），没看过为 nil。
    static func fullScreenStart(saved: ResumeTarget?, teaserIndex: Int, teaserPosition: Double) -> ResumeTarget {
        saved ?? ResumeTarget(index: teaserIndex, position: max(teaserPosition, 0))
    }
}

extension Duration {
    /// 换成秒数（Date 计算用）。
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
