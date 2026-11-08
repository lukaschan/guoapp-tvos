import Testing
@testable import GuoAppLogic

/// 「接下来」预览时只换 hero 的封面和介绍，正在播的这部原地暂停（不重新加载）；
/// 离开这一行时它原样回来：用户自己暂停的仍暂停，否则接着播。
struct PreviewHoldTests {
    @Test func playingDramaPausesAndResumes() {
        var hold = PreviewHold()
        let r1 = hold.begin(playing: true)
        #expect(r1)
        let r2 = hold.end()
        #expect(r2)
    }

    @Test func userPausedDramaStaysPaused() {
        var hold = PreviewHold()
        let r3 = hold.begin(playing: false)
        #expect(!r3)
        let r4 = hold.end()
        #expect(!r4)
    }

    /// 在海报间移动：预览一直在，不会重复暂停，也不会丢掉「之后要接着播」。
    @Test func movingBetweenPostersKeepsTheHold() {
        var hold = PreviewHold()
        let r5 = hold.begin(playing: true)
        #expect(r5)
        let r6 = hold.begin(playing: false)
        #expect(!r6)
        let r7 = hold.end()
        #expect(r7)
    }

    /// 预览开始时这部还在加载（还没出画面）：一出画面就暂停，离开后接着播。
    @Test func videoStartingDuringPreviewIsHeld() {
        var hold = PreviewHold()
        let r8 = hold.begin(playing: false)
        #expect(!r8)
        let r9 = hold.videoStarted()
        #expect(r9)
        let r10 = hold.end()
        #expect(r10)
    }

    @Test func videoStartingWithoutPreviewIsLeftAlone() {
        var hold = PreviewHold()
        let r11 = hold.videoStarted()
        #expect(!r11)
        let r12 = hold.end()
        #expect(!r12)
    }

    @Test func resetForgetsTheHold() {
        var hold = PreviewHold()
        _ = hold.begin(playing: true)
        hold.reset()
        let r13 = hold.end()
        #expect(!r13)
        #expect(!hold.isActive)
    }
}
