import Testing
@testable import GuoAppLogic

struct LiveSearchTests {
    @Test func trimsSurroundingWhitespace() {
        #expect(LiveSearch.query(from: "  霸总 ") == "霸总")
        #expect(LiveSearch.query(from: "霸总 第二部") == "霸总 第二部")
    }

    @Test func emptyOrBlankDoesNotSearch() {
        #expect(LiveSearch.query(from: "") == nil)
        #expect(LiveSearch.query(from: "   ") == nil)
    }

    @Test func searchesAfterTypingPauses() {
        #expect(LiveSearch.debounce == .milliseconds(600))
    }
}
