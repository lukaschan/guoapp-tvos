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
    /// - 看到了最后一集的结尾、且这部剧已完结（releaseStatus 为 finished / completed）：从第 1 集开头
    ///  （与详情页「重新观看」一致）；
    /// - 看到了最新一集的结尾、但还在连载或不知道是否完结：打开最后一集、从头播，不跳回第 1 集丢掉进度；
    /// - 其余同 resolve。
    static func playbackStart(
        episodeNumbers: [Int], latestEpisode: Int?, position: Double, duration: Double, releaseStatus: String = ""
    ) -> ResumeTarget? {
        guard !episodeNumbers.isEmpty else { return nil }
        let caughtUp = WatchStatus(
            latestEpisode: latestEpisode, position: position, duration: duration, totalEpisodes: episodeNumbers.count
        ).isFinished
        guard caughtUp else {
            return resolve(episodeNumbers: episodeNumbers, latestEpisode: latestEpisode, position: position)
        }
        if completedStatuses.contains(releaseStatus) { return ResumeTarget(index: 0, position: 0) }
        return ResumeTarget(index: episodeNumbers.count - 1, position: 0)
    }

    /// 核心标记完结的取值（与 Drama.releaseLabel 的「已完结」一致）。
    private static let completedStatuses: Set<String> = ["finished", "completed"]
}

/// 「播这部剧」的防重入：正在取详情或已经弹出播放页时，再按不重复发起。
enum LaunchGate {
    static func canStart(loadingDramaID: String?, presenting: Bool) -> Bool {
        loadingDramaID == nil && !presenting
    }
}
