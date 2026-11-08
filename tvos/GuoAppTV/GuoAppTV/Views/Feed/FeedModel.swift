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

    static let hongguoSource = "hongguo"
    /// 红果首页推荐流（键见 upstream/native/core/provider_hongguo_recommendations.go）。
    static let feedKey = "home_feed"
    /// 首次加载至少凑够 hero 一部 + 接下来 10 部；推荐流每页只有几部，最多请求 4 次。
    static let targetCount = 11
    static let maximumRequests = 4

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
            let items: [Drama]
            if source == Self.hongguoSource {
                items = try await loadRecommendations()
            } else {
                items = try await CoreClient.shared.catalog(source: source).items
            }
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

    /// 核心返回的是累积的整份列表：先取第一页，不够再「more」，直到够数、没有更多或请求满 4 次。
    private func loadRecommendations() async throws -> [Drama] {
        var page = try await CoreClient.shared.recommendations(feed: Self.feedKey)
        var requests = 1
        while page.hasMore, page.items.count < Self.targetCount, requests < Self.maximumRequests, !Task.isCancelled {
            requests += 1
            // 「more」失败（如核心说暂时没有新的推荐）或没变多时，用已有的，不算整体失败。
            guard let next = try? await CoreClient.shared.recommendations(feed: Self.feedKey, more: true),
                  next.items.count > page.items.count
            else { break }
            page = next
        }
        return page.items
    }

    /// 按 id 去重；重新加载时若正在播的那部还在，hero 不跳。
    private func apply(_ items: [Drama]) {
        var seen = Set<String>()
        let unique = items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
        let currentID = current?.id
        dramas = unique
        currentIndex = currentID.flatMap { id in unique.firstIndex { $0.id == id } } ?? 0
        state = unique.isEmpty ? .empty : .loaded
    }
}
