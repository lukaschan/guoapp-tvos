import Foundation

/// 推荐流的一批剧（hasMore：还能不能往后取）。
struct FeedBatch: Sendable {
    let dramas: [Drama]
    let hasMore: Bool
}

/// 推荐流的剧单（推荐页 hero 与搜索页「大家都在看」共用）：
/// 红果用核心的推荐流——核心返回累积的整份列表，先取第一页，不够再「more」，
/// 直到够数、没有更多或请求满 4 次；其它站源用其片库（第 1 页起，按页往后取）。按 id 去重、丢掉没有 id 的。
enum FeedLoader {
    static let hongguoSource = "hongguo"
    /// 红果首页推荐流（键见 upstream/native/core/provider_hongguo_recommendations.go）。
    static let feedKey = "home_feed"
    static let maximumRequests = 4

    /// 第一批。force：让核心丢掉上次存下的推荐、从头取一份新的（每次启动 App 时用）；
    /// 刷新失败（如离线）时退回核心存着的那份。
    static func dramas(source: String, target: Int, force: Bool = false) async throws -> FeedBatch {
        guard source == hongguoSource else {
            let page = try await CoreClient.shared.catalog(source: source)
            return FeedBatch(dramas: unique(page.items), hasMore: page.hasMore)
        }
        var page: CatalogPage
        do {
            page = try await CoreClient.shared.recommendations(feed: feedKey, force: force)
        } catch {
            guard force, !Task.isCancelled else { throw error }
            page = try await CoreClient.shared.recommendations(feed: feedKey)
        }
        var requests = 1
        while page.hasMore, page.items.count < target, requests < maximumRequests, !Task.isCancelled {
            requests += 1
            // 「more」失败（如核心说暂时没有新的推荐）时用已有的，不算整体失败；
            // 偶尔空一批（没变多）不算到底，在 4 次请求以内接着取。
            guard let next = try? await CoreClient.shared.recommendations(feed: feedKey, more: true) else { break }
            if next.items.count > page.items.count { page = next }
        }
        return FeedBatch(dramas: unique(page.items), hasMore: page.hasMore)
    }

    /// 核心存着的推荐（不联网、立刻返回）：红果才有；取不到或其它站源时为空。
    static func cached(source: String) async -> [Drama] {
        guard source == hongguoSource,
              let page = try? await CoreClient.shared.cachedRecommendations(feed: feedKey)
        else { return [] }
        return unique(page.items)
    }

    /// 往后再取一批：红果用 more（核心返回累积的整份列表，由 FeedPaging.merge 接上新的部分）；
    /// 其它站源取片库的第 page 页。
    static func more(source: String, page: Int) async throws -> FeedBatch {
        let result: CatalogPage
        if source == hongguoSource {
            result = try await CoreClient.shared.recommendations(feed: feedKey, more: true)
        } else {
            result = try await CoreClient.shared.catalog(source: source, page: page)
        }
        return FeedBatch(dramas: unique(result.items), hasMore: result.hasMore)
    }

    private static func unique(_ items: [Drama]) -> [Drama] {
        var seen = Set<String>()
        return items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
}
