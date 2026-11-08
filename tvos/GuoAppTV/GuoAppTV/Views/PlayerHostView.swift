import SwiftUI
import UIKit

/// mpv 的画面：建好容器视图后交给 PlayerController 绑定 Metal 层。
/// 全屏播放页与推荐页的 hero 共用（各自持有自己的 PlayerController）。
struct PlayerHostView: UIViewRepresentable {
    let controller: PlayerController

    init(controller: PlayerController) {
        self.controller = controller
    }

    func makeUIView(context: Context) -> PlayerHostContainerView {
        let view = PlayerHostContainerView()
        controller.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PlayerHostContainerView, context: Context) {}
}
