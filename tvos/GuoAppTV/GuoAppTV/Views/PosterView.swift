import SwiftUI
import UIKit

// MARK: - 海报缓存

/// 海报内存缓存：封面文件由核心下载到本地，这里按显示尺寸缩小解码（ImageDownsampler），
/// 解码后的位图放进按像素占用计费的 NSCache（上限 96 MB，超出自动淘汰）；
/// 同一张图同一尺寸只解码一次，并发请求共用一次。
actor PosterCache {
    static let shared = PosterCache()
    private static let memoryLimit = 96 * 1024 * 1024

    private let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = PosterCache.memoryLimit
        return cache
    }()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for drama: Drama, maxPixelSize: Int) async -> UIImage? {
        let key = Self.key(drama, maxPixelSize)
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached { () -> UIImage? in
            guard let path = try? await CoreClient.shared.coverPath(for: drama),
                  let image = ImageDownsampler.downsample(fileURL: URL(fileURLWithPath: path), maxPixelSize: maxPixelSize)
            else { return nil }
            return UIImage(cgImage: image)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result, let bitmap = result.cgImage {
            memory.setObject(result, forKey: key as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        }
        return result
    }

    /// 预先加载即将出现的封面（低优先级、依次加载、失败忽略）；已在内存或正在加载的跳过。
    nonisolated func prefetch(_ dramas: [Drama], maxPixelSize: Int) {
        guard !dramas.isEmpty else { return }
        Task(priority: .utility) {
            for drama in dramas {
                _ = await image(for: drama, maxPixelSize: maxPixelSize)
            }
        }
    }

    private static func key(_ drama: Drama, _ maxPixelSize: Int) -> String {
        "\(drama.id)\0\(drama.cover)\0\(maxPixelSize)"
    }
}

// MARK: - 海报图

/// 海报图：加载、占位与淡入过渡（海报卡片 / 详情页共用）。
/// 固定 2:3 宽高比，占位态显示剧名；加载完成后淡入，不拉伸不裁切比例。
struct TVPosterImage: View {
    let drama: Drama
    /// 显示时的最长边（pt）：默认按海报 420 高 × 焦点放大 1.10；详情页海报 300×450 也在此内。
    var maxPointSize: CGFloat = 462
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Rectangle().fill(TVTheme.surface)
            if image == nil {
                VStack(spacing: 10) {
                    Image(systemName: "photo")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundColor(TVTheme.textTertiary)
                    Text(drama.title)
                        .font(.system(size: TVTheme.TextSize.caption2))
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
        .task(id: "\(drama.id)\0\(drama.cover)\0\(pixelSize)") {
            image = await PosterCache.shared.image(for: drama, maxPixelSize: pixelSize)
        }
    }

    private var pixelSize: Int {
        ImageDownsampler.maxPixelSize(forPoints: maxPointSize, scale: displayScale)
    }
}

/// 裸海报：详情页左侧大图使用（卡片见 TVPosterCard）。
struct PosterView: View {
    let drama: Drama

    var body: some View {
        TVPosterImage(drama: drama)
    }
}

// MARK: - 焦点预取

/// 海报获得焦点时调用（网格据此预取后面的封面和这部剧的详情）。按 key 判等，
/// 内容不变时海报不会因为这个环境值重绘。
struct PosterFocusAction: Equatable, Sendable {
    let key: Int
    let perform: @MainActor @Sendable (Drama) -> Void

    static func == (lhs: PosterFocusAction, rhs: PosterFocusAction) -> Bool {
        lhs.key == rhs.key
    }
}

private struct PosterFocusActionKey: EnvironmentKey {
    static let defaultValue: PosterFocusAction? = nil
}

extension EnvironmentValues {
    var onPosterFocus: PosterFocusAction? {
        get { self[PosterFocusActionKey.self] }
        set { self[PosterFocusActionKey.self] = newValue }
    }
}

extension View {
    /// 里面的海报获得焦点时：预取它后面几张的封面，焦点停住后预取这部剧的详情（DetailPrefetch）。
    func prefetchesOnPosterFocus(_ items: [Drama]) -> some View {
        modifier(PosterFocusPrefetch(items: items))
    }
}

private struct PosterFocusPrefetch: ViewModifier {
    let items: [Drama]
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let items = items
        let scale = displayScale
        return content.environment(\.onPosterFocus, PosterFocusAction(key: items.map(\.id).hashValue) { drama in
            DetailPrefetch.shared.focused(
                drama,
                nearby: PosterPrefetchPlan.items(after: drama.id, in: items, id: \.id),
                scale: scale
            )
        })
    }
}

// MARK: - 海报卡片

/// 焦点海报卡：整卡可聚焦，进入详情页。
/// 卡面保持干净：海报 + 标题 + 可选副标题 / 进度条，无厚重容器与多余边框。
/// 焦点时只有轻微放大 + 柔和投影、无描边、无系统白框：
/// 自定义 ButtonStyle 压住 tvOS 系统默认焦点白框，tvFocusEffect 关掉描边。
struct TVPosterCard: View {
    let drama: Drama
    var title: String? = nil
    var subtitle: String? = nil
    var progress: Double? = nil
    var rank: Int? = nil
    /// 右上角角标（系列卡片的「共 N 部」）。
    var badge: String? = nil
    var badgeColor: Color = TVTheme.accent
    /// 点按进入哪部剧的详情；默认就是海报这部（系列卡片进入最近看的那一部）。
    var linkValue: Drama? = nil
    /// 按播放键后正在取详情：海报上叠加载圈。
    var isLoading = false
    /// 设置时点按调用它而不是导航链接：卡片放在独立的 UIHostingController 里（如搜索结果）时，
    /// 那里没有外层的 NavigationStack，导航链接点了没反应，由调用方自己推详情页。
    var onSelect: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @Environment(\.onPosterFocus) private var onPosterFocus

    var body: some View {
        Group {
            if let onSelect {
                Button(action: onSelect) { card }
            } else {
                NavigationLink(value: linkValue ?? drama) { card }
            }
        }
        .buttonStyle(TVPressButtonStyle())
        .focused($focused)
        .tvFocusEffect(focused: focused, scale: TVTheme.focusScale, cornerRadius: TVTheme.posterRadius, stroke: false)
        .zIndex(focused ? 1 : 0)
        .onChange(of: focused) { isFocused in
            // 系列卡片预取的是点进去的那一部。
            if isFocused { onPosterFocus?.perform(linkValue ?? drama) }
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            poster
            VStack(alignment: .leading, spacing: 4) {
                Text(title ?? drama.title)
                    .font(.system(size: TVTheme.TextSize.caption, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: TVTheme.TextSize.caption2))
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

    private var poster: some View {
        TVPosterImage(drama: drama)
            .clipShape(RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous))
            .overlay(alignment: .topLeading) { rankBadge }
            .overlay(alignment: .topTrailing) { cornerBadge }
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.45)
                        ProgressView()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous))
                }
            }
    }

    /// 右上角角标：系列卡片显示「共 N 部」等；没有别的角标时显示总集数「80集」（redfruit 样式）。
    @ViewBuilder
    private var cornerBadge: some View {
        if let badge {
            cornerLabel(badge, fill: badgeColor)
        } else if drama.episodes > 0 {
            cornerLabel("\(drama.episodes)集", fill: Color.black.opacity(0.62))
        }
    }

    private func cornerLabel(_ text: String, fill: Color) -> some View {
        Text(text)
            .font(.system(size: TVTheme.TextSize.caption2, weight: .bold))
            .foregroundColor(TVTheme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
            .padding(10)
    }

    /// 榜单排名角标：前三名用品牌强调色，其余低调呈现。
    @ViewBuilder
    private var rankBadge: some View {
        if let rank {
            Text(rank <= 3 ? "\(rank)" : String(format: "%02d", rank))
                .font(.system(size: rank <= 3 ? 30 : 22, weight: .heavy))
                .foregroundColor(rank <= 3 ? TVTheme.textPrimary : TVTheme.textSecondary)
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
    /// 海报上按播放键：直接播放（继续观看或从第 1 集开始）。
    var onPlay: ((Drama) -> Void)? = nil
    /// 正在取详情准备播放的剧（海报上显示加载圈）。
    var loadingID: String? = nil
    /// 第一张海报的名次（剧场把榜首放进「今日主推」后，网格从第 2 名排起）。
    var firstRank = 1

    var body: some View {
        LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, drama in
                TVPosterCard(
                    drama: drama,
                    subtitle: subtitle.map { $0(drama) } ?? nil,
                    progress: progress.map { $0(drama) } ?? nil,
                    rank: showRank ? index + firstRank : nil,
                    isLoading: drama.id == loadingID
                )
                .onAppear {
                    if drama.id == items.last?.id {
                        onReachEnd?()
                    }
                }
                .onPlayPauseCommand(perform: onPlay.map { play in { play(drama) } })
            }
        }
        .prefetchesOnPosterFocus(items)
    }
}
