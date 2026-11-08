import Testing
@testable import GuoAppLogic

struct WatchStatusTests {
    @Test func watchingKnownTotal() {
        let status = WatchStatus(latestEpisode: 12, position: 30, duration: 120, totalEpisodes: 80)
        #expect(status.cardCaption == "看到第 12 集 / 共 80 集")
        #expect(status.posterCaption == "看到第 12 集 · 共 80 集")
        #expect(abs(status.seriesFraction - (11 + 0.25) / 80) < 1e-9)
        #expect(!status.isFinished)
    }

    @Test func finishedLastEpisode() {
        let status = WatchStatus(latestEpisode: 80, position: 119.5, duration: 120, totalEpisodes: 80)
        #expect(status.isFinished)
        #expect(status.cardCaption == "已看完")
        #expect(status.posterCaption == "已看完 · 共 80 集")
        #expect(status.seriesFraction == 1)
    }

    @Test func lastEpisodeNotDone() {
        let status = WatchStatus(latestEpisode: 80, position: 60, duration: 120, totalEpisodes: 80)
        #expect(!status.isFinished)
        #expect(status.cardCaption == "看到第 80 集 / 共 80 集")
    }

    @Test func unknownTotal() {
        let status = WatchStatus(latestEpisode: 5, position: 10, duration: 100, totalEpisodes: 0)
        #expect(status.cardCaption == "看到第 5 集")
        #expect(status.posterCaption == "看到第 5 集")
        #expect(status.seriesFraction == 0)
        #expect(!status.isFinished)
    }

    @Test func notStarted() {
        let known = WatchStatus(latestEpisode: nil, position: 0, duration: 0, totalEpisodes: 60)
        #expect(known.posterCaption == "未开始 · 共 60 集")
        #expect(known.cardCaption == "")
        #expect(known.seriesFraction == 0)
        let unknown = WatchStatus(latestEpisode: nil, position: 0, duration: 0, totalEpisodes: 0)
        #expect(unknown.posterCaption == "未开始")
    }

    @Test func zeroDurationIsFinite() {
        let status = WatchStatus(latestEpisode: 3, position: 50, duration: 0, totalEpisodes: 10)
        #expect(status.seriesFraction.isFinite)
        #expect(abs(status.seriesFraction - 0.2) < 1e-9)
    }
}

/// 红果榜单来自官网榜单页，那里每部剧只列出前几集的预告（episodeVids，通常 3 个），
/// 核心按它的个数填总集数，所以榜单上的「3集」不是真实总集数，只能当作未知。
struct RankingEpisodeCountTests {
    @Test func hongguoRankingCountIsUnknown() {
        #expect(EpisodeCount.fromRanking(reported: 3, source: "hongguo") == 0)
    }

    @Test func otherSourcesKeepTheirCount() {
        #expect(EpisodeCount.fromRanking(reported: 40, source: "huangdou") == 40)
    }

    @Test func unknownStaysUnknown() {
        #expect(EpisodeCount.fromRanking(reported: 0, source: "huangdou") == 0)
    }
}
