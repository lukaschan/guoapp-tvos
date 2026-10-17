import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !appState.initialized {
                launchScreen
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

    /// 启动页：品牌标识 + 核心启动状态；失败时给出重试入口。
    private var launchScreen: some View {
        VStack(spacing: 28) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(TVTheme.accentGradient)
                    .frame(width: 104, height: 104)
                    .shadow(color: TVTheme.accent.opacity(0.35), radius: 30, y: 12)
                Image(systemName: "play.fill")
                    .font(.system(size: 46, weight: .bold))
                    .foregroundColor(.white)
            }
            Text("红果鉴")
                .font(.system(size: 48, weight: .bold))
            Group {
                if let error = appState.initializeError {
                    VStack(spacing: 22) {
                        Text(error)
                            .font(.system(size: 22))
                            .foregroundColor(TVTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 640)
                        TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                            Task { await appState.bootstrap() }
                        }
                    }
                } else {
                    ProgressView("正在启动本地核心…")
                }
            }
            .frame(height: 130)
        }
        .padding(48)
    }
}
