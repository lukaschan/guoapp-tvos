import Foundation

/// 电视上给人看的错误说明：网络类错误统一成一句「网络连接失败…」；
/// 核心给出的中文说明（如「该剧暂时没有可播放的分集」）原样保留；其余技术性英文报错换成通用的一句。
enum UserFacingError {
    static let network = "网络连接失败，请检查网络后重试"
    static let generic = "加载失败，请稍后重试"

    /// Go 核心与系统网络错误里常见的字样（小写比较）。
    private static let networkMarkers = [
        "dial tcp", "no such host", "i/o timeout", "timeout", "deadline exceeded", "connection refused",
        "connection reset", "network is unreachable", "tls handshake", "eof", "offline", "网络",
    ]

    static func message(for text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return generic }
        let lowered = trimmed.lowercased()
        if networkMarkers.contains(where: lowered.contains) { return network }
        if trimmed.unicodeScalars.contains(where: \.properties.isIdeographic) { return trimmed }
        return generic
    }

    static func message(for error: any Error) -> String {
        if error is URLError { return network }
        return message(for: error.localizedDescription)
    }
}
