import Testing
@testable import GuoAppLogic

struct GatewayRevivalTests {
    @Test func readsTheCoreAnswer() {
        #expect(GatewayRevival(coreValue: "idle") == .idle)
        #expect(GatewayRevival(coreValue: "alive") == .alive)
        #expect(GatewayRevival(coreValue: "revived") == .revived)
        #expect(GatewayRevival(coreValue: "reset") == .reset)
    }

    /// 不认识的回答（核心没带这个补丁、返回了别的）按「还在」处理：不能因此反复重新起播。
    @Test func unknownAnswerCountsAsAlive() {
        #expect(GatewayRevival(coreValue: "") == .alive)
        #expect(GatewayRevival(coreValue: "something else") == .alive)
    }

    @Test func onlyRevivedAndResetMeanTheServiceWasLost() {
        #expect(GatewayRevival.revived.wasLost)
        #expect(GatewayRevival.reset.wasLost)
        #expect(!GatewayRevival.alive.wasLost)
        #expect(!GatewayRevival.idle.wasLost)
    }

    /// 起播时记下代数；之后服务丢过一次，代数就变了——播放器这时报失败要重新起播，而不是报「播放失败」。
    @Test func generationAdvancesEachTimeTheServiceIsLost() {
        let start = GatewayGeneration()
        #expect(start.after(.alive) == start)
        #expect(start.after(.idle) == start)
        let lostOnce = start.after(.revived)
        #expect(lostOnce != start)
        #expect(lostOnce.after(.alive) == lostOnce)
        #expect(lostOnce.after(.reset) != lostOnce)
        #expect(lostOnce.after(.reset) != start)
    }
}
