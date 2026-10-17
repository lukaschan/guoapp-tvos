import Foundation

// MARK: - 容错解析

private func stringValue(_ dict: [String: Any], _ key: String) -> String {
    dict[key] as? String ?? ""
}

private func intValue(_ dict: [String: Any], _ key: String) -> Int {
    if let number = dict[key] as? NSNumber { return number.intValue }
    if let text = dict[key] as? String, let number = Int(text) { return number }
    return 0
}

private func stringList(_ dict: [String: Any], _ key: String) -> [String] {
    (dict[key] as? [Any] ?? []).compactMap { $0 as? String }
}

// MARK: - 剧

struct Drama: Identifiable, Hashable, Codable {
    var id: String
    var source: String
    var sourceId: String
    var title: String
    var description: String
    var cover: String
    var episodes: Int
    var category: String
    var vip: Bool?
    var heat: String
    var views: String
    var onlineDate: String
    var tags: [String]
    var releaseStatus: String

    var releaseLabel: String {
        switch releaseStatus {
        case "finished", "completed": return "已完结"
        case "ongoing": return "连载中"
        default: return ""
        }
    }

    init(dict: [String: Any]) {
        id = stringValue(dict, "id")
        source = stringValue(dict, "source").isEmpty ? "hongguo" : stringValue(dict, "source")
        sourceId = stringValue(dict, "sourceId")
        title = stringValue(dict, "title").isEmpty ? "短剧" : stringValue(dict, "title")
        description = stringValue(dict, "description")
        cover = stringValue(dict, "cover")
        episodes = intValue(dict, "episodes")
        category = stringValue(dict, "category")
        vip = dict["vip"] as? Bool
        heat = dict["heat"].map { "\($0)" } ?? ""
        views = dict["views"].map { "\($0)" } ?? ""
        onlineDate = stringValue(dict, "onlineDate")
        tags = stringList(dict, "tags")
        releaseStatus = stringValue(dict, "releaseStatus")
    }

    /// 发给 Go 核心的 drama 结构，与 Dart 侧 Drama.toJson 对齐。
    func requestJSON() -> [String: Any] {
        var json: [String: Any] = [
            "metadataSchema": 1,
            "id": id,
            "source": source,
            "sourceId": sourceId,
            "title": title,
            "description": description,
            "cover": cover,
            "episodes": episodes,
            "category": category,
            "heat": heat,
            "views": views,
            "onlineDate": onlineDate,
            "tags": tags,
            "releaseStatus": releaseStatus,
        ]
        if let vip { json["vip"] = vip }
        return json
    }
}

// MARK: - 分集

struct Episode: Identifiable {
    let raw: [String: Any]

    var id: String { stringValue(raw, "id").isEmpty ? "ep-\(number)" : stringValue(raw, "id") }
    var title: String {
        let value = stringValue(raw, "title")
        return value.isEmpty ? "第\(number)集" : value
    }
    var number: Int {
        let value = intValue(raw, "currentEpisode")
        return value > 0 ? value : 0
    }
    var vip: Bool { raw["vip"] as? Bool == true }

    /// 分集序号（从 1 开始）；核心返回的 currentEpisode 为空时用列表位置兜底。
    init(raw: [String: Any], fallback: Int) {
        var copy = raw
        if intValue(copy, "currentEpisode") <= 0 {
            copy["currentEpisode"] = fallback
        }
        self.raw = copy
    }
}

// MARK: - 详情 / 目录 / 分类

struct DramaDetail {
    let drama: Drama
    let episodes: [Episode]
    let warning: String

    init(dict: [String: Any]) {
        drama = Drama(dict: dict["drama"] as? [String: Any] ?? [:])
        let rows = dict["chapters"] as? [Any] ?? []
        episodes = rows.enumerated().compactMap { index, row in
            guard let row = row as? [String: Any] else { return nil }
            return Episode(raw: row, fallback: index + 1)
        }
        warning = stringValue(dict, "warning")
    }
}

struct CatalogPage {
    let items: [Drama]
    let hasMore: Bool
    let page: Int
    let warning: String
    let fresh: Bool

    init(dict: [String: Any]) {
        let rows = dict["items"] as? [Any] ?? []
        items = rows.compactMap { ($0 as? [String: Any]).map(Drama.init(dict:)) }
        hasMore = dict["hasMore"] as? Bool == true
        warning = stringValue(dict, "warning")
        let page = intValue(dict, "page")
        self.page = page > 0 ? page : 1
        fresh = dict["fresh"] as? Bool == true
    }
}

struct Category: Identifiable, Hashable {
    static let all = Category(id: "", name: "全部")
    let id: String
    let name: String

