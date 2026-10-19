import SwiftUI

/// 首页：内容发现页。
///
/// 结构：目录浏览 —— 站源、分类、榜单筛选 + 海报网格（保留原有全部分类、
/// 无限滚动与榜单能力，切换分类时自动回到目录顶部）。
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var categories: [Category] = [.all]
    @State private var selectedCategory = ""
    @State private var items: [Drama] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var warning = ""
    @State private var loading = false
    @State private var error: String?
    @State private var refreshing = false // 按播放/暂停键手动刷新时为 true
    @State private var categoriesSource = ""
    @State private var rankingBoards: [RankingBoard] = []
    @State private var selectedBoard = ""
    @State private var rankingBoardsSource = ""
    @State private var didApplyDefaultRanking = false
    /// 是否已应用过「红果默认展开榜单」：只应用一次，避免覆盖用户之后
    /// 手动点的分类或「全部」；视图存活期间选择一直保留。

    /// 榜单模式的哨兵分类 id：与核心分类 id 不冲突。
    private static let rankingCategoryId = "__ranking__"
    private var isRankingMode: Bool { selectedCategory == Self.rankingCategoryId }

    private var loadKey: String { appState.selectedSource + "|" + selectedCategory + "|" + selectedBoard }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                        catalogSection
                    }
                    .padding(.horizontal, TVTheme.pageInset)
                    .padding(.top, 0)
                    .padding(.bottom, 56)
                }
                // 首页按播放/暂停键：手动刷新（清空缓存、强制重拉）。
                // 挂在首页内容上（不是 NavigationStack），进详情页后不触发。
                .onPlayPauseCommand {
                    Task { await refresh() }
                }
                .onChange(of: loadKey) { _ in
                    // 切换站源 / 分类 / 榜单后回到目录区。
                    DispatchQueue.main.async {
                        proxy.scrollTo("catalog-top", anchor: .top)
                    }
                }
            }
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
            .onAppear {
                // 首次进入首页且为红果站源时，默认展开榜单，不用每次手动点。
                if !didApplyDefaultRanking, appState.selectedSource == "hongguo" {
                    didApplyDefaultRanking = true
                    selectedCategory = Self.rankingCategoryId
                }
            }
            .task(id: loadKey) {
                await reload(firstPage: true)
            }
        }
    }

    // MARK: - 目录浏览区

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.allSources {
                sourceRow
            }
            categoryRow
            if !warning.isEmpty {
                Text(warning)
                    .font(.system(size: 19))
                    .foregroundColor(TVTheme.textTertiary)
            }
            // 海报区往下挪：单独给海报加顶部间距，只动海报、不动上面那行。
            catalogContent
                .padding(.top, 12)
        }
        .id("catalog-top")
    }

    @ViewBuilder
    private var catalogContent: some View {
        if loading && items.isEmpty {
            TVLoadingView("正在加载…")
                .padding(.vertical, 160)
        } else if let error, items.isEmpty {
            VStack(spacing: 26) {
                TVStatusView(
                    icon: "exclamationmark.triangle",
                    title: "内容加载失败",
                    message: error,
                    expands: false
                )
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    Task { await reload(firstPage: true) }
                }
            }
            .padding(.vertical, 90)
        } else if items.isEmpty {
            TVStatusView(
                icon: "sparkles",
                title: "暂无内容",
                message: "换个分类或站源看看。",
                expands: false
            )
            .padding(.vertical, 90)
        } else {
            VStack(spacing: 20) {
                TVPosterGrid(items: items, showRank: isRankingMode, onReachEnd: {
                    Task { await loadMore() }
                })
                if loading && !items.isEmpty {
                    TVLoadingView(refreshing ? "正在刷新…" : "正在加载更多…")
                        .padding(.vertical, 24)
                }
            }
        }
    }

    private var sourceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SourceSite.available(allSources: appState.allSources)) { site in
                    TVChip(title: site.name, isSelected: site.id == appState.selectedSource) {
                        // 切到红果默认展开榜单，其他站源默认全部。
                        selectedCategory = site.id == "hongguo" ? Self.rankingCategoryId : ""
                        appState.selectedSource = site.id
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    /// 分类 + 榜单同一行：「全部」保留，「红果榜单」标签隐藏、只展示榜单列表；
    /// 点哪个只切内容、不收起；不自动滚动。
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories) { category in
                    TVChip(title: category.name, isSelected: category.id == selectedCategory) {
                        selectedCategory = category.id
                    }
                }
                // 榜单：仅红果站源有；「红果榜单」标签隐藏，只展示榜单列表。
                if appState.selectedSource == "hongguo" {
                    ForEach(rankingBoards) { board in
                        TVChip(
                            title: board.name,
                            isSelected: board.id == selectedBoard
                        ) {
                            // 点榜单直接进榜单模式（若当前在分类模式）。
                            selectedCategory = Self.rankingCategoryId
                            selectedBoard = board.id
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 数据加载（业务逻辑与原版一致）

    /// 手动刷新（首页按播放/暂停键）：清空首页缓存、强制重新拉取第一页。
    private func refresh() async {
        guard !loading, !refreshing else { return }
        refreshing = true
        loading = true // 先占位，避免刷新期间触发加载更多导致数据错乱
        await CoreClient.shared.invalidateHomeCache()
        await reload(firstPage: true)
        refreshing = false
        // reload 内部已把 loading 置 false，这里不再重复设置
    }

    private func reload(firstPage: Bool) async {
        if firstPage { page = 1 }
        loading = true
        error = nil
        do {
            // 分类列表：与模式无关，始终拉取，保证行里始终有子分类。
            // 只在站源变化时拿一次（首屏/切站源/刷新时）；榜单模式下拉取失败不报错
            //（不影响看榜单），分类模式下拉取失败则报错（看不到分类内容）。
            if firstPage, categoriesSource != appState.selectedSource {
                do {
                    let fetched = try await CoreClient.shared.categories(
                        source: appState.selectedSource
                    )
                    // 核心返回的分类里可能自带「全部」，与本地的 .all 重复；
                    // 按名称去重，保留第一个（即本地的 .all）。
                    var seenNames = Set<String>()
                    categories = ([.all] + fetched).filter { seenNames.insert($0.name).inserted }
                    categoriesSource = appState.selectedSource
                } catch {
                    if !isRankingMode { throw error }
                    // 榜单模式：分类拉取失败不阻塞，只展示榜单。
                }
            }
            // 榜单列表（红果站源）：与模式无关，始终拉取，保证行里始终有子榜单。
            // 只在站源变化时拿一次（首屏/切站源/刷新时）；分类模式下拉取失败不报错
            //（不影响看分类），榜单模式下拉取失败则报错（看不到榜单内容）。
            if firstPage, appState.selectedSource == "hongguo",
               rankingBoardsSource != appState.selectedSource {
                do {
                    let boards = try await CoreClient.shared.rankingBoards()
                    rankingBoards = boards.filter { $0.source == "hongguo" }
                    rankingBoardsSource = appState.selectedSource
                } catch {
                    if isRankingMode { throw error }
                    // 分类模式：榜单拉取失败不阻塞，只展示分类。
                }
            }
            if isRankingMode {
                // 榜单模式：默认选中第一个榜。
                if selectedBoard.isEmpty
                    || !rankingBoards.contains(where: { $0.id == selectedBoard }) {
                    selectedBoard = rankingBoards.first?.id ?? ""
                }
                if selectedBoard.isEmpty {
                    items = []
                    hasMore = false
                    warning = ""
                } else {
                    let result = try await CoreClient.shared.rankings(
                        board: selectedBoard, page: page
                    )
                    if firstPage {
                        items = result.items
                    } else {
                        items += result.items
                    }
                    hasMore = result.hasMore
                    warning = result.warning
                }
            } else {
                let result = try await CoreClient.shared.catalog(
                    source: appState.selectedSource, page: page, category: selectedCategory
                )
                if firstPage {
                    items = result.items
                } else {
                    items += result.items
                }
                hasMore = result.hasMore
                warning = result.warning
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        page += 1
        await reload(firstPage: false)
    }
}
