import Foundation
import Testing
@testable import GuoAppLogic

/// 「我的」→ 看过的剧 → 观看记录：每部剧一项（最近看的那一集），最近看的在前；
/// 部数与卡片上「看过的剧」的数字一致（有进度的不同剧）。
struct WatchHistoryTests {
    private struct Entry {
        let id: String
        let position: Double
        let at: Double
    }

    private func dramas(_ entries: [Entry]) -> [Entry] {
        WatchHistory.dramas(entries, dramaID: \.id, position: \.position, updatedAt: { Date(timeIntervalSince1970: $0.at) })
    }

    @Test func newestEntryPerDramaNewestFirst() {
        let result = dramas([
            Entry(id: "a", position: 30, at: 1),
            Entry(id: "b", position: 10, at: 3),
            Entry(id: "a", position: 50, at: 5),
        ])
        #expect(result.map(\.id) == ["a", "b"])
        #expect(result.first?.position == 50)
    }

    /// 只打开过、没播出进度的剧不算看过（与卡片的数字一致）。
    @Test func countMatchesTheWatchedCard() {
        let entries = [
            Entry(id: "a", position: 30, at: 1),
            Entry(id: "b", position: 0, at: 2),
            Entry(id: "c", position: 12, at: 3),
        ]
        let stats = ViewingStats.make(follows: 0, entries: entries.map { (dramaID: $0.id, position: $0.position, duration: 100) })
        #expect(dramas(entries).count == stats.dramasWatched)
        #expect(dramas(entries).map(\.id) == ["c", "a"])
    }

    /// 看过的剧最近一次只是打开了新的一集（还没进度）：仍然列出，显示最近那一集。
    @Test func watchedDramaShowsItsLatestEpisodeEvenWithoutProgress() {
        let result = dramas([
            Entry(id: "a", position: 40, at: 1),
            Entry(id: "a", position: 0, at: 2),
        ])
        #expect(result.count == 1)
        #expect(result.first?.at == 2)
    }
}
