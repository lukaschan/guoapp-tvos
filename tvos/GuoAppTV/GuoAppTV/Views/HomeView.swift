import SwiftUI

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
            VStack(alignment: .leading, spacing: 12) {
                categoryRow
                if appState.allSources {
                    sourceRow
                }
                if !warning.isEmpty {
                    Text(warning).font(.subheadline).foregroundColor(.secondary)
                }
                if loading && items.isEmpty {
                    Spacer()
                    HStack { Spacer(); ProgressView("正在加载…"); Spacer() }
                    Spacer()
                } else if let error, items.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Text(error).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("重试") { Task { await reload(firstPage: true) } }
                    }
                    .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    PosterGrid(items: items, onReachEnd: {
                        Task { await loadMore() }
                    })
                    if loading && !items.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("正在加载…")
                            Spacer()
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .padding(.horizontal, 48)
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
            .task(id: loadKey) {
                await reload(firstPage: true)
            }
        }
    }

    private var sourceRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(SourceSite.available(allSources: appState.allSources)) { site in
                    let selected = site.id == appState.selectedSource
                    Button(site.name) {
                        selectedCategory = ""
                        appState.selectedSource = site.id
                    }
                    .font(.system(size: 16))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selected ? Color.white : Color.white.opacity(0.12))
                    .foregroundColor(selected ? .black : .white)
                    .cornerRadius(8)
                }
            }
        }
    }

    private var categoryRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(categories) { category in
                        let selected = category.id == selectedCategory
                        Button(category.name) {
                            selectedCategory = category.id
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selected ? Color.white : Color.white.opacity(0.12))
                        .foregroundColor(selected ? .black : .white)
                        .cornerRadius(8)
                    }
                    // 红果榜单：与分类同一行，仅红果站源有。
                    if appState.selectedSource == "hongguo" {
                        let selected = isRankingMode
                        Button("红果榜单") {
                            selectedCategory = Self.rankingCategoryId
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(selected ? Color.white : Color.white.opacity(0.12))
                        .foregroundColor(selected ? .black : .white)
                        .cornerRadius(8)
                        // 榜单模式下，榜单切换按钮紧跟在“红果榜单”右边，
                        // 同一行横向滚动、不换行；按钮和字体都更小，省空间。
                        if isRankingMode {
                            ForEach(rankingBoards) { board in
                                let boardSelected = board.id == selectedBoard
                                Button(board.name) {
                                    selectedBoard = board.id
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(boardSelected ? Color.white : Color.white.opacity(0.12))
                                .foregroundColor(boardSelected ? .black : .white)
                                .cornerRadius(6)
                                .id(board.id == rankingBoards.first?.id ? "board-first" : board.id)
                            }
                        }
                    }
                }
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
                    // 核心返回的分类里可能自带“全部”，与本地的 .all 重复；
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
