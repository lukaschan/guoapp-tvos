import Foundation

/// 续播目标：在分集列表里找到上次看到的那集和位置；找不到（分集重排、被下架）就从第 1 集开头播。
struct ResumeTarget: Equatable, Sendable {
    let index: Int
    let position: Double

    /// episodeNumbers：详情里分集的集数，按列表顺序；没有分集时返回 nil。
    static func resolve(episodeNumbers: [Int], latestEpisode: Int?, position: Double) -> ResumeTarget? {
        guard !episodeNumbers.isEmpty else { return nil }
        guard let latestEpisode, let index = episodeNumbers.firstIndex(of: latestEpisode) else {
            return ResumeTarget(index: 0, position: 0)
        }
        return ResumeTarget(index: index, position: max(position, 0))
    }

    /// 直接播放（海报上按播放键、继续观看卡片、推荐页 hero）从哪里开始：
    /// 整部剧已看完（最后一集看到 99 %）时从第 1 集开头（与详情页「重新观看」一致），否则同 resolve。
    static func playbackStart(episodeNumbers: [Int], latestEpisode: Int?, position: Double, duration: Double) -> ResumeTarget? {
        guard !episodeNumbers.isEmpty else { return nil }
        let finished = WatchStatus(
            latestEpisode: latestEpisode, position: position, duration: duration, totalEpisodes: episodeNumbers.count
        ).isFinished
        if finished { return ResumeTarget(index: 0, position: 0) }
        return resolve(episodeNumbers: episodeNumbers, latestEpisode: latestEpisode, position: position)
    }
}

/// 「播这部剧」的防重入：正在取详情或已经弹出播放页时，再按不重复发起。
enum LaunchGate {
    static func canStart(loadingDramaID: String?, presenting: Bool) -> Bool {
        loadingDramaID == nil && !presenting
    }
}
