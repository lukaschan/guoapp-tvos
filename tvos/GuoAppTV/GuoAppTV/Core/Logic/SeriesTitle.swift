import Foundation

// 系列（同一部剧的第 N 部 / 第 N 季）：规则与 Go 核心一致，见
// upstream/native/core/provider_hongguo_search_seasons.go（hongguoSearchSeason）与
// provider_hongguo_search.go（hongguoSearchText）。核心在搜索时会补齐缺失的分部，这里负责归组展示。

/// 从标题解析出的系列信息：「霸总 第二部」→ base 霸总、第 2 部。
struct SeriesTitle: Equatable, Sendable {
    let base: String
    let part: Int
    /// 「部」或「季」：两种单位视为不同系列。
    let unit: String

    /// 归组键：规范化后的剧名 + ":" + 单位。
    var key: String { Self.normalize(base) + ":" + unit }

    static let maximumPart = 200
    // 以「第 N 部 / 季」结尾，后面允许跟标点或空白。
    private static let suffix = try! NSRegularExpression(
        pattern: "第\\s*([0-9零〇一二两兩三四五六七八九十百]+)\\s*([季部])[\\p{P}\\s]*$"
    )
    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    static func parse(_ title: String) -> SeriesTitle? {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCompatibilityMapping
        let range = NSRange(text.startIndex..., in: text)
        guard let match = suffix.firstMatch(in: text, range: range),
              let whole = Range(match.range, in: text),
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let part = parseNumber(String(text[numberRange])),
              (1...maximumPart).contains(part)
        else { return nil }
        let base = String(text[..<whole.lowerBound]).trimmingTrailing { $0.isWhitespace || $0.isPunctuation }
        guard !base.isEmpty else { return nil }
        return SeriesTitle(base: base, part: part, unit: String(text[unitRange]))
    }

    /// 剧名规范化：NFKC、去空白与标点、转小写；结果为空时退回去首尾空白的小写原文。
    static func normalize(_ text: String) -> String {
        let scalars = text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0)
        }
        let normalized = String(String.UnicodeScalarView(scalars)).lowercased()
        return normalized.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() : normalized
    }

    /// 阿拉伯数字或中文数字（含十、百）；超出 1…200 或写法不合法时为 nil。
    private static func parseNumber(_ label: String) -> Int? {
        if let number = Int(label) { return number }
        if !label.contains("十") && !label.contains("百") {
            var number = 0
            for character in label {
                guard let value = digits[character] else { return nil }
                number = number * 10 + value
                if number > maximumPart { return nil }
            }
            return number
        }
        var number = 0, digit = 0, previous = 1000
        for character in label {
            if let value = digits[character] {
                digit = digit * 10 + value
                continue
            }
            let value = character == "百" ? 100 : 10
            if value >= previous || digit > 9 { return nil }
            number += max(digit, 1) * value
            digit = 0
            previous = value
        }
        return number + digit
    }
}

private extension String {
    func trimmingTrailing(where shouldTrim: (Character) -> Bool) -> String {
        var result = self
        while let last = result.last, shouldTrim(last) { result.removeLast() }
        return result
    }
}

/// 系列里的一部。
struct SeriesPart<Item> {
    let part: Int
    let item: Item
}

extension SeriesPart: Sendable where Item: Sendable {}
extension SeriesPart: Equatable where Item: Equatable {}

/// 同一系列的各部，按部数升序。
struct SeriesGroup<Item> {
    let key: String
    let base: String
    let unit: String
    let parts: [SeriesPart<Item>]

    var partNumbers: [Int] { parts.map(\.part) }
}

extension SeriesGroup: Sendable where Item: Sendable {}
extension SeriesGroup: Equatable where Item: Equatable {}

/// 归组结果：单部剧原样保留，同一系列（至少两部）合成一项。
enum SeriesEntry<Item> {
    case single(Item)
    case series(SeriesGroup<Item>)
}

extension SeriesEntry: Sendable where Item: Sendable {}
extension SeriesEntry: Equatable where Item: Equatable {}

/// 归组过程中的临时分组（泛型函数里不能嵌套类型）。
private struct PendingSeries {
    var base: String
    var unit: String
    var members: [(part: Int, index: Int)]
}

enum SeriesGrouping {
    /// 按系列归组，顺序沿用各项（系列取其最早出现的一部）首次出现的位置；只归同一站源的剧。
    /// 无后缀的标题若与某系列剧名一致，视为该系列第 1 部。
    static func group<Item>(
        _ items: [Item],
        title: (Item) -> String,
        source: (Item) -> String
    ) -> [SeriesEntry<Item>] {
        var groups: [String: PendingSeries] = [:]
        // 1. 带「第 N 部 / 季」后缀的标题建组。
        for (index, item) in items.enumerated() {
            guard let parsed = SeriesTitle.parse(title(item)) else { continue }
            let key = source(item) + "|" + parsed.key
            groups[key, default: PendingSeries(base: parsed.base, unit: parsed.unit, members: [])]
                .members.append((parsed.part, index))
        }
        // 2. 无后缀、剧名与某组一致的标题算第 1 部（优先「部」）。
        for (index, item) in items.enumerated() where SeriesTitle.parse(title(item)) == nil {
            let normalized = SeriesTitle.normalize(title(item))
            for unit in ["部", "季"] {
                let key = source(item) + "|" + normalized + ":" + unit
                if groups[key] != nil {
                    groups[key]?.members.append((1, index))
                    break
                }
            }
        }
        // 3. 至少两个不同部数才算系列；同一部数重复出现时只取最早的一项，其余按单部处理。
        var membership: [Int: String] = [:]
        var series: [String: SeriesGroup<Item>] = [:]
        for (key, pending) in groups {
            var seen = Set<Int>()
            let members = pending.members.sorted { ($0.part, $0.index) < ($1.part, $1.index) }.filter { seen.insert($0.part).inserted }
            guard members.count >= 2 else { continue }
            members.forEach { membership[$0.index] = key }
            series[key] = SeriesGroup(
                key: key,
                base: pending.base,
                unit: pending.unit,
                parts: members.map { SeriesPart(part: $0.part, item: items[$0.index]) }
            )
        }
        // 4. 按首次出现位置输出。
        var emitted = Set<String>()
        var entries: [SeriesEntry<Item>] = []
        for (index, item) in items.enumerated() {
            guard let key = membership[index], let group = series[key] else {
                entries.append(.single(item))
                continue
            }
            if emitted.insert(key).inserted {
                entries.append(.series(group))
            }
        }
        return entries
    }

    /// 「第 1–3 部」（连续）/「第 1、3 部」（不连续）/「第 2 季」（单个）。
    static func partsLabel(_ parts: [Int], unit: String) -> String {
        let sorted = parts.sorted()
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if sorted.count == 1 { return "第 \(first) \(unit)" }
        let contiguous = zip(sorted, sorted.dropFirst()).allSatisfy { $1 == $0 + 1 }
        if contiguous { return "第 \(first)–\(last) \(unit)" }
        return "第 " + sorted.map(String.init).joined(separator: "、") + " \(unit)"
    }
}
