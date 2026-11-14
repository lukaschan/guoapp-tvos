import SwiftUI

/// 搜索页：tvOS 原生搜索界面（键盘在上、结果在下，与 Apple TV App 的搜索一致），边输入边出结果。
/// 搜索框由 NativeSearchContainer（UIKit）提供，避免 SwiftUI 回写文字打断 iPhone 的中文输入；
/// 搜索逻辑在 SearchModel（核心 catalog 的关键词搜索 + 系列归组，与原版一致）。
/// 切到本页时焦点留在标签栏，向下才进入键盘。
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @StateObject private var model = SearchModel()
    @StateObject private var launcher = PlaybackLauncher()
    @State private var path: [Drama] = []

    var body: some View {
        NavigationStack(path: $path) {
            NativeSearchContainer(model: model, suggestions: model.suggestions, prompt: "输入剧名、演员或关键词") {
                // 结果放在搜索控制器自己的 UIHostingController 里：环境要显式传，导航用回调推到外层的 NavigationStack。
                SearchResultsView(model: model, launcher: launcher) { drama in
                    path.append(drama)
                }
                .environmentObject(appState)
                .environmentObject(store)
            }
            .ignoresSafeArea()
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
            .navigationDestination(for: ProducerRoute.self) { route in
                ProducerView(drama: route.drama)
            }
            .playbackLauncher(launcher)
        }
        .onAppear {
            model.source = appState.selectedSource
            model.loadPopular()
        }
        .onChange(of: appState.selectedSource) { source in
            model.source = source
            model.loadPopular()
        }
    }
}

/// 搜索结果与状态：没输入时「大家都在看」；输入后「找到 N 部短剧」+ 网格 / 加载骨架 / 没有找到 / 失败重试。
private struct SearchResultsView: View {
    @ObservedObject var model: SearchModel
    @ObservedObject var launcher: PlaybackLauncher
    let onOpen: (Drama) -> Void

    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                resultSection
            }
            .padding(.horizontal, TVTheme.posterPageInset)
            .padding(.top, 24)
            .padding(.bottom, 56)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let error = model.error {
            TVFailureView(message: error) {
                model.retry()
            }
            .padding(.vertical, 100)
        } else if LiveSearch.query(from: model.query) == nil {
            popularSection
        } else if model.results.isEmpty, model.isAwaitingResults {
            PosterGridSkeleton(showsTitle: false)
                .padding(.top, 12)
        } else if model.results.isEmpty {
            TVStatusView(
                icon: "magnifyingglass",
                title: SearchCopy.notFound(model.searchedQuery ?? model.query),
                message: SearchCopy.notFoundHint,
                expands: false
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
        } else {
            // 换关键词时旧结果先变暗，新结果回来再替换，不闪成整块加载。
            VStack(alignment: .leading, spacing: 24) {
                sectionTitle(SearchCopy.found(model.results.count))
                resultGrid
            }
            .padding(.top, 12)
            .opacity(model.isAwaitingResults ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: model.isAwaitingResults)
        }
    }

    /// 还没输入：「大家都在看」（推荐流前 14 部）；加载中是骨架，失败可重试。
    @ViewBuilder
    private var popularSection: some View {
        switch PopularState.make(count: model.popular.count, loading: model.popularLoading, error: model.popularError) {
        case .posters:
            VStack(alignment: .leading, spacing: 24) {
                sectionTitle(SearchCopy.popularTitle)
                LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
                    ForEach(model.popular) { drama in
                        TVPosterCard(drama: drama, isLoading: launcher.loadingDramaID == drama.id, onSelect: { onOpen(drama) })
                            .onPlayPauseCommand { launcher.play(drama, store: store) }
                    }
                }
                .prefetchesOnPosterFocus(model.popular)
            }
            .padding(.top, 12)
        case .loading:
            PosterGridSkeleton()
                .padding(.top, 12)
        case .failed(let error):
            TVFailureView(message: error) {
                model.loadPopular(force: true)
            }
            .padding(.vertical, 100)
        case .empty:
            VStack(spacing: 28) {
                TVStatusView(icon: "sparkles", title: SearchCopy.popularEmptyTitle, message: SearchCopy.popularEmptyHint, expands: false)
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    model.loadPopular(force: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 100)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: TVTheme.TextSize.callout, weight: .bold))
            .foregroundColor(TVTheme.textPrimary)
    }

    /// 搜索结果：同一系列的各部合成一张卡片（「共 N 部」），其余单部剧原样显示。
    private var resultGrid: some View {
        let entries = SeriesGrouping.group(model.results, title: \.title, source: \.source)
        return LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .single(let drama):
                    TVPosterCard(drama: drama, isLoading: launcher.loadingDramaID == drama.id, onSelect: { onOpen(drama) })
                        .onPlayPauseCommand { launcher.play(drama, store: store) }
                case .series(let group):
                    let target = seriesTarget(group)
                    TVPosterCard(
                        drama: group.parts[0].item,
                        title: group.base,
                        subtitle: SeriesGrouping.partsLabel(group.partNumbers, unit: group.unit),
                        badge: "共 \(group.parts.count) \(group.unit)",
                        linkValue: target,
                        isLoading: launcher.loadingDramaID == target.id,
                        onSelect: { onOpen(target) }
                    )
                    .onPlayPauseCommand { launcher.play(target, store: store) }
                }
            }
        }
        .prefetchesOnPosterFocus(model.results)
    }

    /// 系列卡片进入 / 播放哪一部：最近看过的那部，没看过就第一部。
    private func seriesTarget(_ group: SeriesGroup<Drama>) -> Drama {
        let watched = group.parts.compactMap { part in
            store.latestProgress(for: part.item.id).map { (part.item, $0.updatedAt) }
        }
        return watched.max { $0.1 < $1.1 }?.0 ?? group.parts[0].item
    }
}
