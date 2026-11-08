import Foundation

/// 一个榜单第 1 页的本地快照：核心只在内存里缓存榜单，重开 App 后要联网；
/// 剧场启动时先显示上次存下的这一页，新的回来再换上。超过 7 天的不再用。
struct RankingSnapshot<Item: Codable & Sendable>: Codable, Sendable {
    static var maximumAge: TimeInterval { 7 * 86_400 }

    let board: String
    let items: [Item]
    let savedAt: Date

    static func isUsable(savedAt: Date, now: Date) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age < maximumAge
    }
}
