import Testing
@testable import GuoAppLogic

/// 推荐页 hero 的暂停只看用户按了什么：按了暂停就一直停着——在「接下来」海报间移动、预览别的剧、
/// 离开这一行，都不会自己播起来；预览期间选定的那部藏在后面，总是停着。
struct HeroPauseIntentTests {
    @Test func startsPlaying() {
        let intent = HeroPauseIntent()
        #expect(!intent.mainPaused)
        #expect(!intent.previewPaused)
    }

    @Test func previewHidesTheSelectedDrama() {
        var intent = HeroPauseIntent()
        intent.beginPreview()
        #expect(intent.mainPaused)
        #expect(!intent.previewPaused)
        intent.endPreview()
        #expect(!intent.mainPaused)
    }

    /// 先暂停再到「接下来」：每张海报的预览都停在第一帧，离开这一行后选定的那部仍停着。
    @Test func pauseBeforePreviewSticksAcrossPosters() {
        var intent = HeroPauseIntent()
        let paused = intent.toggle(visiblePaused: false)
        #expect(paused)
        intent.beginPreview()
        #expect(intent.previewPaused)
        intent.beginPreview()
        #expect(intent.previewPaused)
        intent.endPreview()
        #expect(intent.mainPaused)
    }

    /// 在预览上按了暂停：换到下一张海报仍停着，离开这一行后选定的那部也停着。
    @Test func pauseDuringPreviewSticks() {
        var intent = HeroPauseIntent()
        intent.beginPreview()
        let paused = intent.toggle(visiblePaused: false)
        #expect(paused)
        #expect(intent.previewPaused)
        intent.endPreview()
        #expect(intent.mainPaused)
    }

    /// 暂停后在预览上按了继续：离开这一行时选定的那部也接着播。
    @Test func resumeDuringPreviewCarriesBack() {
        var intent = HeroPauseIntent()
        _ = intent.toggle(visiblePaused: false)
        intent.beginPreview()
        let paused = intent.toggle(visiblePaused: true)
        #expect(!paused)
        intent.endPreview()
        #expect(!intent.mainPaused)
    }

    /// 按键跟着画面走：看得见的那个停着就继续，不管之前记的是什么。
    @Test func toggleFollowsWhatIsOnScreen() {
        var intent = HeroPauseIntent()
        let paused = intent.toggle(visiblePaused: true)
        #expect(!paused)
        #expect(!intent.userPaused)
    }

    /// 选定一部剧（按下海报、播完换下一部、重新进入推荐页）就是要播它。
    @Test func choosingADramaPlaysIt() {
        var intent = HeroPauseIntent()
        _ = intent.toggle(visiblePaused: false)
        intent.beginPreview()
        intent.choose()
        #expect(!intent.isPreviewing)
        #expect(!intent.mainPaused)
        #expect(!intent.previewPaused)
    }
}
