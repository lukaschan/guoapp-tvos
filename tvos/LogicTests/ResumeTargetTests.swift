import Testing
@testable import GuoAppLogic

struct ResumeTargetTests {
    @Test func resumeFound() {
        #expect(ResumeTarget.resolve(episodeNumbers: [1, 2, 3], latestEpisode: 2, position: 42)
            == ResumeTarget(index: 1, position: 42))
    }

    @Test func resumeNil() {
        #expect(ResumeTarget.resolve(episodeNumbers: [1, 2], latestEpisode: nil, position: 0)
            == ResumeTarget(index: 0, position: 0))
    }

    @Test func resumeFallsBackWhenEpisodeMissing() {
        #expect(ResumeTarget.resolve(episodeNumbers: [1, 2, 3], latestEpisode: 9, position: 30)
            == ResumeTarget(index: 0, position: 0))
    }

    @Test func noEpisodes() {
        #expect(ResumeTarget.resolve(episodeNumbers: [], latestEpisode: 1, position: 0) == nil)
    }

    @Test func launcherReentrancy() {
        #expect(LaunchGate.canStart(loadingDramaID: nil, presenting: false))
        #expect(!LaunchGate.canStart(loadingDramaID: "x", presenting: false))
        #expect(!LaunchGate.canStart(loadingDramaID: nil, presenting: true))
    }

    /// 看完了的剧（重新观看）：从第 1 集开头。
    @Test func finishedRestartsFromFirstEpisode() {
        #expect(ResumeTarget.playbackStart(episodeNumbers: [1, 2, 3], latestEpisode: 3, position: 99.5, duration: 100)
            == ResumeTarget(index: 0, position: 0))
    }

    @Test func midwayResumes() {
        #expect(ResumeTarget.playbackStart(episodeNumbers: [1, 2, 3], latestEpisode: 2, position: 30, duration: 100)
            == ResumeTarget(index: 1, position: 30))
    }

    @Test func lastEpisodeMidwayStillResumes() {
        #expect(ResumeTarget.playbackStart(episodeNumbers: [1, 2, 3], latestEpisode: 3, position: 40, duration: 100)
            == ResumeTarget(index: 2, position: 40))
    }

    @Test func noHistoryStarts() {
        #expect(ResumeTarget.playbackStart(episodeNumbers: [1, 2, 3], latestEpisode: nil, position: 0, duration: 0)
            == ResumeTarget(index: 0, position: 0))
    }

    @Test func playbackStartWithoutEpisodes() {
        #expect(ResumeTarget.playbackStart(episodeNumbers: [], latestEpisode: 1, position: 10, duration: 100) == nil)
    }
}
