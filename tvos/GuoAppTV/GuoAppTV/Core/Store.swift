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
    /// 追剧更新（FollowUpdate）：用户已知的集数；nil 表示还没有基准（第一次检查时设）。
    /// 以下三个字段都是可选的：第四阶段之前存下的追剧照样能读出来。
    var knownEpisodes: Int?
    /// 最近一次检查（核心 followCheck）看到的集数。
    var latestEpisodes: Int?
    var checkedAt: Date?
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

    // MARK: - 追剧更新

    /// 记下一次检查的结果（基准规则见 FollowUpdate.afterCheck）。
    /// releaseStatus：检查带回的完结状态（有就记下，已完结的剧以后不再自动检查）。
    func recordCheck(dramaID: String, latestEpisodes: Int, releaseStatus: String = "", at date: Date) {
        guard let index = follows.firstIndex(where: { $0.drama.id == dramaID }) else { return }
        if !releaseStatus.isEmpty { follows[index].drama.releaseStatus = releaseStatus }
        let counts = FollowUpdate.afterCheck(known: follows[index].knownEpisodes, latest: latestEpisodes)
        follows[index].knownEpisodes = counts.known
        follows[index].latestEpisodes = counts.latest
        follows[index].checkedAt = date
        persist()
    }

    /// 用户自己打开或播放了这部剧：已知集数追平，角标消失。
    func acknowledgeUpdate(dramaID: String) {
        guard let index = follows.firstIndex(where: { $0.drama.id == dramaID }),
              let latest = follows[index].latestEpisodes,
              FollowUpdate.hasUpdate(known: follows[index].knownEpisodes, latest: latest)
        else { return }
        follows[index].knownEpisodes = latest
        persist()
    }

    /// 这部剧有更新时的角标（「更新至 N 集」），否则 nil。
    func updateBadge(for dramaID: String) -> String? {
        guard let follow = follows.first(where: { $0.drama.id == dramaID }),
              FollowUpdate.hasUpdate(known: follow.knownEpisodes, latest: follow.latestEpisodes),
              let latest = follow.latestEpisodes
        else { return nil }
        return FollowUpdate.badge(latest: latest)
    }

    var updatedFollowCount: Int {
        follows.filter { FollowUpdate.hasUpdate(known: $0.knownEpisodes, latest: $0.latestEpisodes) }.count
    }

    func isFollowing(_ drama: Drama) -> Bool {
        follows.contains { $0.drama.id == drama.id }
    }

    /// knownEpisodes：在详情页追剧时传详情里的分集数（与 followCheck 返回的是同一种计数），
    /// 作为追剧更新的基准；其它地方追剧不传，由第一次检查设基准。
    func toggleFollow(_ drama: Drama, knownEpisodes: Int? = nil) {
        if let index = follows.firstIndex(where: { $0.drama.id == drama.id }) {
            follows.remove(at: index)
        } else {
            let known = knownEpisodes.flatMap { $0 > 0 ? $0 : nil }
            follows.insert(FollowedDrama(drama: drama, followedAt: Date(), knownEpisodes: known), at: 0)
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

    /// 清除全部观看记录：「继续观看」清空，追剧列表不受影响。
    func clearHistory() {
        progress.removeAll()
        persist()
    }

    /// 删除某部剧的全部观看记录（最近观看里该剧的整条记录）。
    func deleteHistory(for drama: Drama) {
        progress.removeAll { $0.drama.id == drama.id }
        persist()
    }
}
