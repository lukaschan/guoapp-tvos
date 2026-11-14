import Foundation

/// 请求走哪条通道：播放类（起播、换线路、释放、取消播放、初始化）继续一个一个来——
/// 核心里较新的播放请求会取消进行中的那个（nativeBeginPlayback），并发会让预取下一集取消掉正要看的这集；
/// 其余都是读（封面、片库、详情、搜索、推荐、弹幕、追剧检查……），可以几个一起跑。
enum CoreLane: Sendable {
    case playback
    case read
}

enum CoreRoute {
    static let playbackActions: Set<String> = ["initialize", "resolve", "fallback", "release", "cancelPlayback"]

    static func lane(for action: String) -> CoreLane {
        playbackActions.contains(action) ? .playback : .read
    }

    /// 同一读会话里更新的请求到了，核心取消旧的并回 context canceled：这是取消，不是失败。
    static func isCancellation(message: String) -> Bool {
        message.lowercased().contains("context canceled")
    }
}
