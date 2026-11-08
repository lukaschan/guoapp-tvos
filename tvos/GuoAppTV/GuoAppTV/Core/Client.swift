import Foundation

enum CoreError: LocalizedError {
    case message(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .transport(let text): return text
        }
    }
}

/// Go 核心的 Swift 客户端（见 upstream/native/core/app_runtime.go 的 NativeRequest）。
///
/// 协议就是一层 JSON：请求 `{action, ...}`，响应 `{ok, data, error, code}`。
/// 核心调用是阻塞的（站源请求最长 60 秒），绝不在主线程或 Swift 协作线程池里阻塞，分两条通道（CoreRoute）：
/// - 播放类（初始化、起播、换线路、释放、取消播放）：一条串行队列，与以前一样——
///   核心里较新的播放请求会取消进行中的那个，不能并发；
/// - 读（封面、片库、详情、搜索、推荐、弹幕……）：并发队列，最多 4 个一起跑（AsyncLimiter），
///   封面和列表不再排成一队。搜索、联想词、弹幕、补全信息带核心的读会话（session + sequence）：
///   同一会话里新的请求会让核心取消旧的，被取消的那个抛 CancellationError，不当作出错显示。
/// 内存缓存（片库、分类、榜单）不变。
actor CoreClient {
    static let shared = CoreClient()

    private let queue = DispatchQueue(label: "app.duanju.core", qos: .userInitiated)
    private let readQueue = DispatchQueue(label: "app.duanju.core.read", qos: .userInitiated, attributes: .concurrent)
    private let readLimiter = AsyncLimiter(limit: 4)
    private var initialized = false
    private var playbackSequence = 0
    /// 读会话的序号：同一会话里越新越大（核心按它判断哪个是最新的）。
    private var readSequence: Int64 = 0

    /// 首页目录缓存：切标签回来时直接用缓存，避免每次重新联网拉取。
    /// 带 TTL（30 分钟），过期后重新拉取，保证内容新鲜。
    /// 只缓存浏览（query 为空），搜索结果不缓存，保证搜索实时。
    private struct CacheEntry<Value> {
        let value: Value
        let timestamp: Date
    }
    private static let cacheTTL: TimeInterval = 1800
    private var catalogCache: [String: CacheEntry<CatalogPage>] = [:]
    private var categoriesCache: [String: CacheEntry<[Category]>] = [:]
    private var rankingBoardsCache: CacheEntry<[RankingBoard]>?
    private var rankingsCache: [String: CacheEntry<RankingPage>] = [:]

    private func isFresh(_ timestamp: Date) -> Bool {
        Date().timeIntervalSince(timestamp) < Self.cacheTTL
    }

    /// 写缓存时顺带清理过期条目，避免缓存无限增长。
    private func purgeExpiredCache() {
        catalogCache = catalogCache.filter { isFresh($0.value.timestamp) }
        categoriesCache = categoriesCache.filter { isFresh($0.value.timestamp) }
        if let entry = rankingBoardsCache, !isFresh(entry.timestamp) {
            rankingBoardsCache = nil
        }
        rankingsCache = rankingsCache.filter { isFresh($0.value.timestamp) }
    }

    /// 清空首页目录缓存（首页按播放/暂停键手动刷新时调用，强制重新拉取）。
    func invalidateHomeCache() {
        catalogCache.removeAll()
        categoriesCache.removeAll()
        rankingBoardsCache = nil
        rankingsCache.removeAll()
    }

    /// session：核心读会话的键（只用于读请求）；给了就带上 session 与递增的 sequence。
    private func call(_ payload: [String: Any], session: String? = nil) async throws -> [String: Any] {
        var payload = payload
        if let session {
            readSequence += 1
            payload["session"] = session
            payload["sequence"] = readSequence
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(decoding: data, as: UTF8.self)
        let responseText: String
        switch CoreRoute.lane(for: payload["action"] as? String ?? "") {
        case .playback:
            responseText = try await Self.perform(text, on: queue)
        case .read:
            await readLimiter.acquire()
            do {
                responseText = try await Self.perform(text, on: readQueue)
            } catch {
                await readLimiter.release()
                throw error
            }
            await readLimiter.release()
        }
        guard
            let responseData = responseText.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw CoreError.transport("本地核心返回了无效数据")
        }
        guard envelope["ok"] as? Bool == true else {
            let message = envelope["error"] as? String ?? "读取失败，请重试"
            // 被同一会话里更新的请求取消：不是失败。
            if CoreRoute.isCancellation(message: message) { throw CancellationError() }
            throw CoreError.message(message)
        }
        return envelope["data"] as? [String: Any] ?? [:]
    }

    /// 在给定队列上阻塞调用核心（不占用 Swift 协作线程池）。
    private static func perform(_ text: String, on queue: DispatchQueue) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try DuanjuBridge.request(text))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func nextSequence() -> Int {
        playbackSequence += 1
        return playbackSequence
    }

    /// 初始化核心。返回核心编译时是否包含全部站源（--all-sources）。
    func initialize() async throws -> Bool {
        if initialized { return allSources }
        // tvOS 沙盒：真机上 Documents / Application Support 只读，只有
        // Caches 与 tmp 可写。核心的数据目录必须放在 Caches；代价是
        // 系统在存储不足时可能回收 Caches（缓存、海报、进度会丢失，
        // 属于 tvOS 的固有约束，下载等功能也因此不做）。
        let directory = FileManager.default.urls(
            for: .cachesDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try await call(["action": "initialize", "directory": directory.path])
        allSources = data["allSources"] as? Bool ?? false
        initialized = true
        return allSources
    }

    private(set) var allSources = false

    func categories(source: String, force: Bool = false) async throws -> [Category] {
        if !force, let entry = categoriesCache[source], isFresh(entry.timestamp) {
            return entry.value
        }
        let data = try await call(["action": "categories", "source": source, "force": force])
        let rows = data["items"] as? [Any] ?? []
        let result = rows.compactMap { ($0 as? [String: Any]).map(Category.init(dict:)) }
        purgeExpiredCache()
        categoriesCache[source] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    /// 榜单列表（Go 核心 `rankingBoards`）。
    func rankingBoards() async throws -> [RankingBoard] {
        if let entry = rankingBoardsCache, isFresh(entry.timestamp) {
            return entry.value
        }
        let data = try await call(["action": "rankingBoards"])
        let rows = data["items"] as? [Any] ?? []
        let result = rows.compactMap { ($0 as? [String: Any]).map(RankingBoard.init(dict:)) }
        purgeExpiredCache()
        rankingBoardsCache = CacheEntry(value: result, timestamp: Date())
        return result
    }

    /// 某一榜单的一页（Go 核心 `rankings`）。
    func rankings(board: String, page: Int = 1) async throws -> RankingPage {
        let key = "\(board)|\(page)"
        if let entry = rankingsCache[key], isFresh(entry.timestamp) {
            return entry.value
        }
        let data = try await call(["action": "rankings", "board": board, "page": page])
        let result = RankingPage(dict: data)
        purgeExpiredCache()
        rankingsCache[key] = CacheEntry(value: result, timestamp: Date())
        return result
    }

    /// 核心存在本地的推荐（上次取到的那份，不联网、立刻返回）：推荐页与「大家都在看」启动时先显示它。
    func cachedRecommendations(feed: String = "home_feed") async throws -> CatalogPage {
        let data = try await call(["action": "cachedRecommendations", "category": feed])
        return CatalogPage(dict: data)
    }

    /// 红果推荐流（推荐页 hero）：核心自己缓存，返回累积的整份列表；more 时再往后取一页。
    func recommendations(feed: String = "home_feed", more: Bool = false, force: Bool = false) async throws -> CatalogPage {
        let data = try await call([
            "action": "recommendations",
            "category": feed,
            "command": more ? "more" : "",
            "force": force,
        ])
        return CatalogPage(dict: data)
    }

    /// session：搜索页传 "search"，让新的关键词取消旧的；系列查找等其它调用不传。
    func catalog(
        source: String, page: Int = 1, query: String = "", category: String = "", force: Bool = false,
        session: String? = nil
    ) async throws -> CatalogPage {
        // 只缓存浏览（query 为空），搜索结果不缓存，保证搜索实时。
        let cacheKey: String? = query.isEmpty ? "\(source)|\(page)|\(category)" : nil
        if !force, let key = cacheKey, let entry = catalogCache[key], isFresh(entry.timestamp) {
            return entry.value
        }
        let data = try await call([
            "action": "catalog",
            "source": source,
            "page": page,
            "query": query,
            "category": category,
            "force": force,
        ], session: session)
        let result = CatalogPage(dict: data)
        if let key = cacheKey {
            purgeExpiredCache()
            catalogCache[key] = CacheEntry(value: result, timestamp: Date())
        }
        return result
    }

    func suggestions(query: String) async throws -> [String] {
        let data = try await call(["action": "suggestions", "query": query], session: "suggestions")
        return (data["items"] as? [Any] ?? []).compactMap { $0 as? String }
    }

    /// 海报由核心下载到本地文件并返回路径；HEIC 海报 tvOS 原生支持，无需转码。
    func coverPath(for drama: Drama) async throws -> String {
        let data = try await call(["action": "cover", "drama": drama.requestJSON(), "force": false])
        guard let path = data["path"] as? String, !path.isEmpty else {
            throw CoreError.message("海报暂不可用")
        }
        return path
    }

    func detail(drama: Drama) async throws -> DramaDetail {
        let data = try await call(["action": "detail", "drama": drama.requestJSON()])
        return DramaDetail(dict: data)
    }

    func resolve(drama: Drama, episode: Episode, quality: Int = 0) async throws -> PlaybackPlan {
        let data = try await call([
            "action": "resolve",
            "drama": drama.requestJSON(),
            "chapter": episode.requestJSON(),
            "index": episode.number,
            "quality": quality,
            "sequence": nextSequence(),
        ])
        return PlaybackPlan(dict: data)
    }

    /// 当前线路失败时向核心要下一条线路。
    func fallback(plan: PlaybackPlan) async throws -> PlaybackPlan {
        let data = try await call([
            "action": "fallback",
            "session": plan.session,
            "sequence": nextSequence(),
        ])
        return PlaybackPlan(dict: data)
    }

    func danmaku(plan: PlaybackPlan, startMs: Int, durationMs: Int) async throws -> DanmakuPage {
        // 核心要求弹幕请求带读会话（session + sequence），否则一律拒绝（「请求标记无效」）——
        // 这就是弹幕一直不出来的原因（与上游 Dart 侧 _read('danmaku', …) 一致）。
        let data = try await call([
            "action": "danmaku",
            "playbackSession": plan.session,
            "startMs": startMs,
            "durationMs": durationMs,
        ], session: "danmaku")
        return DanmakuPage(dict: data)
    }

    /// 释放一次播放会话（退出播放页时调用）。
    func release(session: String) async throws {
        guard !session.isEmpty else { return }
        _ = try await call(["action": "release", "session": session])
    }

    /// 取消正在进行的解析（与 Dart 侧行为一致，sequence 递增）。
    func cancelPlayback() async throws {
        _ = try await call(["action": "cancelPlayback", "sequence": nextSequence()])
    }
}
