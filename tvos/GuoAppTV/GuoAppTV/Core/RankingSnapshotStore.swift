import Foundation

/// 剧场榜单快照（Caches/ranking-snapshots.json）：每个榜单只存第 1 页，启动时先显示它。
@MainActor
final class RankingSnapshotStore {
    static let shared = RankingSnapshotStore()

    private let file: URL
    private var snapshots: [String: RankingSnapshot<Drama>]

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        file = caches.appendingPathComponent("ranking-snapshots.json")
        let data = try? Data(contentsOf: file)
        snapshots = data.flatMap { try? JSONDecoder().decode([String: RankingSnapshot<Drama>].self, from: $0) } ?? [:]
    }

    /// 这个榜单上次存下的第 1 页；没有或超过 7 天时为 nil。
    func snapshot(board: String) -> [Drama]? {
        guard let saved = snapshots[board], RankingSnapshot<Drama>.isUsable(savedAt: saved.savedAt, now: Date()),
              !saved.items.isEmpty
        else { return nil }
        return saved.items
    }

    func save(board: String, items: [Drama]) {
        guard !items.isEmpty else { return }
        snapshots[board] = RankingSnapshot(board: board, items: items, savedAt: Date())
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
