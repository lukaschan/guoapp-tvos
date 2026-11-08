import Foundation

/// 搜索页的文案（与 redfruit 一致）。
enum SearchCopy {
    /// 还没输入时显示的推荐：推荐流的前 14 部。
    static let popularTitle = "大家都在看"
    static let popularCount = 14
    static let notFoundHint = "换个关键词试试，比如剧名里的几个字或「都市」「古装」"

    /// 结果标题：数的是搜到的剧（系列卡片上另有「共 N 部」）。
    static func found(_ count: Int) -> String {
        "找到 \(count) 部短剧"
    }

    static func notFound(_ query: String) -> String {
        "没有找到「\(query)」"
    }
}
