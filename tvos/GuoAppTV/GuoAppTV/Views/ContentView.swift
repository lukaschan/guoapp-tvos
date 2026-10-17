import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if !appState.initialized {
                VStack(spacing: 24) {
                    Text("红果鉴").font(.largeTitle)
                    if let error = appState.initializeError {
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 60)
                        Button("重试") {
                            Task { await appState.bootstrap() }
                        }
                    } else {
                        ProgressView("正在启动本地核心…")
                    }
                }
            } else {
                TabView {
                    HomeView()
                        .tabItem { Label("首页", systemImage: "house") }
                    SearchView()
                        .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    FollowingView()
                        .tabItem { Label("追剧", systemImage: "bookmark") }
                    HistoryView()
                        .tabItem { Label("最近观看", systemImage: "clock") }
                    SettingsView()
                        .tabItem { Label("设置", systemImage: "gearshape") }
                }
            }
        }
        .task {
            await appState.bootstrap()
        }
    }
}
