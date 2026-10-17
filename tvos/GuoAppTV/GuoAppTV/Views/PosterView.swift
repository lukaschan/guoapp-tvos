import SwiftUI
import UIKit

// MARK: - 海报缓存

/// 海报内存缓存：同一张海报只向核心请求一次本地文件。
actor PosterCache {
    static let shared = PosterCache()

    private var images: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for drama: Drama) async -> UIImage? {
        let key = "\(drama.id)\0\(drama.cover)"
        if let cached = images[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached {
            do {
                let path = try await CoreClient.shared.coverPath(for: drama)
                return UIImage(contentsOfFile: path)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { images[key] = result }
        return result
    }
}

// MARK: - 海报图

/// 海报图：加载、占位与淡入过渡（海报卡片 / 详情页共用）。
/// 固定 2:3 宽高比，占位态显示剧名；加载完成后淡入，不拉伸不裁切比例。
struct TVPosterImage: View {
    let drama: Drama
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Rectangle().fill(TVTheme.surface)
            if image == nil {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(TVTheme.textTertiary)
                    Text(drama.title)
                        .font(.system(size: 19))
                        .foregroundColor(TVTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 14)
                }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .aspectRatio(2 / 3, contentMode: .fit)
        .clipped()
        .animation(.easeIn(duration: 0.25), value: image != nil)
        .task(id: "\(drama.id)\0\(drama.cover)") {
            image = await PosterCache.shared.image(for: drama)
        }
    }
}

/// 裸海报：详情页左侧大图使用（卡片见 TVPosterCard）。
struct PosterView: View {
    let drama: Drama

    var body: some View {
        TVPosterImage(drama: drama)
    }
}

// MARK: - 海报卡片

/// 焦点海报卡：整卡可聚焦，进入详情页。
/// 卡面保持干净：海报 + 标题 + 可选副标题 / 进度条，无厚重容器与多余边框。
/// 焦点时轻微放大 + 柔和投影（无描边），由 tvFocusEffect 统一处理。
struct TVPosterCard: View {
    let drama: Drama
    var title: String? = nil
    var subtitle: String? = nil
    var progress: Double? = nil
    var rank: Int? = nil

    @FocusState private var focused: Bool

    var body: some View {
        NavigationLink(value: drama) {
            VStack(alignment: .leading, spacing: 12) {
                poster
                VStack(alignment: .leading, spacing: 4) {
                    Text(title ?? drama.title)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(TVTheme.textPrimary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 18))
                            .foregroundColor(TVTheme.textSecondary)
                            .lineLimit(1)
                    }
                    if let progress, progress > 0.005 {
                        TVProgressBar(fraction: progress)
                            .frame(height: 5)
                            .padding(.top, 2)
                    } else if subtitle != nil {
                        Color.clear.frame(height: 7)
                    }
                }
            }
        }
        .buttonStyle(TVPressButtonStyle())
        .focused($focused)
        .tvFocusEffect(focused: focused, scale: TVTheme.focusScale, cornerRadius: TVTheme.posterRadius, stroke: false)
        .zIndex(focused ? 1 : 0)
    }

    private var poster: some View {
        TVPosterImage(drama: drama)
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous))
            .overlay(alignment: .topLeading) { rankBadge }
    }

    /// 榜单排名角标：前三名用品牌强调色，其余低调呈现。
    @ViewBuilder
    private var rankBadge: some View {
        if let rank {
            Text(rank <= 3 ? "\(rank)" : String(format: "%02d", rank))
                .font(.system(size: rank <= 3 ? 30 : 22, weight: .heavy))
                .foregroundColor(rank <= 3 ? .white : TVTheme.textSecondary)
                .frame(width: rank <= 3 ? 52 : 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(rank <= 3 ? AnyShapeStyle(TVTheme.accentGradient) : AnyShapeStyle(Color.black.opacity(0.62)))
                )
                .padding(10)
        }
    }
}

// MARK: - 海报网格

/// 海报网格：首页目录 / 搜索结果共用。
/// `showRank` 用于榜单模式（顺序即排名）；`subtitle` / `progress` 供列表注入
/// 进度信息；`onReachEnd` 供首页无限滚动：最后一个海报出现时回调，由调用方拉下一页。
struct TVPosterGrid: View {
    let items: [Drama]
    var showRank = false
    var subtitle: ((Drama) -> String?)? = nil
    var progress: ((Drama) -> Double?)? = nil
    var onReachEnd: (() -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, drama in
                TVPosterCard(
                    drama: drama,
                    subtitle: subtitle.map { $0(drama) } ?? nil,
                    progress: progress.map { $0(drama) } ?? nil,
                    rank: showRank ? index + 1 : nil
                )
                .onAppear {
                    if drama.id == items.last?.id {
                        onReachEnd?()
                    }
                }
            }
        }
    }
}
