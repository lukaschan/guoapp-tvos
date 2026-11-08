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
        // App 回到前台（tvOS 常常把 App 挂起好几天而不是重新启动）：再检查一次追剧更新。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if appState.initialized { FollowUpdateChecker.shared.checkIfDue(store: store) }
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
        let tabBarController = KeepAliveTabBarController()
        tabBarController.viewControllers = [
            // redfruit 标签结构：推荐（整屏 hero，默认页）· 剧场 · 追剧 · 搜索 · 我的。
            hosting(FeedHeroView(), title: "推荐", image: "sparkles", tag: KeepAliveTabBarController.feedTabIndex),
            hosting(HomeView(), title: "剧场", image: "film.stack", tag: 1),
            hosting(MyListView(), title: "追剧", image: "heart", tag: 2),
            hosting(SearchView(), title: "搜索", image: "magnifyingglass", tag: 3),
            hosting(SettingsView(), title: "我的", image: "person.crop.circle", tag: 4),
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

/// 标签栏容器。焦点在顶部标签栏时，遥控器的播放/暂停键走 UIKit 响应链、到不了 SwiftUI 页面
///（App 启动时焦点就在标签栏）；选中的是推荐页时把这个键转给推荐页，hero 照样能暂停 / 继续。
/// 焦点在页面里时不转发，由页面自己的 onPlayPauseCommand 处理，避免同一次按键切换两次。
final class KeepAliveTabBarController: UITabBarController, UITabBarControllerDelegate {
    static let feedTabIndex = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
    }

    /// 标签一切换就通知（推荐页据此立刻停掉 hero，不等页面消失的回调）。
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        NotificationCenter.default.post(name: .tabSelectionChanged, object: selectedIndex)
    }

    /// 已转发、不再交给系统的按键（began / ended 成对处理）。
    private var forwardedPresses = Set<UIPress>()

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let forwarded = presses.filter { $0.type == .playPause && forwardsPlayPause }
        if !forwarded.isEmpty {
            forwardedPresses.formUnion(forwarded)
            NotificationCenter.default.post(name: .feedHeroTogglePlayback, object: nil)
        }
        let rest = presses.subtracting(forwarded)
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = presses.subtracting(forwardedPresses)
        if !rest.isEmpty { super.pressesChanged(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = finish(presses)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = finish(presses)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    /// 去掉已转发的按键并返回其余的。
    private func finish(_ presses: Set<UIPress>) -> Set<UIPress> {
        let mine = presses.intersection(forwardedPresses)
        forwardedPresses.subtract(mine)
        return presses.subtracting(mine)
    }

    private var forwardsPlayPause: Bool {
        guard selectedIndex == Self.feedTabIndex,
              let focused = UIFocusSystem.focusSystem(for: self)?.focusedItem as? UIView
        else { return false }
        return focused.isDescendant(of: tabBar)
    }
}
