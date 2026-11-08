import Foundation

/// 搜索页的状态与边输入边搜索（原 SearchView 里的逻辑原样搬来）：
/// 停止输入 0.6 秒后用核心的 catalog 关键词搜索，结果按系列归组存进 SeriesLookup，再取联想词。
/// 输入继续变化时取消上一次，只显示最后一次的结果。
@MainActor
final class SearchModel: ObservableObject {
    @Published private(set) var query = ""
    @Published private(set) var results: [Drama] = []
    /// 当前结果对应的关键词；nil 表示还没搜过（或已清空）。
    @Published private(set) var searchedQuery: String?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var suggestions: [String] = []
    /// 还没输入时的「大家都在看」：推荐流的前 14 部（FeedLoader，与推荐页同一份）。
    @Published private(set) var popular: [Drama] = []
    @Published private(set) var popularLoading = false
    @Published private(set) var popularError: String?
    /// 在哪个站源里搜（跟随剧场里选的站源）。
    var source = "hongguo"

    private var task: Task<Void, Never>?
    private var popularTask: Task<Void, Never>?
    /// 已加载（或正在加载）「大家都在看」的站源；失败后清空，下次进页面自动再试。
    private var popularSource: String?

    /// 输入了关键词、但显示的还不是它的结果（等停止输入或正在搜）。
    var isAwaitingResults: Bool {
        guard let key = LiveSearch.query(from: query) else { return false }
        return loading || searchedQuery != key
    }

    /// 加载「大家都在看」：同一站源只加载一次，force（重试）时重新加载。
    func loadPopular(force: Bool = false) {
        guard force || popularSource != source else { return }
        let source = source
        popularSource = source
        popularTask?.cancel()
        popularLoading = true
        popularError = nil
        popularTask = Task {
            // 核心存着推荐时直接用（立刻显示，不联网；推荐页会在后台刷新这份推荐）。
            let cached = await FeedLoader.cached(source: source)
            if !cached.isEmpty {
                guard !Task.isCancelled else { return }
                popular = Array(cached.prefix(SearchCopy.popularCount))
                popularLoading = false
                return
            }
            do {
                let batch = try await FeedLoader.dramas(source: source, target: SearchCopy.popularCount)
                guard !Task.isCancelled else { return }
                popular = Array(batch.dramas.prefix(SearchCopy.popularCount))
                // 一部都没取到：下次进页面再试（页面上有提示和重试）。
                if popular.isEmpty { popularSource = nil }
            } catch is CancellationError {
                popularSource = nil
            } catch {
                guard !Task.isCancelled else { return }
                popularError = UserFacingError.message(for: error)
                popularSource = nil
            }
            popularLoading = false
        }
    }

    /// 搜索框里的文字变了。
    func update(text: String) {
        guard text != query else { return }
        query = text
        task?.cancel()
        task = Task { await liveSearch(text) }
    }

    func retry() {
        guard let key = LiveSearch.query(from: query) else { return }
        task?.cancel()
        task = Task { await search(key) }
    }

    private func liveSearch(_ text: String) async {
        guard let key = LiveSearch.query(from: text) else {
            suggestions = []
            results = []
            searchedQuery = nil
            error = nil
            loading = false
            return
        }
        try? await Task.sleep(for: LiveSearch.debounce)
        guard !Task.isCancelled else { return }
        if key != searchedQuery {
            await search(key)
        } else {
            // 改回了正在显示的关键词（输入后又删掉）：不重搜；被取消的上一次可能留下了加载中状态。
            loading = false
        }
        guard !Task.isCancelled else { return }
        let words = (try? await CoreClient.shared.suggestions(query: key)) ?? []
        guard !Task.isCancelled else { return }
        suggestions = words.filter { $0 != key }
    }

    // MARK: - 搜索（业务逻辑与原版一致）

    private func search(_ key: String) async {
        loading = true
        error = nil
        do {
            let result = try await CoreClient.shared.catalog(source: source, query: key, session: "search")
            // 输入已经变了：这次的结果作废（新的一次会自己更新状态）。
            guard !Task.isCancelled else { return }
            results = result.items
            searchedQuery = key
            // 归组出的系列存进 SeriesLookup，进详情页时「本系列」直接命中、不再搜索。
            for case .series(let group) in SeriesGrouping.group(result.items, title: \.title, source: \.source) {
                await SeriesLookup.shared.remember(group)
            }
        } catch is CancellationError {
            // 被更新的关键词取代（核心取消了这次）：新的那次会自己更新状态。
            return
        } catch {
            guard !Task.isCancelled else { return }
            self.error = UserFacingError.message(for: error)
            searchedQuery = key
        }
        loading = false
    }
}
