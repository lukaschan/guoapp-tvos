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

/// Go 核心的 Swift 客户端（见 native/core/app_runtime.go 的 NativeRequest）。
///
/// 协议就是一层 JSON：请求 `{action, ...}`，响应 `{ok, data, error, code}`。
/// 核心调用是阻塞的（站源请求最长 60 秒），所以统一走一条专用串行队列，
/// 绝不在主线程或 Swift 协作线程池里阻塞；actor 保证调用之间不交错。
actor CoreClient {
    static let shared = CoreClient()

    private let queue = DispatchQueue(label: "app.duanju.core", qos: .userInitiated)
    private var initialized = false
    private var playbackSequence = 0

    private func call(_ payload: [String: Any]) async throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let text = String(decoding: data, as: UTF8.self)
        let responseText = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try DuanjuBridge.request(text))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        guard
            let responseData = responseText.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        else {
            throw CoreError.transport("本地核心返回了无效数据")
        }
        guard envelope["ok"] as? Bool == true else {
            throw CoreError.message(envelope["error"] as? String ?? "读取失败，请重试")
        }
        return envelope["data"] as? [String: Any] ?? [:]
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
        let data = try await call(["action": "categories", "source": source, "force": force])
        let rows = data["items"] as? [Any] ?? []
        return rows.compactMap { ($0 as? [String: Any]).map(Category.init(dict:)) }
    }

    /// 榜单列表（Go 核心 `rankingBoards`）。
    func rankingBoards() async throws -> [RankingBoard] {
        let data = try await call(["action": "rankingBoards"])
        let rows = data["items"] as? [Any] ?? []
        return rows.compactMap { ($0 as? [String: Any]).map(RankingBoard.init(dict:)) }
    }

    /// 某一榜单的一页（Go 核心 `rankings`）。
    func rankings(board: String, page: Int = 1) async throws -> RankingPage {
        let data = try await call(["action": "rankings", "board": board, "page": page])
        return RankingPage(dict: data)
    }

    func catalog(
        source: String, page: Int = 1, query: String = "", category: String = "", force: Bool = false
    ) async throws -> CatalogPage {
        let data = try await call([
            "action": "catalog",
            "source": source,
            "page": page,
            "query": query,
            "category": category,
            "force": force,
        ])
        return CatalogPage(dict: data)
    }

    func suggestions(query: String) async throws -> [String] {
        let data = try await call(["action": "suggestions", "query": query])
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
            "chapter": episode.raw,
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
        let data = try await call([
            "action": "danmaku",
            "playbackSession": plan.session,
            "startMs": startMs,
            "durationMs": durationMs,
        ])
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
