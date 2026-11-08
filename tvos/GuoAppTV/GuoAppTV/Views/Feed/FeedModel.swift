import Foundation

/// 推荐页的剧单：红果用核心的推荐流（其它站源用其片库第一页），
/// 外加 hero 当前播哪一部、「接下来」是哪些。
@MainActor
final class FeedModel: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    /// 首次加载至少凑够 hero 一部 + 接下来 10 部（加载规则见 FeedLoader）。
    static let targetCount = 11

    @Published private(set) var dramas: [Drama] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var state: LoadState = .loading

    /// hero 正在播的这部。
    var current: Drama? {
        dramas.indices.contains(currentIndex) ? dramas[currentIndex] : nil
    }

    var upNext: [Drama] {
        UpNext.window(count: dramas.count, current: currentIndex).map { dramas[$0] }
    }

    func load(source: String) async {
        if dramas.isEmpty { state = .loading }
        do {
            let items = try await FeedLoader.dramas(source: source, target: Self.targetCount)
            guard !Task.isCancelled else { return }
            apply(items)
        } catch {
            guard !Task.isCancelled else { return }
            // 已有剧单时保留（重新加载失败不打断正在看的）；否则显示错误与重试。
            if dramas.isEmpty { state = .failed(UserFacingError.message(for: error)) }
        }
    }

    /// 当前这部的最后一集播完：换到下一部，到底后回到第一部。
    func advance() {
        guard !dramas.isEmpty else { return }
        currentIndex = (currentIndex + 1) % dramas.count
    }

    /// 在「接下来」里选定一部，让它成为 hero。
    func select(_ drama: Drama) {
        guard let index = dramas.firstIndex(where: { $0.id == drama.id }) else { return }
        currentIndex = index
    }

    /// 换上新剧单（FeedLoader 已去重）；重新加载时若正在播的那部还在，hero 不跳。
    private func apply(_ unique: [Drama]) {
        let currentID = current?.id
        dramas = unique
        currentIndex = currentID.flatMap { id in unique.firstIndex { $0.id == id } } ?? 0
        state = unique.isEmpty ? .empty : .loaded
    }
}
