import Foundation
import Testing
@testable import GuoAppLogic

/// 剧场榜单的本地快照：启动时先显示上次的第 1 页（核心只在内存里缓存榜单，重开 App 就没了）。
struct RankingSnapshotTests {
    private struct Item: Codable, Sendable, Equatable {
        let id: String
    }

    @Test func roundTrips() throws {
        let saved = RankingSnapshot(board: "hongguo-hot", items: [Item(id: "a"), Item(id: "b")], savedAt: Date(timeIntervalSince1970: 1_000))
        let data = try JSONEncoder().encode(saved)
        let loaded = try JSONDecoder().decode(RankingSnapshot<Item>.self, from: data)
        #expect(loaded.board == "hongguo-hot")
        #expect(loaded.items == [Item(id: "a"), Item(id: "b")])
        #expect(loaded.savedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func staleAfterSevenDays() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        #expect(RankingSnapshot<Item>.isUsable(savedAt: now.addingTimeInterval(-6.9 * 86_400), now: now))
        #expect(!RankingSnapshot<Item>.isUsable(savedAt: now.addingTimeInterval(-7.1 * 86_400), now: now))
    }
}
