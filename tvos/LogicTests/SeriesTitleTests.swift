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

    /// 红果真实片名：长系列后期常省掉「第」（「…44季」），要和「…第二季」归到一起。
    @Test func arabicSeasonWithoutDi() {
        #expect(SeriesTitle.parse("谁说没灵根不能修仙的？之无灵证道44季")
            == SeriesTitle(base: "谁说没灵根不能修仙的？之无灵证道", part: 44, unit: "季"))
        let entries = group([
            Item(title: "谁说没灵根不能修仙的？之无灵证道"),
            Item(title: "谁说没灵根不能修仙的？之无灵证道45季"),
            Item(title: "谁说没灵根不能修仙的？之无灵证道第二季"),
            Item(title: "谁说没灵根不能修仙的？之无灵证道44季"),
            Item(title: "谁说没灵根不能修仙的？之无灵证道第22季"),
        ])
        #expect(entries.count == 1)
        guard case .series(let series) = entries.first else {
            Issue.record("should be one series")
            return
        }
        #expect(series.partNumbers == [1, 2, 22, 44, 45])
    }

    /// 没有「第」的中文数字太容易误判（「人间四季」不是第 4 季），只接受阿拉伯数字。
    @Test func chineseNumeralNeedsDi() {
        #expect(SeriesTitle.parse("人间四季") == nil)
        #expect(SeriesTitle.parse("我的一部") == nil)
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

    /// 继续观看：同一系列只留最新看的那一部（历史已按时间倒序），并标出第几部、用系列名作标题。
    @Test func newestPartPerSeries() {
        let history = [Item(title: "霸总 第二部"), Item(title: "别的剧"), Item(title: "霸总")]
        let collapsed = SeriesGrouping.newestPartPerSeries(history, title: \.title, source: \.source)
        #expect(collapsed.map(\.item.title) == ["霸总 第二部", "别的剧"])
        #expect(collapsed.map(\.partLabel) == ["第 2 部", nil])
        #expect(collapsed.map(\.seriesTitle) == ["霸总", nil])
    }

    @Test func lonePartStillLabelled() {
        let collapsed = SeriesGrouping.newestPartPerSeries([Item(title: "霸总第三部")], title: \.title, source: \.source)
        #expect(collapsed.first?.partLabel == "第 3 部")
        #expect(collapsed.first?.seriesTitle == "霸总")
    }

    @Test func partsLabel() {
        #expect(SeriesGrouping.partsLabel([1, 2, 3], unit: "部") == "第 1–3 部")
        #expect(SeriesGrouping.partsLabel([1, 3], unit: "部") == "第 1、3 部")
        #expect(SeriesGrouping.partsLabel([2], unit: "季") == "第 2 季")
        // 部数很多又不连续时只给首尾（角标「共 N 部」给出实际数量），避免一长串。
        #expect(SeriesGrouping.partsLabel([1, 2, 3, 4, 5, 7], unit: "季") == "第 1–7 季")
    }
}
