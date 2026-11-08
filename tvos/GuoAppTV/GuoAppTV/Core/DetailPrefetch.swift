import CoreGraphics
import Foundation

/// 海报焦点预取（只预取封面和详情，不 resolve、不预热播放；推荐页预告的提前加载见 HeroPlayback）：
/// - 封面：获得焦点立刻低优先级加载后面几张；
/// - 详情：焦点停 0.5 秒后取这部剧的详情，同一时间最多取一个（PrefetchSlot），
///   结果放进 3 分钟有效的 TimedCache，进详情页 / 按播放键时直接命中。
/// 缓存在这里而不在 CoreClient 里：CoreClient 的缓存保持原样。
@MainActor
final class DetailPrefetch {
    static let shared = DetailPrefetch()
    static let maxAge: TimeInterval = 180
    static let debounce: Duration = .milliseconds(500)
    static let maxEntries = 40
    /// 预取封面用的海报尺寸（与 TVPosterImage 默认一致）。
    static let posterPoints: CGFloat = 462

    private let cache = TimedCache<DramaDetail>(maxAge: DetailPrefetch.maxAge, maxEntries: DetailPrefetch.maxEntries)
    private var slot = PrefetchSlot<Drama>()
    private var pending: Task<Void, Never>?

    /// 详情：3 分钟内取过就直接用，否则向核心取并存起来（失败不存）。
    func detail(for drama: Drama) async throws -> DramaDetail {
        try await cache.value(for: drama.id) {
            try await CoreClient.shared.detail(drama: drama)
        }
    }

    /// 推荐页「接下来」一出现就把这一排的详情在核心里逐个取好，焦点停上去、开始预告时不用再等详情。
    /// 走 followCheck 而不是 detail：核心对同一站点的请求一次只发一个、间隔 250 ms，followCheck 是低优先级，
    /// 只在没有别的请求排队时才发，不会挡住正要起播的那部（实测电视上取地址被挡到 3.5 秒）；它和 detail
    /// 共用核心 5 分钟的详情缓存，之后 detail 直接命中。一次一个；任务取消（这一排换了）就停。
    func warm(_ dramas: [Drama]) async {
        for drama in dramas {
            guard !Task.isCancelled else { return }
            if await cache.cachedValue(for: drama.id) != nil { continue }
            _ = try? await CoreClient.shared.followCheck(drama: drama)
        }
    }

    func focused(_ drama: Drama, nearby: [Drama], scale: CGFloat) {
        PosterCache.shared.prefetch(nearby, maxPixelSize: ImageDownsampler.maxPixelSize(forPoints: Self.posterPoints, scale: scale))
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.prefetchDetail(drama)
        }
    }

    private func prefetchDetail(_ drama: Drama) async {
        guard await cache.cachedValue(for: drama.id) == nil, var current = slot.request(drama) else { return }
        while true {
            _ = try? await detail(for: current)
            guard let next = slot.finished() else { return }
            current = next
        }
    }
}
