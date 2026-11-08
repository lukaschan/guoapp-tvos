import Foundation

/// 「我的」顶部的观看统计，只用本地存下的观看记录（最多最近 500 集）：
/// 在追 = 追剧数；看过的剧 = 有进度的不同剧；看完的集 = 看到 90 % 以上的集；累计观看 = 各集看到的位置加起来（小时，一位小数）。
struct ViewingStats: Equatable, Sendable {
    let following: Int
    let dramasWatched: Int
    let episodesFinished: Int
    let hoursWatched: Double

    static let finishedFraction = 0.9

    static func make(follows: Int, entries: [(dramaID: String, position: Double, duration: Double)]) -> ViewingStats {
        let watched = Set(entries.filter { $0.position > 0 }.map(\.dramaID))
        let finished = entries.filter { $0.duration > 0 && $0.position / $0.duration >= finishedFraction }.count
        let seconds = entries.reduce(0) { $0 + max($1.position, 0) }
        let hours = (seconds / 3600 * 10).rounded() / 10
        return ViewingStats(following: follows, dramasWatched: watched.count, episodesFinished: finished, hoursWatched: hours)
    }
}

/// 存储大小的文字，与系统设置一样按 1000 进位：820 KB、412 MB、1.2 GB。
enum StorageSize {
    static func label(bytes: Int64) -> String {
        let value = Double(max(bytes, 0))
        if value >= 1_000_000_000 { return String(format: "%.1f GB", value / 1_000_000_000) }
        if value >= 1_000_000 { return "\(Int((value / 1_000_000).rounded())) MB" }
        if value >= 1_000 { return "\(Int((value / 1_000).rounded())) KB" }
        return "\(Int(value)) B"
    }
}
