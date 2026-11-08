import Foundation

/// 「大家都在看」显示哪种状态：有海报就显示海报（重新加载时也是），取回 0 部单独给提示和重试。
enum PopularState: Equatable, Sendable {
    case posters
    case loading
    case failed(String)
    case empty

    static func make(count: Int, loading: Bool, error: String?) -> PopularState {
        if count > 0 { return .posters }
        if loading { return .loading }
        if let error { return .failed(error) }
        return .empty
    }
}

/// 搜索页的文案（与 redfruit 一致）。
enum SearchCopy {
    /// 还没输入时显示的推荐：推荐流的前 14 部。
    static let popularTitle = "大家都在看"
    static let popularCount = 14

    /// 核心存着的推荐够 14 部才直接用；刚开始刷新时可能只有一两部，那就照常去取。
    static func cachedIsEnough(_ count: Int) -> Bool {
        count >= popularCount
    }
    static let notFoundHint = "换个关键词试试，比如剧名里的几个字或「都市」「古装」"
    static let popularEmptyTitle = "暂时没有可播放的短剧"
    static let popularEmptyHint = "稍后再来看看吧"

    /// 结果标题：数的是搜到的剧（系列卡片上另有「共 N 部」）。
    static func found(_ count: Int) -> String {
        "找到 \(count) 部短剧"
    }

    static func notFound(_ query: String) -> String {
        "没有找到「\(query)」"
    }
}
