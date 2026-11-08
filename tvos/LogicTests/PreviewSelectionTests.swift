import Foundation
import Testing
@testable import GuoAppLogic

struct PreviewSelectionTests {
    @Test func dwellPreviews() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        #expect(selection.heroID == "hero")
        selection.dwellElapsed(for: "a")
        #expect(selection.previewID == "a")
        #expect(selection.heroID == "a")
    }

    @Test func staleDwellIgnored() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        selection.focus("b")
        selection.dwellElapsed(for: "a")
        #expect(selection.previewID == nil)
        #expect(selection.heroID == "hero")
    }

    @Test func leavingRowRestores() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        selection.dwellElapsed(for: "a")
        selection.focus(nil)
        #expect(selection.previewID == nil)
        #expect(selection.heroID == "hero")
    }

    @Test func commitClearsPreview() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        selection.dwellElapsed(for: "a")
        selection.commit("a")
        #expect(selection.committedID == "a")
        #expect(selection.previewID == nil)
        #expect(selection.heroID == "a")
    }

    @Test func committedNotPreviewed() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("hero")
        selection.dwellElapsed(for: "hero")
        #expect(selection.previewID == nil)
    }

    @Test func moveToAnotherPosterKeepsPreviewUntilItsDwell() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        selection.dwellElapsed(for: "a")
        selection.focus("b")
        #expect(selection.heroID == "a")
        selection.dwellElapsed(for: "b")
        #expect(selection.heroID == "b")
    }

    @Test func dwellIsOneSecond() {
        #expect(PreviewSelection.dwell == .milliseconds(1000))
    }

    /// 按下切换后的 1.5 秒内不自动预览：焦点被挤到旁边那张时，不会 1 秒后自己换成它。
    @Test func noPreviewRightAfterCommit() {
        let start = Date(timeIntervalSince1970: 1_000)
        var selection = PreviewSelection(committedID: "hero")
        selection.commit("x", at: start)
        selection.focus("y")
        selection.dwellElapsed(for: "y", at: start.addingTimeInterval(1.0))
        #expect(selection.previewID == nil)
        #expect(selection.heroID == "x")
    }

    @Test func previewResumesAfterQuietPeriod() {
        let start = Date(timeIntervalSince1970: 1_000)
        var selection = PreviewSelection(committedID: "hero")
        selection.commit("x", at: start)
        selection.focus("y")
        selection.dwellElapsed(for: "y", at: start.addingTimeInterval(PreviewSelection.quietAfterCommit + 0.1))
        #expect(selection.previewID == "y")
        #expect(PreviewSelection.quietAfterCommit == 1.5)
    }
}

/// 焦点停 0.3 秒就在后台加载预览：只给到点时真的会预览的那张加载。
struct PreviewWarmupTests {
    @Test func focusedPosterWillPreview() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("a")
        #expect(selection.willPreview("a"))
        #expect(!selection.willPreview("b"))
    }

    @Test func committedDramaNeverPreviews() {
        var selection = PreviewSelection(committedID: "hero")
        selection.focus("hero")
        #expect(!selection.willPreview("hero"))
    }

    @Test func quietPeriodAfterCommitDoesNotWarm() {
        let now = Date()
        var selection = PreviewSelection(committedID: "hero")
        selection.commit("b", at: now)
        selection.focus("c")
        #expect(!selection.willPreview("c", at: now.addingTimeInterval(1)))
        #expect(selection.willPreview("c", at: now.addingTimeInterval(2)))
    }
}
