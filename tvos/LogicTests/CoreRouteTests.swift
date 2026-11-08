import Testing
@testable import GuoAppLogic

struct CoreRouteTests {
    /// 核心里较新的播放请求会取消进行中的那个（nativeBeginPlayback）：播放类请求必须继续一个一个来。
    @Test func playbackActionsStaySerial() {
        for action in ["initialize", "resolve", "fallback", "release", "cancelPlayback"] {
            #expect(CoreRoute.lane(for: action) == .playback, "\(action)")
        }
        for action in ["cover", "catalog", "detail", "danmaku", "followCheck", "metadata", "rankings", "recommendations"] {
            #expect(CoreRoute.lane(for: action) == .read, "\(action)")
        }
    }

    /// 被更新的同类请求取消时核心回 context canceled：当作取消，不当作出错显示。
    @Test func cancelledReplyIsCancellation() {
        #expect(CoreRoute.isCancellation(message: "context canceled"))
        #expect(!CoreRoute.isCancellation(message: "该剧暂时没有可播放的分集"))
    }
}
