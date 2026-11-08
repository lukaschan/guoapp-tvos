import Foundation
import Testing
@testable import GuoAppLogic

/// 追剧更新：每部追的剧记下「已知集数」与「最近一次检查的集数」，后者更多时显示「更新至 N 集」。
struct FollowUpdateTests {
    @Test func noBadgeWithoutBaseline() {
        #expect(!FollowUpdate.hasUpdate(known: nil, latest: 80))
        #expect(!FollowUpdate.hasUpdate(known: 0, latest: 80))
    }

    @Test func badgeWhenMoreEpisodes() {
        #expect(FollowUpdate.hasUpdate(known: 80, latest: 85))
        #expect(!FollowUpdate.hasUpdate(known: 80, latest: 80))
        #expect(!FollowUpdate.hasUpdate(known: 80, latest: nil))
    }

    /// 第四阶段之前就追的剧、或从榜单（集数未知）追的剧：第一次检查只记下基准，不显示更新。
    @Test func firstCheckSetsBaseline() {
        #expect(FollowUpdate.afterCheck(known: nil, latest: 85) == FollowUpdate.Counts(known: 85, latest: 85))
        #expect(FollowUpdate.afterCheck(known: 0, latest: 85) == FollowUpdate.Counts(known: 85, latest: 85))
        #expect(FollowUpdate.afterCheck(known: 80, latest: 85) == FollowUpdate.Counts(known: 80, latest: 85))
    }

    @Test func rechecksAfterSixHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!FollowUpdate.shouldCheck(checkedAt: now.addingTimeInterval(-5 * 3600), now: now, finished: false, force: false))
        #expect(FollowUpdate.shouldCheck(checkedAt: now.addingTimeInterval(-7 * 3600), now: now, finished: false, force: false))
        #expect(FollowUpdate.shouldCheck(checkedAt: nil, now: now, finished: false, force: false))
        // 看完的剧不再自动检查；手动「检查追剧更新」照样检查。
        #expect(!FollowUpdate.shouldCheck(checkedAt: nil, now: now, finished: true, force: false))
        #expect(FollowUpdate.shouldCheck(checkedAt: now, now: now, finished: true, force: true))
    }

    @Test func badgeText() {
        #expect(FollowUpdate.badge(latest: 85) == "更新至 85 集")
        #expect(FollowUpdate.summary(updatedCount: 3) == "3 部有更新")
    }

    private struct LegacyFollow: Codable {
        var knownEpisodes: Int?
        var latestEpisodes: Int?
        var checkedAt: Date?
        var followedAt: Date
    }

    /// 旧版存下的追剧（没有这三个字段）照样能读出来，字段为空。
    @Test func legacyFollowDecodes() throws {
        let json = #"{"followedAt": 700000000}"#
        let follow = try JSONDecoder().decode(LegacyFollow.self, from: Data(json.utf8))
        #expect(follow.knownEpisodes == nil && follow.latestEpisodes == nil && follow.checkedAt == nil)
    }
}
