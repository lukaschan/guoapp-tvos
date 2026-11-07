import Foundation

/// 一部剧的观看状态：给「继续观看」卡片、「我的追剧」海报生成文案与整部剧进度。
/// totalEpisodes ≤ 0 表示总集数未知（目录接口没给），此时不显示「共 M 集」、也不判定看完。
struct WatchStatus: Equatable, Sendable {
    /// 视为看完的单集进度阈值。
    static let finishedThreshold = 0.99

    let latestEpisode: Int?
    /// 最近一集的播放进度（0…1）。
    let fraction: Double
    /// 总集数；nil 表示未知。
    let totalEpisodes: Int?

    init(latestEpisode: Int?, position: Double, duration: Double, totalEpisodes: Int) {
        self.latestEpisode = latestEpisode
        fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
        self.totalEpisodes = totalEpisodes > 0 ? totalEpisodes : nil
    }

    /// 看到了最后一集且最后一集基本播完。
    var isFinished: Bool {
        guard let latestEpisode, let totalEpisodes else { return false }
        return latestEpisode == totalEpisodes && fraction >= Self.finishedThreshold
    }

    /// 整部剧进度：(N − 1 + 本集进度) / M；看完为 1，未开始或总集数未知为 0。
    var seriesFraction: Double {
        if isFinished { return 1 }
        guard let latestEpisode, let totalEpisodes else { return 0 }
        return min(max((Double(latestEpisode - 1) + fraction) / Double(totalEpisodes), 0), 1)
    }

    /// 「继续观看」卡片：看到第 N 集 / 共 M 集；看完为「已看完」；未开始为空。
    var cardCaption: String {
        if isFinished { return "已看完" }
        guard let latestEpisode else { return "" }
        guard let totalEpisodes else { return "看到第 \(latestEpisode) 集" }
        return "看到第 \(latestEpisode) 集 / 共 \(totalEpisodes) 集"
    }

    /// 「我的追剧」海报：看到第 N 集 · 共 M 集 / 未开始 · 共 M 集 / 已看完 · 共 M 集；总集数未知时去掉后缀。
    var posterCaption: String {
        let state: String
        if isFinished {
            state = "已看完"
        } else if let latestEpisode {
            state = "看到第 \(latestEpisode) 集"
        } else {
            state = "未开始"
        }
        guard let totalEpisodes else { return state }
        return "\(state) · 共 \(totalEpisodes) 集"
    }
}
