import Foundation
import Testing
@testable import GuoAppLogic

/// 详情页补全信息（核心的 metadata）：红果剧缺评分或上线日期时补一次；表头显示评分、上线月份、热度。
struct DramaMetadataTests {
    @Test func supplementsHongguoMissingScoreOrDate() {
        #expect(DramaMetadata.needsSupplement(source: "hongguo", score: nil, onlineDate: "2026-10-01"))
        #expect(DramaMetadata.needsSupplement(source: "hongguo", score: "9.5", onlineDate: ""))
    }

    @Test func noSupplementWhenComplete() {
        #expect(!DramaMetadata.needsSupplement(source: "hongguo", score: "9.5", onlineDate: "2026-10-01"))
    }

    @Test func noSupplementForOtherSources() {
        #expect(!DramaMetadata.needsSupplement(source: "huangdou", score: nil, onlineDate: ""))
    }

    @Test func headerParts() {
        #expect(DramaMetadata.headerParts(score: "9.5", onlineDate: "2026-10-03", heat: "13237万热度")
            == ["评分 9.5", "2026-10 上线", "13237万热度"])
        #expect(DramaMetadata.headerParts(score: nil, onlineDate: "", heat: "") == [])
    }

    /// metadata 带回的热度是原始数字（实测 81807978）：换成万 / 亿。
    @Test func rawHeatIsFormatted() {
        #expect(DramaMetadata.heatLabel("81807978") == "8181万热度")
        #expect(DramaMetadata.heatLabel("123456789") == "1.2亿热度")
        #expect(DramaMetadata.heatLabel("9800") == "9800热度")
        #expect(DramaMetadata.heatLabel("13237万热度") == "13237万热度")
        #expect(DramaMetadata.heatLabel("") == nil)
    }

    private struct LegacyDrama: Codable {
        var id: String
        var score: String?
    }

    /// 旧版存下的剧信息没有 score：照样能读出来（Drama.score 是可选的，同样的写法）。
    @Test func legacyDramaDecodes() throws {
        let drama = try JSONDecoder().decode(LegacyDrama.self, from: Data(#"{"id": "hongguo:1"}"#.utf8))
        #expect(drama.score == nil)
    }
}
