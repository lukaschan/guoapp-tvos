import Testing
@testable import GuoAppLogic

/// 「我的」的观看统计（只看本地存的观看记录，最近 500 集）。
struct ViewingStatsTests {
    @Test func statsCountDistinctDramasAndFinishedEpisodes() {
        let stats = ViewingStats.make(follows: 12, entries: [
            (dramaID: "a", position: 50, duration: 100),
            (dramaID: "a", position: 95, duration: 100),
            (dramaID: "b", position: 3600, duration: 3600),
            (dramaID: "c", position: 0, duration: 100),
        ])
        #expect(stats == ViewingStats(following: 12, dramasWatched: 2, episodesFinished: 2, hoursWatched: 1.0))
    }

    @Test func emptyHistory() {
        #expect(ViewingStats.make(follows: 0, entries: []) == ViewingStats(following: 0, dramasWatched: 0, episodesFinished: 0, hoursWatched: 0))
    }
}

/// 「已用空间」的文字（与系统一样按 1000 进位）。
struct StorageSizeTests {
    @Test func storageLabels() {
        #expect(StorageSize.label(bytes: 412_000_000) == "412 MB")
        #expect(StorageSize.label(bytes: 1_200_000_000) == "1.2 GB")
        #expect(StorageSize.label(bytes: 820_000) == "820 KB")
        #expect(StorageSize.label(bytes: 512) == "512 B")
    }
}
