import Foundation

/// 排查用的小日志：一行一条，写到 Caches/diagnostics.log（最多约 256 KB，超了只留后一半）。
/// 电视上没有控制台可看，出问题后用
/// `xcrun devicectl device copy from --domain-type appDataContainer --domain-identifier <包名>
///  --source Library/Caches/diagnostics.log --destination <目录>` 拷出来。
/// 只记应用前后台切换、本机播放服务是否还在、播放失败的原因——不记观看内容以外的个人信息。
enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "app.duanju.diagnostics", qos: .utility)
    private static let limit = 256 * 1024

    private static var file: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("diagnostics.log")
    }

    static func record(_ message: String) {
        let stamp = Date()
        queue.async {
            guard let file else { return }
            let line = "\(stamp.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))) \(message)\n"
            let existing = (try? Data(contentsOf: file)) ?? Data()
            let kept = existing.count > limit ? existing.suffix(limit / 2) : existing
            try? (kept + Data(line.utf8)).write(to: file, options: .atomic)
        }
    }
}
