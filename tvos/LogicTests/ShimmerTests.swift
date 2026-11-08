import Testing
@testable import GuoAppLogic

struct ShimmerTests {
    @Test func periodIsOnePointFourSeconds() {
        #expect(Shimmer.period == 1.4)
    }

    @Test func stillWithReduceMotion() {
        #expect(!Shimmer.animates(reduceMotion: true))
        #expect(Shimmer.animates(reduceMotion: false))
    }
}
