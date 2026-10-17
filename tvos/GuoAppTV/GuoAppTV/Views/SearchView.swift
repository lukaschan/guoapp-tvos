import SwiftUI

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
            VStack(alignment: .leading, spacing: 20) {
                TextField("搜索剧名", text: $query)
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
                if !searched, !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(suggestions.prefix(8), id: \.self) { suggestion in
                            Button(suggestion) {
                                query = suggestion
                                Task { await search() }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                if loading {
                    Spacer()
                    HStack { Spacer(); ProgressView("正在搜索…"); Spacer() }
                    Spacer()
                } else if let error {
                    Spacer()
                    Text(error).foregroundColor(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                } else if searched, results.isEmpty {
                    Spacer()
                    Text("没有找到相关内容").foregroundColor(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    PosterGrid(items: results)
                }
            }
            .padding(.horizontal, 48)
            .navigationTitle("搜索")
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
        }
    }

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
