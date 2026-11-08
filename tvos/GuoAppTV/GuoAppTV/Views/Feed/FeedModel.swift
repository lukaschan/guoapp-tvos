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

    /// 推荐流还能不能往后取（取完一批后由核心告知）。
    private var hasMore = false
    private var loadingMore = false
    /// 连续几批没有新剧（见 FeedPaging.afterBatch）。
    private var emptyBatches = 0
    private var source = ""
    /// 非红果站源往后取片库的下一页页码。
    private var nextCatalogPage = 2

    /// hero 正在播的这部。
    var current: Drama? {
        dramas.indices.contains(currentIndex) ? dramas[currentIndex] : nil
    }

    var upNext: [Drama] {
        UpNext.window(count: dramas.count, current: currentIndex).map { dramas[$0] }
    }

    /// force：让核心从头取一份新的推荐（每次启动 App 第一次加载时），避免每次都是上次那一批。
    func load(source: String, force: Bool = false) async {
        if dramas.isEmpty { state = .loading }
        self.source = source
        do {
            let batch = try await FeedLoader.dramas(source: source, target: Self.targetCount, force: force)
            guard !Task.isCancelled else { return }
            apply(batch.dramas)
            hasMore = batch.hasMore
            emptyBatches = 0
            nextCatalogPage = 2
            loadMoreIfNeeded()
        } catch is CancellationError {
            // 被取消（离开页面或被更新的请求取代）：不是失败，不改状态。
            return
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
        loadMoreIfNeeded()
    }

    /// 在「接下来」里选定一部，让它成为 hero。
    func select(_ drama: Drama) {
        guard let index = dramas.firstIndex(where: { $0.id == drama.id }) else { return }
        currentIndex = index
        loadMoreIfNeeded()
    }

    /// hero 之后剩下的不够填满「接下来」时往后取一批，接在剧单后面（FeedPaging），
    /// 这样一直往下看都是新的剧，而不是循环同一批；取不到（没有更多或出错）时才绕回开头。
    private func loadMoreIfNeeded() {
        guard FeedPaging.shouldLoadMore(currentIndex: currentIndex, count: dramas.count, hasMore: hasMore, loading: loadingMore)
        else { return }
        loadingMore = true
        let source = source
        let page = nextCatalogPage
        Task {
            defer { loadingMore = false }
            guard let batch = try? await FeedLoader.more(source: source, page: page), source == self.source else {
                // 核心说暂时没有新的推荐或网络出错：这一轮不再取，先绕回开头；下次加载时再试。
                if source == self.source { hasMore = false }
                return
            }
            let merged = FeedPaging.merge(existing: dramas, incoming: batch.dramas, id: \.id)
            let progress = FeedPaging.afterBatch(hasMore: batch.hasMore, grew: merged.count > dramas.count, emptyBatches: emptyBatches)
            dramas = merged
            hasMore = progress.hasMore
            emptyBatches = progress.emptyBatches
            nextCatalogPage = page + 1
        }
    }

    /// 换上新剧单（FeedLoader 已去重）；重新加载时若正在播的那部还在，hero 不跳。
    private func apply(_ unique: [Drama]) {
        let currentID = current?.id
        dramas = unique
        currentIndex = currentID.flatMap { id in unique.firstIndex { $0.id == id } } ?? 0
        state = unique.isEmpty ? .empty : .loaded
    }
}
