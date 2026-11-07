import Testing
@testable import GuoAppLogic

private struct Item: Equatable, Sendable {
    let title: String
    var source = "hongguo"
}

private func group(_ items: [Item]) -> [SeriesEntry<Item>] {
    SeriesGrouping.group(items, title: \.title, source: \.source)
}

struct SeriesTitleTests {
    @Test func parsesArabicAndChinese() {
        #expect(SeriesTitle.parse("霸总 第2部") == SeriesTitle(base: "霸总", part: 2, unit: "部"))
        #expect(SeriesTitle.parse("霸总第二部")?.part == 2)
        #expect(SeriesTitle.parse("霸总 第十一季") == SeriesTitle(base: "霸总", part: 11, unit: "季"))
        #expect(SeriesTitle.parse("霸总第二十部")?.part == 20)
        #expect(SeriesTitle.parse("霸总第一百部")?.part == 100)
    }

    @Test func rejectsNonSeries() {
        #expect(SeriesTitle.parse("霸总") == nil)
        #expect(SeriesTitle.parse("第二部") == nil)
        #expect(SeriesTitle.parse("霸总第201部") == nil)
    }

    /// 网络来的标题可能很怪：十 / 百 前面一长串数字不能整数溢出崩溃，应判为非系列。
    @Test func hugeDigitRunDoesNotCrash() {
        #expect(SeriesTitle.parse("霸总第" + String(repeating: "九", count: 40) + "十部") == nil)
        #expect(SeriesTitle.parse("霸总第十" + String(repeating: "九", count: 40) + "部") == nil)
    }

    @Test func fullWidthAndPunctuation() {
        #expect(SeriesTitle.parse("霸总（第２部）") == SeriesTitle(base: "霸总", part: 2, unit: "部"))
    }

    @Test func keyNormalisesSpacingAndCase() {
        #expect(SeriesTitle.parse("Boss 战 第2部")?.key == SeriesTitle.parse("boss战第二部")?.key)
    }

    @Test func groupsSameSeries() {
        let entries = group([Item(title: "霸总"), Item(title: "霸总 第二部"), Item(title: "别的剧"), Item(title: "霸总第3部")])
        #expect(entries.count == 2)
        guard case .series(let series) = entries.first else {
            Issue.record("first entry should be a series")
            return
        }
        #expect(series.base == "霸总")
        #expect(series.unit == "部")
        #expect(series.partNumbers == [1, 2, 3])
        #expect(series.parts.map(\.item.title) == ["霸总", "霸总 第二部", "霸总第3部"])
        #expect(entries.last == .single(Item(title: "别的剧")))
    }

    @Test func unitsDontMix() {
        let entries = group([Item(title: "霸总 第二部"), Item(title: "霸总 第二季")])
        #expect(entries == [.single(Item(title: "霸总 第二部")), .single(Item(title: "霸总 第二季"))])
    }

    @Test func sourcesDontMix() {
        let entries = group([Item(title: "霸总", source: "hongguo"), Item(title: "霸总 第二部", source: "hema")])
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { if case .single = $0 { true } else { false } })
    }

    @Test func singlePartIsNotASeries() {
        #expect(group([Item(title: "霸总 第二部")]) == [.single(Item(title: "霸总 第二部"))])
    }

    @Test func partsLabel() {
        #expect(SeriesGrouping.partsLabel([1, 2, 3], unit: "部") == "第 1–3 部")
        #expect(SeriesGrouping.partsLabel([1, 3], unit: "部") == "第 1、3 部")
        #expect(SeriesGrouping.partsLabel([2], unit: "季") == "第 2 季")
    }
}
