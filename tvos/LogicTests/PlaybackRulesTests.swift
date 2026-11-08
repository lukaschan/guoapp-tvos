import Testing
@testable import GuoAppLogic

/// 播放规则的特征测试：锁住播放页现有行为（预取、进度节流、换集时预取是否保留）。
struct PlaybackRulesTests {
    @Test func prefetchTriggersTenSecondsBeforeEnd() {
        #expect(PlaybackRules.prefetchIndex(
            position: 90, duration: 100, currentIndex: 0, episodeCount: 3, prefetchedIndex: nil, prefetchInFlight: false
        ) == 1)
        #expect(PlaybackRules.prefetchIndex(
            position: 85, duration: 100, currentIndex: 0, episodeCount: 3, prefetchedIndex: nil, prefetchInFlight: false
        ) == nil)
    }

    @Test func prefetchNotForLastEpisode() {
        #expect(PlaybackRules.prefetchIndex(
            position: 95, duration: 100, currentIndex: 2, episodeCount: 3, prefetchedIndex: nil, prefetchInFlight: false
        ) == nil)
    }

    @Test func prefetchNotTwice() {
        #expect(PlaybackRules.prefetchIndex(
            position: 95, duration: 100, currentIndex: 0, episodeCount: 3, prefetchedIndex: 1, prefetchInFlight: false
        ) == nil)
        #expect(PlaybackRules.prefetchIndex(
            position: 95, duration: 100, currentIndex: 0, episodeCount: 3, prefetchedIndex: nil, prefetchInFlight: true
        ) == nil)
    }

    @Test func prefetchNotAtZeroDuration() {
        #expect(PlaybackRules.prefetchIndex(
            position: 0, duration: 0, currentIndex: 0, episodeCount: 3, prefetchedIndex: nil, prefetchInFlight: false
        ) == nil)
    }

    @Test func saveThrottle() {
        #expect(!PlaybackRules.shouldSaveProgress(position: 4.9, lastSaved: 0))
        #expect(PlaybackRules.shouldSaveProgress(position: 5, lastSaved: 0))
        #expect(PlaybackRules.shouldSaveProgress(position: 10, lastSaved: -1))
    }

    @Test func keepsPrefetch() {
        #expect(PlaybackRules.keepsPrefetch(prefetchedIndex: 3, target: 3))
        #expect(PlaybackRules.keepsPrefetch(prefetchedIndex: 4, target: 3))
        #expect(!PlaybackRules.keepsPrefetch(prefetchedIndex: 5, target: 3))
        #expect(!PlaybackRules.keepsPrefetch(prefetchedIndex: nil, target: 3))
    }

    /// 全屏播放时播放中不让屏保出现；推荐页 hero 不拦，屏保按电视的设置照常出现。
    @Test func screenStaysAwakeOnlyWhilePlayingWhereAllowed() {
        #expect(PlaybackRules.disablesIdleTimer(hasPlayer: true, paused: false, keepsScreenAwake: true))
        #expect(!PlaybackRules.disablesIdleTimer(hasPlayer: true, paused: true, keepsScreenAwake: true))
        #expect(!PlaybackRules.disablesIdleTimer(hasPlayer: false, paused: false, keepsScreenAwake: true))
        #expect(!PlaybackRules.disablesIdleTimer(hasPlayer: true, paused: false, keepsScreenAwake: false))
    }
}
