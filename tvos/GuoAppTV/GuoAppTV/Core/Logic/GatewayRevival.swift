import Foundation

/// 核心检查本机播放服务后的结论（核心补丁 ReviveNativeStream 的返回值，
/// 见 fork/core/tvos_stream_revive.go）。
enum GatewayRevival: String, Sendable {
    /// 核心还没就绪，或还没起过播（没有本机播放服务）。
    case idle
    /// 还在监听。
    case alive
    /// 监听没了，已在原端口恢复：播放地址不变。
    case revived
    /// 原端口拿不回来，旧服务已丢弃：旧播放地址作废，下次起播重新创建。
    case reset

    /// 不认识的回答按「还在」处理，免得因此反复重新起播。
    init(coreValue: String) {
        self = GatewayRevival(rawValue: coreValue) ?? .alive
    }

    /// 这次检查发现服务刚才不在了。
    var wasLost: Bool { self == .revived || self == .reset }
}

/// 本机播放服务是「第几代」：每丢失一次加一。起播时记下当时的代数；播放器报失败时代数变了，
/// 就是服务被系统回收（App 挂起）造成的——从刚才的位置重新起播，不当成播放失败。
struct GatewayGeneration: Equatable, Sendable {
    private(set) var value = 0

    func after(_ revival: GatewayRevival) -> GatewayGeneration {
        guard revival.wasLost else { return self }
        var next = self
        next.value += 1
        return next
    }
}
