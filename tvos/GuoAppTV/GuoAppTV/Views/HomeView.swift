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
    @State private var categoriesSource = ""
    @State private var rankingBoards: [RankingBoard] = []
    @State private var selectedBoard = ""
    @State private var rankingBoardsSource = ""

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
                    .padding(.top, 8)
                    .padding(.bottom, 56)
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
            .task(id: loadKey) {
                await reload(firstPage: true)
            }
        }
    }

    // MARK: - 目录浏览区

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if appState.allSources {
                sourceRow
            }
            categoryRow
            if !warning.isEmpty {
                Text(warning)
                    .font(.system(size: 19))
                    .foregroundColor(TVTheme.textTertiary)
            }
            catalogContent
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
                    TVLoadingView("正在加载更多…")
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
                        selectedCategory = ""
                        appState.selectedSource = site.id
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    private var categoryRow: some View {
        ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories) { category in
                            TVChip(title: category.name, isSelected: category.id == selectedCategory) {
                                selectedCategory = category.id
                            }
                        }
                        // 红果榜单：与分类同一行，仅红果站源有。
                        if appState.selectedSource == "hongguo" {
                            TVChip(title: "红果榜单", isSelected: isRankingMode) {
                                selectedCategory = Self.rankingCategoryId
                            }
                            // 榜单模式下，榜单切换胶囊紧跟在「红果榜单」右边，
                            // 同一行横向滚动、不换行。
                            if isRankingMode {
                                ForEach(rankingBoards) { board in
                                    TVChip(
                                        title: board.name,
                                        isSelected: board.id == selectedBoard,
                                        compact: true
                                    ) {
                                        selectedBoard = board.id
                                    }
                                    .id(board.id == rankingBoards.first?.id ? "board-first" : board.id)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }
                // 榜单出现后自动滚到第一个榜单按钮，避免它藏在屏幕外。
                .onChange(of: isRankingMode && !rankingBoards.isEmpty) { shouldScroll in
                    if shouldScroll {
                        DispatchQueue.main.async {
                            proxy.scrollTo("board-first", anchor: .leading)
                        }
                    }
                }
        }
    }

    // MARK: - 数据加载（业务逻辑与原版一致）

    private func reload(firstPage: Bool) async {
        if firstPage { page = 1 }
        loading = true
        error = nil
        do {
            if isRankingMode {
                // 榜单模式：榜单列表只拿一次，默认选中第一个榜。
                if rankingBoardsSource != appState.selectedSource {
                    let boards = try await CoreClient.shared.rankingBoards()
                    rankingBoards = boards.filter { $0.source == "hongguo" }
                    rankingBoardsSource = appState.selectedSource
                    if selectedBoard.isEmpty
                        || !rankingBoards.contains(where: { $0.id == selectedBoard }) {
                        selectedBoard = rankingBoards.first?.id ?? ""
                    }
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
                if categoriesSource != appState.selectedSource {
                    let fetched = try await CoreClient.shared.categories(
                        source: appState.selectedSource
                    )
                    // 核心返回的分类里可能自带「全部」，与本地的 .all 重复；
                    // 按名称去重，保留第一个（即本地的 .all）。
                    var seenNames = Set<String>()
                    categories = ([.all] + fetched).filter { seenNames.insert($0.name).inserted }
                    categoriesSource = appState.selectedSource
                }
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
