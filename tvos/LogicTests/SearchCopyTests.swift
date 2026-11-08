import Testing
@testable import GuoAppLogic

struct SearchCopyTests {
    @Test func foundHeadline() {
        #expect(SearchCopy.found(3) == "找到 3 部短剧")
    }

    @Test func notFoundQuotesQuery() {
        #expect(SearchCopy.notFound("霸总") == "没有找到「霸总」")
        #expect(SearchCopy.notFoundHint == "换个关键词试试，比如剧名里的几个字或「都市」「古装」")
    }

    @Test func popularIsFourteen() {
        #expect(SearchCopy.popularCount == 14)
        #expect(SearchCopy.popularTitle == "大家都在看")
    }
}
