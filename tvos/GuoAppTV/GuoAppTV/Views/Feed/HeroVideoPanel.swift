import SwiftUI
import UIKit

/// 推荐页 hero 的画面层（1920×1080）：
/// - 氛围底：同一张封面放大 1.25 倍、模糊 60、压暗 28 %（mpv 只有一个渲染层，做不了第二路模糊视频）；
/// - 视频面板：竖屏贴右整高 608×1080、左右边缘羽化 140 pt；横屏铺满整屏、不羽化（播放器填满画面，看不到边框）；
///   出画面前先显示封面；
/// - 左侧压一层背景色渐变（竖屏到面板左缘，横屏到 1400 pt），底部再压一层，给信息栏与「接下来」留出可读的底。
struct HeroVideoPanel<Video: View>: View {
    let drama: Drama
    let videoSize: CGSize?
    let showsVideo: Bool
    @ViewBuilder let video: Video

    static var canvas: CGSize { CGSize(width: 1920, height: 1080) }
    private static var feather: CGFloat { 140 }
    /// 横屏铺满时左侧压暗的宽度（信息栏到 1120 pt，再往右渐隐）。
    private static var landscapeScrim: CGFloat { 1400 }

    var body: some View {
        let layout = HeroLayout.panel(videoSize: videoSize)
        ZStack(alignment: .topLeading) {
            HeroCoverImage(drama: drama, maxPointSize: 540)
                .frame(width: Self.canvas.width, height: Self.canvas.height)
                .scaleEffect(1.25)
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.28))
            panel(frame: layout.frame, vertical: layout.vertical)
                .offset(x: layout.frame.minX, y: layout.frame.minY)
            leftScrim(width: layout.vertical ? layout.frame.minX : Self.landscapeScrim)
            bottomScrim
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height, alignment: .topLeading)
        .clipped()
        .animation(.easeInOut(duration: 0.35), value: layout.vertical)
    }

    private func panel(frame: CGRect, vertical: Bool) -> some View {
        ZStack {
            video
            HeroCoverImage(drama: drama)
                .opacity(showsVideo ? 0 : 1)
                .animation(.easeOut(duration: 0.4), value: showsVideo)
        }
        .frame(width: frame.width, height: frame.height)
        .clipped()
        .mask(EdgeFade(horizontal: true, fraction: vertical ? Self.feather / frame.width : 0))
    }

    /// 背景色 92 % → 72 % 处 70 % → 面板左缘透明。
    private func leftScrim(width: CGFloat) -> some View {
        LinearGradient(
            stops: [
                .init(color: TVTheme.background.opacity(0.92), location: 0),
                .init(color: TVTheme.background.opacity(0.70), location: 0.72),
                .init(color: TVTheme.background.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: width, height: Self.canvas.height)
    }

    private var bottomScrim: some View {
        LinearGradient(
            colors: [TVTheme.background.opacity(0), TVTheme.background.opacity(0.85)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: Self.canvas.width, height: 360)
        .offset(y: Self.canvas.height - 360)
    }
}

/// 两端羽化的遮罩；fraction 为每端渐变占的比例，0 表示不羽化。
private struct EdgeFade: View {
    let horizontal: Bool
    let fraction: CGFloat

    var body: some View {
        if fraction <= 0 {
            Color.black
        } else {
            let edge = min(fraction, 0.5)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: edge),
                    .init(color: .black, location: 1 - edge),
                    .init(color: .clear, location: 1),
                ],
                startPoint: horizontal ? .leading : .top,
                endPoint: horizontal ? .trailing : .bottom
            )
        }
    }
}

/// 铺满给定区域的封面（裁切、不留边）；与海报共用 PosterCache。
struct HeroCoverImage: View {
    let drama: Drama
    /// 显示时的最长边（pt）：hero 面板 1080；模糊的氛围底用 540 就够。
    var maxPointSize: CGFloat = 1080
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        TVTheme.surfaceDim
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .animation(.easeIn(duration: 0.25), value: image != nil)
            .task(id: "\(drama.id)\0\(drama.cover)\0\(pixelSize)") {
                image = await PosterCache.shared.image(for: drama, maxPixelSize: pixelSize)
            }
    }

    private var pixelSize: Int {
        ImageDownsampler.maxPixelSize(forPoints: maxPointSize, scale: displayScale)
    }
}
