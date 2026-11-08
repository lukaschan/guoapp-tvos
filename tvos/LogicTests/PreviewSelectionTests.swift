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
}
