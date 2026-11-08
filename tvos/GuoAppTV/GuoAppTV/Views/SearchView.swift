import SwiftUI

/// 搜索页：tvOS 原生搜索界面（SwiftUI `.searchable`，与 Apple TV App 的搜索一致）。
///
/// 顶部是系统的搜索框与键盘，结果网格就在下面，边输入边出结果（停止输入 0.6 秒后搜索）；
/// 联想词显示在键盘旁，选中即搜。切到本页时焦点留在标签栏，向下才进入键盘。
/// 搜索本身与原版一致：核心 catalog 的 query 搜索，结果按系列归组。
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @StateObject private var launcher = PlaybackLauncher()
    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var results: [Drama] = []
    /// 当前结果对应的关键词；nil 表示还没搜过（或已清空）。
    @State private var searchedQuery: String?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    resultSection
                }
                .padding(.horizontal, TVTheme.posterPageInset)
                .padding(.top, 24)
                .padding(.bottom, 56)
            }
            .searchable(text: $query, prompt: "输入剧名、演员或关键词")
            .searchSuggestions {
                ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
            }
            .task(id: query) {
                await liveSearch()
            }
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
            .playbackLauncher(launcher)
        }
    }

    // MARK: - 结果与状态

    @ViewBuilder
    private var resultSection: some View {
        if let error {
            VStack(spacing: 26) {
                TVStatusView(
                    icon: "exclamationmark.triangle",
                    title: "搜索失败",
                    message: error,
                    expands: false
                )
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    guard let key = LiveSearch.query(from: query) else { return }
                    Task { await search(key) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
        } else if loading && results.isEmpty {
            TVLoadingView("正在搜索…")
                .padding(.vertical, 160)
        } else if searchedQuery != nil, !loading, results.isEmpty {
            TVStatusView(
                icon: "magnifyingglass",
                title: "没有找到相关内容",
                message: "换个关键词试试。",
                expands: false
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
        } else if !results.isEmpty {
            // 换关键词时旧结果先变暗，新结果回来再替换，不闪成整块加载。
            resultGrid
                .padding(.top, 12)
                .opacity(loading ? 0.5 : 1)
                .animation(.easeInOut(duration: 0.2), value: loading)
        }
    }

    /// 搜索结果：同一系列的各部合成一张卡片（「共 N 部」），其余单部剧原样显示。
    private var resultGrid: some View {
        let entries = SeriesGrouping.group(results, title: \.title, source: \.source)
        return LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .single(let drama):
                    TVPosterCard(drama: drama, isLoading: launcher.loadingDramaID == drama.id)
                        .onPlayPauseCommand { launcher.play(drama, store: store) }
                case .series(let group):
                    let target = seriesTarget(group)
                    TVPosterCard(
                        drama: group.parts[0].item,
                        title: group.base,
                        subtitle: SeriesGrouping.partsLabel(group.partNumbers, unit: group.unit),
                        badge: "共 \(group.parts.count) \(group.unit)",
                        linkValue: target,
                        isLoading: launcher.loadingDramaID == target.id
                    )
                    .onPlayPauseCommand { launcher.play(target, store: store) }
                }
            }
        }
    }

    /// 系列卡片进入 / 播放哪一部：最近看过的那部，没看过就第一部。
    private func seriesTarget(_ group: SeriesGroup<Drama>) -> Drama {
        let watched = group.parts.compactMap { part in
            store.latestProgress(for: part.item.id).map { (part.item, $0.updatedAt) }
        }
        return watched.max { $0.1 < $1.1 }?.0 ?? group.parts[0].item
    }

    // MARK: - 搜索（业务逻辑与原版一致）

    /// 关键词变化后：清空时复位；否则等停止输入 0.6 秒再搜，并更新联想词。
    /// 输入继续变化会取消这一次（.task(id:)），只有最后一次的结果会显示。
    private func liveSearch() async {
        guard let key = LiveSearch.query(from: query) else {
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

    private func search(_ key: String) async {
        loading = true
        error = nil
        do {
            let result = try await CoreClient.shared.catalog(
                source: appState.selectedSource, query: key
            )
            // 输入已经变了：这次的结果作废（新的一次会自己更新状态）。
            guard !Task.isCancelled else { return }
            results = result.items
            searchedQuery = key
            // 归组出的系列存进 SeriesLookup，进详情页时「本系列」直接命中、不再搜索。
            for case .series(let group) in SeriesGrouping.group(result.items, title: \.title, source: \.source) {
                await SeriesLookup.shared.remember(group)
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
            searchedQuery = key
        }
        loading = false
    }
}
