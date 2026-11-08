import Foundation

/// 详情页的补全信息（核心的 metadata）：红果的剧在列表里常缺评分或上线日期，进详情时补一次；
/// 表头显示「评分 9.5」「2026-10 上线」「8181万热度」，没有的不显示。
enum DramaMetadata {
    static func needsSupplement(source: String, score: String?, onlineDate: String) -> Bool {
        guard source == "hongguo" else { return false }
        return (score ?? "").isEmpty || onlineDate.isEmpty
    }

    static func headerParts(score: String?, onlineDate: String, heat: String) -> [String] {
        var parts: [String] = []
        if let score, !score.isEmpty { parts.append("评分 \(score)") }
        if onlineDate.count >= 7 { parts.append("\(onlineDate.prefix(7)) 上线") }
        if let heat = heatLabel(heat) { parts.append(heat) }
        return parts
    }

    /// 热度：列表里已经是「13237万热度」就原样；metadata 带回的原始数字换成万 / 亿。
    static func heatLabel(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = Double(text), text.allSatisfy(\.isNumber) else {
            return text.hasSuffix("热度") ? text : text + "热度"
        }
        if value >= 100_000_000 { return String(format: "%.1f亿热度", value / 100_000_000) }
        if value >= 10_000 { return "\(Int((value / 10_000).rounded()))万热度" }
        return "\(Int(value))热度"
    }
}
