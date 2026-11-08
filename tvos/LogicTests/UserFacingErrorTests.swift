import Foundation
import Testing
@testable import GuoAppLogic

struct UserFacingErrorTests {
    @Test func networkGoErrors() {
        #expect(UserFacingError.message(for: "Get \"https://x\": dial tcp: lookup x: no such host") == UserFacingError.network)
        #expect(UserFacingError.message(for: "context deadline exceeded (Client.Timeout exceeded while awaiting headers)")
            == UserFacingError.network)
        #expect(UserFacingError.message(for: "read tcp 10.0.0.2:5000->1.2.3.4:443: read: connection reset by peer")
            == UserFacingError.network)
        #expect(UserFacingError.network == "网络连接失败，请检查网络后重试")
    }

    @Test func chineseCoreMessageKept() {
        #expect(UserFacingError.message(for: "该剧暂时没有可播放的分集") == "该剧暂时没有可播放的分集")
    }

    @Test func technicalEnglishBecomesGeneric() {
        #expect(UserFacingError.message(for: "json: cannot unmarshal number into Go value") == UserFacingError.generic)
        #expect(UserFacingError.generic == "加载失败，请稍后重试")
    }

    @Test func emptyBecomesGeneric() {
        #expect(UserFacingError.message(for: "") == UserFacingError.generic)
        #expect(UserFacingError.message(for: "   ") == UserFacingError.generic)
    }

    @Test func urlErrorIsNetwork() {
        #expect(UserFacingError.message(for: URLError(.notConnectedToInternet)) == UserFacingError.network)
    }
}
