import Foundation

/// 选集分段：把分集按每段 30 集切成标签（1–30、31–60、61–80…），与 redfruit 一致。
struct EpisodeRanges: Equatable, Sendable {
    static let defaultPageSize = 30

    /// 每段的集数范围（集数从 1 开始）。
    let ranges: [ClosedRange<Int>]

    init(episodeCount: Int, pageSize: Int = EpisodeRanges.defaultPageSize) {
        guard episodeCount > 0, pageSize > 0 else {
            ranges = []
            return
        }
        ranges = stride(from: 1, through: episodeCount, by: pageSize).map { start in
            start...min(start + pageSize - 1, episodeCount)
        }
    }

    /// 包含某集的分段下标；越界时夹到第一段或最后一段，没有分段时为 0。
    func clampedIndex(containing episode: Int) -> Int {
        if let index = ranges.firstIndex(where: { $0.contains(episode) }) { return index }
        guard let last = ranges.indices.last else { return 0 }
        return episode < 1 ? 0 : last
    }

    /// 分段标签："1–30"（短横为 en dash）；只有一集时为 "31"。
    static func label(for range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }
}

/// 选集格子的状态：比上次看到的那集靠前的算已看，等于它的是当前集，其余未看。
enum EpisodeCellState: Equatable, Sendable {
    case watched
    case current
    case unwatched

    init(episode: Int, currentEpisode: Int?) {
        guard let currentEpisode else {
            self = .unwatched
            return
        }
        if episode == currentEpisode {
            self = .current
        } else if episode < currentEpisode {
            self = .watched
        } else {
            self = .unwatched
        }
    }
}
