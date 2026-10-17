import Foundation
import SwiftUI

// MARK: - 应用状态

@MainActor
final class AppState: ObservableObject {
    @Published var initialized = false
    @Published var initializeError: String?
    @Published var allSources = false
    @Published var selectedSource = "hongguo"

    /// 启动本地核心；已初始化时直接返回。失败时保留错误文案供界面重试。
    func bootstrap() async {
        guard !initialized else { return }
        initializeError = nil
        do {
            allSources = try await CoreClient.shared.initialize()
            if !SourceSite.available(allSources: allSources).contains(where: { $0.id == selectedSource }) {
                selectedSource = "hongguo"
            }
            initialized = true
        } catch {
            initializeError = error.localizedDescription
        }
    }
}

// MARK: - 追剧 / 观看进度（本地持久化）

struct WatchProgress: Codable, Equatable {
    var drama: Drama
    var episode: Int
    var episodeTitle: String
    var position: Double
    var duration: Double
    var updatedAt: Date

    var episodeKey: String { "\(drama.id)#\(episode)" }
}

struct FollowedDrama: Codable, Equatable {
    var drama: Drama
    var followedAt: Date
}

private struct PersistedState: Codable {
    var follows: [FollowedDrama] = []
    var progress: [WatchProgress] = []
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var follows: [FollowedDrama] = []
    @Published private(set) var progress: [WatchProgress] = []

    private let file: URL

    init() {
        // 与核心目录同理：tvOS 真机上 Application Support 只读，
        // 追剧与进度存在 Caches，系统可能在存储不足时回收。
        let directory = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        file = directory.appendingPathComponent("tv-state.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: file) else { return }
        guard let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        follows = state.follows
        progress = state.progress
    }

    private func persist() {
        let state = PersistedState(follows: follows, progress: progress)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: file, options: .atomic)
    }

    func isFollowing(_ drama: Drama) -> Bool {
        follows.contains { $0.drama.id == drama.id }
    }

    func toggleFollow(_ drama: Drama) {
        if let index = follows.firstIndex(where: { $0.drama.id == drama.id }) {
            follows.remove(at: index)
        } else {
            follows.insert(FollowedDrama(drama: drama, followedAt: Date()), at: 0)
        }
        persist()
    }

    /// 某部剧的最新观看进度（任意分集）。
    func latestProgress(for dramaId: String) -> WatchProgress? {
        progress.filter { $0.drama.id == dramaId }.max { $0.updatedAt < $1.updatedAt }
    }

    /// 最近观看：每部剧只保留最新一条进度，按观看时间倒序。
    /// 与 iOS 端 history 行为一致（按 drama 去重、按 updatedAt 倒序）。
    var recentHistory: [WatchProgress] {
        var latest: [String: WatchProgress] = [:]
        for entry in progress {
            if let old = latest[entry.drama.id] {
                if entry.updatedAt > old.updatedAt { latest[entry.drama.id] = entry }
            } else {
                latest[entry.drama.id] = entry
            }
        }
        return latest.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    func progress(for dramaId: String, episode: Int) -> WatchProgress? {
        progress.first { $0.drama.id == dramaId && $0.episode == episode }
    }

    func saveProgress(_ entry: WatchProgress) {
        if let index = progress.firstIndex(where: { $0.episodeKey == entry.episodeKey }) {
            progress[index] = entry
        } else {
            progress.append(entry)
        }
        // 只保留最近 500 条进度，避免文件无限增长。
        if progress.count > 500 {
            progress = Array(progress.sorted { $0.updatedAt > $1.updatedAt }.prefix(500))
        }
        persist()
    }
}