    init(dict: [String: Any]) {
        id = stringValue(dict, "id")
        let name = stringValue(dict, "name")
        self.name = name.isEmpty ? "全部" : name
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - 播放计划 / 弹幕

struct PlaybackPlan {
    let url: String
    let headers: [String: String]
    let quality: Int
    let qualities: [Int]
    let session: String
    let danmakuId: String
    let routeIndex: Int
    let routeCount: Int
    let local: Bool
    let expiresAt: Int
    let decryptionKey: String
    /// CENC 解密密钥（hex），红果等加密源才有；传给 mpv 的 decryption-key 选项。

    var hasAlternative: Bool { !session.isEmpty && routeIndex + 1 < routeCount }

    init(dict: [String: Any]) {
        url = stringValue(dict, "url")
        var headers: [String: String] = [:]
        for (key, value) in dict["headers"] as? [String: Any] ?? [:] {
            headers[key] = "\(value)"
        }
        self.headers = headers
        quality = intValue(dict, "quality")
        let qualities = (dict["qualities"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        self.qualities = Array(Set(qualities)).sorted(by: >)
        session = stringValue(dict, "session")
        danmakuId = stringValue(dict, "danmakuId")
        routeIndex = intValue(dict, "routeIndex")
        let routeCount = intValue(dict, "routeCount")
        self.routeCount = routeCount > 0 ? routeCount : 1
        local = dict["local"] as? Bool == true
        expiresAt = intValue(dict, "expiresAt")
        decryptionKey = stringValue(dict, "decryptionKey")
    }
}

struct DanmakuItem: Identifiable {
    let id: String
    let text: String
    let timeMs: Int
}

struct DanmakuPage {
    let episodeId: String
    let startMs: Int
    let nextMs: Int
    let items: [DanmakuItem]

    init(dict: [String: Any]) {
        episodeId = stringValue(dict, "episodeId")
        startMs = intValue(dict, "startMs")
        nextMs = intValue(dict, "nextMs")
        let rows = dict["items"] as? [Any] ?? []
        items = rows.prefix(90).compactMap { row in
            guard let row = row as? [String: Any] else { return nil }
            return DanmakuItem(
                id: stringValue(row, "id"),
                text: stringValue(row, "text"),
                timeMs: intValue(row, "timeMs")
            )
        }
    }
}

// MARK: - 站源

struct SourceSite: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String

    /// 与 Dart 侧 SourceSite.knownValues 对齐；站源列表由核心的 allSources 编译开关决定。
    static func available(allSources: Bool) -> [SourceSite] {
        let hongguo = SourceSite(id: "hongguo", name: "红果", description: "短剧 · 漫剧 · AI 剧")
        guard allSources else { return [hongguo] }
        return [
            hongguo,
            SourceSite(id: "dsd", name: "帝果", description: "分类视频 · 在线搜索"),
            SourceSite(id: "sorani", name: "青空", description: "番剧 · 剧场动画 · 特摄"),
            SourceSite(id: "guipian", name: "鬼片", description: "鬼片 · 电视剧 · 动漫"),
            SourceSite(id: "hanxiaoquan", name: "韩小圈", description: "韩剧 · 韩国电影 · 综艺 · 动漫"),
            SourceSite(id: "huangdou", name: "黄豆", description: "精选短剧"),
            SourceSite(id: "huangju", name: "剧果", description: "热门 · 最新 · 分类短剧"),
            SourceSite(id: "yeguo", name: "野果", description: "分类短剧 · 在线搜索"),
            SourceSite(id: "huangguo-video", name: "黄果视频", description: "视频剧集"),
            SourceSite(id: "huangguoai", name: "黄果 AI", description: "AI 短剧"),
            SourceSite(id: "cloudfront", name: "黄果旧版", description: "旧 API 剧库"),
        ]
    }
}

/// 榜单：与 Dart 侧 RankingBoard 对齐，Go 核心 `rankingBoards` 返回。
struct RankingBoard: Identifiable, Hashable {
    let id: String
    let source: String
    let name: String
    let description: String

    init(dict: [String: Any]) {
        id = stringValue(dict, "id")
        source = stringValue(dict, "source")
        name = stringValue(dict, "name")
        description = stringValue(dict, "description")
    }
}

/// 一页榜单：items 里每个元素是 `{rank, drama, metric}`，drama 与目录里的
/// Drama 同一结构；顺序即排名，rank 不单独存（界面按顺序展示）。
struct RankingPage {
    let items: [Drama]
    let page: Int
    let hasMore: Bool
    let warning: String

    init(dict: [String: Any]) {
        let rows = dict["items"] as? [Any] ?? []
        items = rows.compactMap { row in
            guard let row = row as? [String: Any],
                  let dramaDict = row["drama"] as? [String: Any]
            else { return nil }
            return Drama(dict: dramaDict)
        }
        let page = intValue(dict, "page")
        self.page = page > 0 ? page : 1
        hasMore = dict["hasMore"] as? Bool == true
        warning = stringValue(dict, "warning")
    }
}
