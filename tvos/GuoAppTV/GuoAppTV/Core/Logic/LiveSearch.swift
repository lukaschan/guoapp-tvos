import Foundation

/// 边输入边搜索：停止输入 0.6 秒后，用去掉首尾空白的关键词调用原有的搜索（核心 catalog 的 query）。
enum LiveSearch {
    static let debounce: Duration = .milliseconds(600)

    /// 实际拿去搜索的关键词；空白时为 nil（不搜，清空结果）。
    static func query(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
