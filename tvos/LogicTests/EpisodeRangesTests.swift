import Testing
@testable import GuoAppLogic

struct EpisodeRangesTests {
    @Test func rangesSplitIntoThirties() {
        #expect(EpisodeRanges(episodeCount: 80).ranges == [1...30, 31...60, 61...80])
    }

    @Test func exactMultiple() {
        #expect(EpisodeRanges(episodeCount: 30).ranges == [1...30])
    }

    @Test func oneOverPage() {
        #expect(EpisodeRanges(episodeCount: 31).ranges == [1...30, 31...31])
        #expect(EpisodeRanges.label(for: 31...31) == "31")
    }

    @Test func emptyAndSingle() {
        #expect(EpisodeRanges(episodeCount: 0).ranges == [])
        #expect(EpisodeRanges(episodeCount: 1).ranges == [1...1])
    }

    @Test func labels() {
        #expect(EpisodeRanges.label(for: 1...30) == "1–30")
    }

    @Test func clampedIndex() {
        let ranges = EpisodeRanges(episodeCount: 80)
        #expect(ranges.clampedIndex(containing: 45) == 1)
        #expect(ranges.clampedIndex(containing: 0) == 0)
        #expect(ranges.clampedIndex(containing: 999) == 2)
        #expect(EpisodeRanges(episodeCount: 0).clampedIndex(containing: 5) == 0)
    }

    @Test func cellStates() {
        #expect(EpisodeCellState(episode: 3, currentEpisode: 5) == .watched)
        #expect(EpisodeCellState(episode: 5, currentEpisode: 5) == .current)
        #expect(EpisodeCellState(episode: 6, currentEpisode: 5) == .unwatched)
        #expect(EpisodeCellState(episode: 1, currentEpisode: nil) == .unwatched)
    }
}
