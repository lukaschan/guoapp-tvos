import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: Store

    var body: some View {
        ZStack {
            TVTheme.background.ignoresSafeArea()
            if !appState.initialized {
                launchScreen
            } else {
                // 用 UITabBarController 保持所有标签页存活：切标签不销毁视图，
                // @State（滚动位置、已加载页数、选中分类/榜单）都保留，切回来秒开。
                // SwiftUI 的 TabView 切走时会销毁视图，故改用本容器。
                KeepAliveTabView(appState: appState, store: store)
                    .ignoresSafeArea()
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
                    .foregroundColor(TVTheme.textPrimary)
            }
            Text(tvAppDisplayName)
                .font(.system(size: 48, weight: .bold))
            Group {
                if let error = appState.initializeError {
                    VStack(spacing: 22) {
                        Text(error)
                            .font(.system(size: TVTheme.TextSize.body))
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

/// 保持标签页存活的容器：UIKit 的 UITabBarController 切标签不销毁子页面，
/// 每个标签页包一层 UIHostingController，SwiftUI 视图的 @State 在切标签时保留。
struct KeepAliveTabView: UIViewControllerRepresentable {
    var appState: AppState
    var store: Store

    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [
            // redfruit 标签结构；推荐（首页大图）在第二阶段加入并成为默认页。
            hosting(HomeView(), title: "剧场", image: "film.stack", tag: 0),
            hosting(MyListView(), title: "追剧", image: "heart", tag: 1),
            hosting(SearchView(), title: "搜索", image: "magnifyingglass", tag: 2),
            hosting(SettingsView(), title: "我的", image: "person.crop.circle", tag: 3),
        ]
        return tabBarController
    }

    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        // 子页面只在 makeUIViewController 创建一次，此处不重建，避免丢状态。
    }

    private func hosting<V: View>(_ content: V, title: String, image: String, tag: Int) -> UIViewController {
        // 每个标签页显式注入 AppState 与 Store：嵌套的 UIHostingController 在 tvOS 16 上不保证继承 SwiftUI 环境。
        let controller = UIHostingController(rootView: content.environmentObject(appState).environmentObject(store))
        controller.view.backgroundColor = UIColor(TVTheme.background)
        controller.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), tag: tag)
        return controller
    }
}
