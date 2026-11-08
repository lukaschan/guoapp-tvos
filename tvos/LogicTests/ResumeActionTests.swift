import Testing
@testable import GuoAppLogic

struct ResumeActionTests {
    @Test func finishedWithNext() {
        let action = ResumeAction.make(
            target: ResumeTarget(index: 2, position: 95), episodeNumbers: [1, 2, 3], isFinished: true, hasNextPart: true
        )
        #expect(action == .nextPart)
        #expect(action.title == "观看下一部")
    }

    @Test func finishedNoNext() {
        let action = ResumeAction.make(
            target: ResumeTarget(index: 2, position: 95), episodeNumbers: [1, 2, 3], isFinished: true, hasNextPart: false
        )
        #expect(action == .restart)
        #expect(action.title == "重新观看")
    }

    @Test func resumeMidway() {
        let action = ResumeAction.make(
            target: ResumeTarget(index: 2, position: 30), episodeNumbers: [1, 2, 3], isFinished: false, hasNextPart: true
        )
        #expect(action == .resume(episode: 3))
        #expect(action.title == "继续观看 第 3 集")
    }

    @Test func resumeAtEpisodeStart() {
        #expect(ResumeAction.make(
            target: ResumeTarget(index: 1, position: 0), episodeNumbers: [1, 2, 3], isFinished: false, hasNextPart: false
        ) == .resume(episode: 2))
    }

    @Test func freshStart() {
        let action = ResumeAction.make(target: nil, episodeNumbers: [1, 2, 3], isFinished: false, hasNextPart: false)
        #expect(action == .start)
        #expect(action.title == "立即观看")
        #expect(ResumeAction.make(
            target: ResumeTarget(index: 0, position: 0), episodeNumbers: [1, 2, 3], isFinished: false, hasNextPart: false
        ) == .start)
    }

    @Test func targetOutsideEpisodesStarts() {
        #expect(ResumeAction.make(
            target: ResumeTarget(index: 7, position: 30), episodeNumbers: [1, 2, 3], isFinished: false, hasNextPart: false
        ) == .start)
    }
}
