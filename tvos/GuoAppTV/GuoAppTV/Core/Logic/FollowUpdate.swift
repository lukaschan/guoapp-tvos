import Foundation

/// 追剧更新（核心的 followCheck）：每部追的剧记下「已知集数」（用户已经知道的）与「最近一次检查的集数」，
/// 后者更多时显示「更新至 N 集」；用户自己打开或播放这部剧后把已知集数追平（角标消失）。
enum FollowUpdate {
    /// 同一部剧两次自动检查之间至少隔 6 小时。
    static let recheckInterval: TimeInterval = 6 * 3600

    struct Counts: Equatable, Sendable {
        let known: Int
        let latest: Int
    }

    static func hasUpdate(known: Int?, latest: Int?) -> Bool {
        guard let known, let latest, known > 0 else { return false }
        return latest > known
    }

    /// 检查之后：已知集数未知（第四阶段前追的剧、或榜单里集数未知的剧）时以这次检查为基准，不算更新。
    static func afterCheck(known: Int?, latest: Int) -> Counts {
        guard let known, known > 0 else { return Counts(known: latest, latest: latest) }
        return Counts(known: known, latest: latest)
    }

    /// 该不该检查这一部：手动检查总是检查；自动检查跳过看完的剧和 6 小时内查过的。
    static func shouldCheck(checkedAt: Date?, now: Date, finished: Bool, force: Bool) -> Bool {
        if force { return true }
        guard !finished else { return false }
        guard let checkedAt else { return true }
        return now.timeIntervalSince(checkedAt) >= recheckInterval
    }

    static func badge(latest: Int) -> String {
        "更新至 \(latest) 集"
    }

    static func summary(updatedCount: Int) -> String {
        "\(updatedCount) 部有更新"
    }
}
