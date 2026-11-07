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
}
