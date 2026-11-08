import Testing
@testable import GuoAppLogic

/// 推荐页 hero 只放 10 秒预告：从看到的那一集开头播，播满 10 秒回到封面；全屏观看接着看。
struct HeroTeaserTests {
    @Test func startsAtTheWatchedEpisodeFromItsBeginning() {
        let start = HeroTeaser.start(episodeNumbers: [1, 2, 3], latestEpisode: 2, position: 50, duration: 100)
        #expect(start == ResumeTarget(index: 1, position: 0))
    }

    @Test func unwatchedStartsAtEpisodeOne() {
        let start = HeroTeaser.start(episodeNumbers: [1, 2, 3], latestEpisode: nil, position: 0, duration: 0)
        #expect(start == ResumeTarget(index: 0, position: 0))
        #expect(HeroTeaser.start(episodeNumbers: [], latestEpisode: nil, position: 0, duration: 0) == nil)
    }

    /// 按实际播放的位置算（暂停时位置不动，也就不计时）；这一集先播完也算播完。
    @Test func finishesAfterTenSecondsOfPlay() {
        #expect(!HeroTeaser.isFinished(position: 9.9, ended: false))
        #expect(HeroTeaser.isFinished(position: 10, ended: false))
        #expect(HeroTeaser.isFinished(position: 3, ended: true))
    }

    @Test func fractionFillsOverTheTeaser() {
        #expect(HeroTeaser.fraction(position: 5) == 0.5)
        #expect(HeroTeaser.fraction(position: 12) == 1)
        #expect(HeroTeaser.fraction(position: -1) == 0)
    }

    @Test func fullScreenResumesSavedProgress() {
        let start = HeroTeaser.fullScreenStart(saved: ResumeTarget(index: 1, position: 80), teaserIndex: 1, teaserPosition: 6)
        #expect(start == ResumeTarget(index: 1, position: 80))
    }

    @Test func fullScreenContinuesTheTeaserForNewDramas() {
        let start = HeroTeaser.fullScreenStart(saved: nil, teaserIndex: 0, teaserPosition: 7.2)
        #expect(start == ResumeTarget(index: 0, position: 7.2))
    }

    /// 预读上限要装得下整段预告：实测最高码率约 1.1 Mbps。
    @Test func readAheadCoversTheTeaser() {
        let seconds = Double(HeroTeaser.readAheadBytes) * 8 / 1_100_000
        #expect(seconds >= HeroTeaser.length)
    }
}

struct DurationSecondsTests {
    @Test func convertsToTimeInterval() {
        #expect(Duration.milliseconds(700).timeInterval == 0.7)
        #expect(Duration.seconds(2).timeInterval == 2)
    }
}
