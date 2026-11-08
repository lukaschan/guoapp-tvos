import Foundation

/// 应用里共用的系列查询：用核心搜索（会补齐缺失的分部）实现 SeriesCache 的搜索。
enum SeriesLookup {
    static let shared = SeriesCache<Drama>(
        search: { source, query in try? await CoreClient.shared.catalog(source: source, query: query).items },
        id: { $0.id },
        title: { $0.title },
        source: { $0.source }
    )
}
