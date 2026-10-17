import SwiftUI

/// 搜索页：大屏搜索。
///
/// 顶部为醒目的搜索框（进入页面自动聚焦，拉起系统键盘）；
/// 输入中给出联想词；确认后展示统一的海报网格。
/// 加载中 / 失败 / 无结果均有清晰状态。
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var suggestions: [String] = []
    @State private var results: [Drama] = []
    @State private var searched = false
    @State private var loading = false
    @State private var error: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchField
                    if !searched, !suggestions.isEmpty {
                        suggestionList
                    }
                    resultSection
                }
                .padding(.horizontal, TVTheme.pageInset)
                .padding(.top, 24)
                .padding(.bottom, 56)
            }
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
        }
    }

    // MARK: - 搜索框

    private var searchField: some View {
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(searchFocused ? TVTheme.textPrimary : TVTheme.textTertiary)
            TextField("输入剧名、演员或关键词", text: $query)
                .font(.system(size: 26))
                .foregroundColor(.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
                .onChange(of: query) { newValue in
                    if newValue.isEmpty {
                        suggestions = []
                        results = []
                        searched = false
                    } else {
                        searched = false
                    }
                }
                .task(id: query) {
                    guard !query.isEmpty else { return }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    suggestions = (try? await CoreClient.shared.suggestions(query: query)) ?? []
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(TVTheme.textTertiary)
                }
                .buttonStyle(TVPressButtonStyle())
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(searchFocused ? Color(white: 0.18) : Color(white: 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(searchFocused ? 0.85 : 0), lineWidth: 3)
        )
        .onAppear {
            // 进入搜索页默认聚焦搜索框；从详情页返回时不打扰已结果状态。
            if !searched {
                DispatchQueue.main.async { searchFocused = true }
            }
        }
    }

    // MARK: - 联想词

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                Button {
                    query = suggestion
                    Task { await search() }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(TVTheme.textTertiary)
                        Text(suggestion)
                            .font(.system(size: 23))
                            .foregroundColor(TVTheme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(TVTheme.surfaceDim)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(TVPressButtonStyle())
            }
        }
    }

    // MARK: - 结果与状态

    @ViewBuilder
    private var resultSection: some View {
        if loading {
            TVLoadingView("正在搜索…")
                .padding(.vertical, 160)
        } else if let error {
            VStack(spacing: 26) {
                TVStatusView(
                    icon: "exclamationmark.triangle",
                    title: "搜索失败",
                    message: error,
                    expands: false
                )
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    Task { await search() }
                }
            }
            .padding(.vertical, 100)
        } else if searched, results.isEmpty {
            TVStatusView(
                icon: "magnifyingglass",
                title: "没有找到相关内容",
                message: "换个关键词试试。",
                expands: false
            )
            .padding(.vertical, 100)
        } else if !results.isEmpty {
            TVPosterGrid(items: results)
        }
    }

    // MARK: - 搜索（业务逻辑与原版一致）

    private func search() async {
        guard !query.isEmpty else { return }
        suggestions = []
        searched = true
        loading = true
        error = nil
        do {
            let result = try await CoreClient.shared.catalog(
                source: appState.selectedSource, query: query
            )
            results = result.items
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
