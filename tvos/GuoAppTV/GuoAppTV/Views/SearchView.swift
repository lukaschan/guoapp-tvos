import SwiftUI
import UIKit

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
    /// 搜索栏容器是否聚焦（只控制放大镜图标亮度，不触发布键盘）。
    @FocusState private var searchBarFocused: Bool
    /// 是否正在输入（键盘是否弹出），由 TVSearchTextField 驱动。
    @State private var isEditing = false

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
                .padding(.horizontal, TVTheme.posterPageInset)
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
        // 可见搜索栏只是深黑底 + 白字的展示层，本身是一个可聚焦容器，
        // 点按时通过 TVSearchTextField 直接拉起键盘。
        // 不用 SwiftUI TextField：tvOS 会在焦点层给它画一个白框，
        // 焦点层在所有 App 视图之上，任何遮罩都盖不住。
        HStack(spacing: 14) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .medium))
                .foregroundColor(searchBarFocused ? TVTheme.textPrimary : TVTheme.textTertiary)
            Text(query.isEmpty ? "输入剧名、演员或关键词" : query)
                .font(.system(size: 26))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
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
                .fill(Color(white: 0.10))
        )
        .focusable()
        .focused($searchBarFocused)
        .onTapGesture { isEditing = true }
        .background {
            // 真正的输入框：1x1 透明 UITextField，永不参与焦点导航。
            TVSearchTextField(
                text: $query,
                isEditing: $isEditing,
                onSubmit: { Task { await search() } }
            )
            .frame(width: 1, height: 1)
        }
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
        .onAppear {
            // 进入搜索页默认聚焦搜索框；从详情页返回时不打扰已结果状态。
            if !searched {
                DispatchQueue.main.async { searchBarFocused = true }
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
            // 搜索海报往下挪：单独给海报加顶部间距，只动海报、不动搜索框。
            TVPosterGrid(items: results)
                .padding(.top, 12)
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

/// tvOS 搜索输入框（UIKit 封装）。
///
/// SwiftUI TextField 在 tvOS 聚焦时，系统会在焦点层画一个白框，
/// 焦点层在所有 App 视图之上，任何 SwiftUI 遮罩都盖不住。
/// 这里用 UITextField 子类（canBecomeFocused = false），
/// 永不参与焦点导航、永不画白框；由外部点按直接调 becomeFirstResponder()
/// 拉起键盘，只负责收输入与回车搜索。
private struct TVSearchTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isEditing: Bool
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> _TVSearchField {
        let field = _TVSearchField()
        field.backgroundColor = .clear
        field.borderStyle = .none
        field.textColor = .clear
        field.tintColor = .clear
        field.returnKeyType = .search
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: _TVSearchField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isEditing && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isEditing && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        private let parent: TVSearchTextField
        init(_ parent: TVSearchTextField) { self.parent = parent }

        @objc func editingChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onSubmit()
            parent.isEditing = false
            return true
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.isEditing = false
        }
    }
}

/// 永不参与 tvOS 焦点导航的 UITextField（避免系统给它画白框）。
private final class _TVSearchField: UITextField {
    override var canBecomeFocused: Bool { false }
}
