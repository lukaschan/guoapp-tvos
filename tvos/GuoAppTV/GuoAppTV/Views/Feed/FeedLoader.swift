import Foundation

/// 推荐流的剧单（推荐页 hero 与搜索页「大家都在看」共用）：
/// 红果用核心的推荐流——核心返回累积的整份列表，先取第一页，不够再「more」，
/// 直到够数、没有更多或请求满 4 次；其它站源用其片库第一页。按 id 去重、丢掉没有 id 的。
enum FeedLoader {
    static let hongguoSource = "hongguo"
    /// 红果首页推荐流（键见 upstream/native/core/provider_hongguo_recommendations.go）。
    static let feedKey = "home_feed"
    static let maximumRequests = 4

    static func dramas(source: String, target: Int) async throws -> [Drama] {
        let items: [Drama]
        if source == hongguoSource {
            items = try await recommendations(target: target)
        } else {
            items = try await CoreClient.shared.catalog(source: source).items
        }
        var seen = Set<String>()
        return items.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    private static func recommendations(target: Int) async throws -> [Drama] {
        var page = try await CoreClient.shared.recommendations(feed: feedKey)
        var requests = 1
        while page.hasMore, page.items.count < target, requests < maximumRequests, !Task.isCancelled {
            requests += 1
            // 「more」失败（如核心说暂时没有新的推荐）或没变多时，用已有的，不算整体失败。
            guard let next = try? await CoreClient.shared.recommendations(feed: feedKey, more: true),
                  next.items.count > page.items.count
            else { break }
            page = next
        }
        return page.items
    }
}
