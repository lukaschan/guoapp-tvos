import SwiftUI

/// 首页：内容发现页。
///
/// 结构：目录浏览 —— 站源、分类、榜单筛选 + 海报网格（保留原有全部分类、
/// 无限滚动与榜单能力，切换分类时自动回到目录顶部）。
struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store
    @StateObject private var launcher = PlaybackLauncher()
    @State private var categories: [Category] = [.all]
    @State private var selectedCategory = ""
    @State private var items: [Drama] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var warning = ""
    @State private var loading = false
    /// 正在加载第一页的次数（换分类 / 榜单 / 站源）：大于 0 时网格变暗、分类行下转圈，不清空网格。
    @State private var firstPageLoads = 0
    /// 正在显示上次存下的内容（榜单快照或核心缓存的片库），新的在后台加载：不变暗、不转圈。
    @State private var showingSaved = false
    /// 加载领号（LoadGeneration）：只有最新一次加载的结果能改界面。
    @State private var loads = LoadGeneration()
    @State private var error: String?
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
                    .padding(.horizontal, TVTheme.posterPageInset)
                    .padding(.top, 0)
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
            .navigationDestination(for: ProducerRoute.self) { route in
                ProducerView(drama: route.drama)
            }
            .playbackLauncher(launcher)
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
                .overlay(alignment: .bottomLeading) {
                    if isSwitching {
                        ProgressView()
                            .padding(.leading, 12)
                            .offset(y: 56)
                    }
                }
            if !warning.isEmpty {
                Text(warning)
                    .font(.system(size: TVTheme.TextSize.caption2))
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
            TheaterSkeleton()
        } else if let error, items.isEmpty {
            TVFailureView(message: UserFacingError.message(for: error)) {
                Task { await reload(firstPage: true) }
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
            VStack(spacing: 32) {
                // 当前列表的第一部做「今日主推」，网格从第二部开始。
                if let featured = items.first {
                    FeaturedBanner(drama: featured) {
                        launcher.play(featured, store: store)
                    }
                    .padding(.horizontal, Self.bannerInset - TVTheme.posterPageInset)
                }
                TVPosterGrid(
                    items: Array(items.dropFirst()),
                    showRank: isRankingMode,
                    onReachEnd: { Task { await loadMore() } },
                    onPlay: { launcher.play($0, store: store) },
                    loadingID: launcher.loadingDramaID,
                    firstRank: 2
                )
                if loading && !isSwitching && !showingSaved {
                    TVLoadingView("正在加载更多…")
                        .padding(.vertical, 24)
                }
            }
            .opacity(isSwitching ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: isSwitching)
        }
    }

    /// 「今日主推」离屏幕边缘 80 pt（tvOS 安全区），网格仍用海报页边距。
    private static let bannerInset: CGFloat = 80

    /// 换分类后第一页还没回来、且网格里还有旧内容：变暗 + 转圈（首屏仍用整块加载视图）。
    private var isSwitching: Bool { firstPageLoads > 0 && !items.isEmpty && !showingSaved }

    /// 首屏还空着时先放上次存下的内容：榜单用本地快照，分类用核心缓存的片库（都不联网）。
    private func showSavedContent() async {
        if isRankingMode {
            guard let saved = RankingSnapshotStore.shared.snapshot(board: selectedBoard) else { return }
            items = saved
        } else {
            guard let page = try? await CoreClient.shared.cached(source: appState.selectedSource, category: selectedCategory),
                  !page.items.isEmpty
            else { return }
            items = page.items
        }
        showingSaved = true
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

    /// 分类 + 榜单同一行：红果站源的榜单排在最前（「全部」之前），
    /// 「红果榜单」标签隐藏、只展示榜单列表；点哪个只切内容、不收起；不自动滚动。
    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // 榜单：仅红果站源有，排在「全部」之前；「红果榜单」标签隐藏，只展示榜单列表。
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
                ForEach(categories) { category in
                    TVChip(title: category.name, isSelected: category.id == selectedCategory) {
                        selectedCategory = category.id
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - 数据加载（业务逻辑与原版一致）

    private func reload(firstPage: Bool) async {
        if firstPage {
            page = 1
            firstPageLoads += 1
        }
        defer {
            if firstPage { firstPageLoads -= 1 }
        }
        // 请求并行后，换了榜单 / 分类时慢的那次可能晚回来：每次加载领一个号，只有最新的能改界面。
        let generation = loads.begin()
        loading = true
        error = nil
        do {
            // 榜单列表（红果站源）先拿：它是核心里的固定列表，立刻返回（实测 0 秒），
            // 拿到就能选中榜单、先放上次存下的那一页；分类列表冷启动要联网（实测约 4 秒），放在后面。
            // 只在站源变化时拿一次；分类模式下拉取失败不报错（不影响看分类），榜单模式下拉取失败则报错。
            if firstPage, appState.selectedSource == "hongguo",
               rankingBoardsSource != appState.selectedSource {
                do {
                    let boards = try await CoreClient.shared.rankingBoards()
                    guard loads.isCurrent(generation) else { return }
                    rankingBoards = boards.filter { $0.source == "hongguo" }
                    rankingBoardsSource = appState.selectedSource
                } catch {
                    if isRankingMode { throw error }
                    // 分类模式：榜单拉取失败不阻塞，只展示分类。
                }
            }
            if isRankingMode,
               selectedBoard.isEmpty || !rankingBoards.contains(where: { $0.id == selectedBoard }) {
                // 榜单模式：默认选中第一个榜。
                selectedBoard = rankingBoards.first?.id ?? ""
            }
            // 首屏还空着：先放上次存下的内容（榜单快照或核心缓存的片库），再联网取新的。
            if firstPage, items.isEmpty, !isRankingMode || !selectedBoard.isEmpty {
                await showSavedContent()
                guard loads.isCurrent(generation) else { return }
            }
            // 分类列表：与模式无关，始终拉取，保证行里始终有子分类。
            // 只在站源变化时拿一次；榜单模式下拉取失败不报错（不影响看榜单），分类模式下拉取失败则报错。
            if firstPage, categoriesSource != appState.selectedSource {
                do {
                    let fetched = try await CoreClient.shared.categories(
                        source: appState.selectedSource
                    )
                    guard loads.isCurrent(generation) else { return }
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
            if isRankingMode {
                if selectedBoard.isEmpty {
                    items = []
                    hasMore = false
                    warning = ""
                } else {
                    let board = selectedBoard
                    let result = try await CoreClient.shared.rankings(board: board, page: page)
                    guard loads.isCurrent(generation) else { return }
                    if firstPage {
                        items = result.items
                        RankingSnapshotStore.shared.save(board: board, items: result.items)
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
                guard loads.isCurrent(generation) else { return }
                if firstPage {
                    items = result.items
                } else {
                    items += result.items
                }
                hasMore = result.hasMore
                warning = result.warning
            }
        } catch {
            guard loads.isCurrent(generation) else { return }
            self.error = error.localizedDescription
        }
        showingSaved = false
        loading = false
    }

    private func loadMore() async {
        guard hasMore, !loading else { return }
        page += 1
        await reload(firstPage: false)
    }
}
