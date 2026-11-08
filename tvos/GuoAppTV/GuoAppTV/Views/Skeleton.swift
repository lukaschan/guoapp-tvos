import SwiftUI

// 加载骨架（redfruit 的 DesignSystem/Components/Skeleton.swift）：形状照着真实布局，
// 一层柔和扫光（Shimmer.period 秒一次），开了「减弱动态效果」时静止；骨架里没有可聚焦的东西。

private let skeletonFill = TVTheme.textPrimary.opacity(0.08)

/// 一块占位：内容还在加载时占住它的形状。
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 10

    init(width: CGFloat?, height: CGFloat, cornerRadius: CGFloat = 10) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(skeletonFill)
            .frame(width: width, height: height)
    }
}

/// 扫过骨架的一道柔光：clear → 7 % 暖白 → clear，宽 40 %，从 −1 扫到 1.2 倍宽。
private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if Shimmer.animates(reduceMotion: reduceMotion) {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, TVTheme.textPrimary.opacity(0.07), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.4)
                        .offset(x: phase * proxy.size.width)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard Shimmer.animates(reduceMotion: reduceMotion) else { return }
                withAnimation(.linear(duration: Shimmer.period).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在加载")
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

/// 海报网格的骨架（搜索、剧场）：可选的标题块 + 与 TVPosterGrid 相同列宽的 2:3 海报块和标题块。
struct PosterGridSkeleton: View {
    var count = 14
    var showsTitle = true
    /// 嵌在别的骨架里时由外层统一扫光，避免叠两层。
    var shimmers = true

    init(count: Int = 14, showsTitle: Bool = true, shimmers: Bool = true) {
        self.count = count
        self.showsTitle = showsTitle
        self.shimmers = shimmers
    }

    var body: some View {
        let grid = VStack(alignment: .leading, spacing: 24) {
            if showsTitle {
                SkeletonBlock(width: 220, height: 38, cornerRadius: 8)
            }
            LazyVGrid(columns: TVTheme.posterColumns(), alignment: .leading, spacing: 32) {
                ForEach(0..<count, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 12) {
                        RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous)
                            .fill(skeletonFill)
                            .aspectRatio(2 / 3, contentMode: .fit)
                        SkeletonBlock(width: nil, height: 22, cornerRadius: 6)
                            .scaleEffect(x: 0.7, anchor: .leading)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        if shimmers {
            grid.shimmering()
        } else {
            grid
        }
    }
}

/// 剧场首屏骨架：「今日主推」横幅块 + 海报网格（分类行是真实的，已经显示在上面）。
struct TheaterSkeleton: View {
    /// 与 HomeView 的横幅内缩一致：离屏幕边缘 80 pt。
    private static let bannerInset: CGFloat = 80 - TVTheme.posterPageInset

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SkeletonBlock(width: nil, height: 340, cornerRadius: 24)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Self.bannerInset)
            PosterGridSkeleton(count: 14, showsTitle: false, shimmers: false)
        }
        .shimmering()
    }
}
