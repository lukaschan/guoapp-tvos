import CoreGraphics
import Foundation
import Testing
@testable import GuoAppLogic

struct HeroLayoutTests {
    @Test func verticalDefault() {
        let layout = HeroLayout.panel(videoSize: nil)
        #expect(layout.vertical)
        #expect(layout.frame == CGRect(x: 1192, y: 0, width: 608, height: 1080))
        #expect(HeroLayout.panel(videoSize: CGSize(width: 720, height: 1280)).vertical)
        #expect(HeroLayout.infoWidth(vertical: true) == 1040)
    }

    @Test func landscape() {
        let layout = HeroLayout.panel(videoSize: CGSize(width: 1920, height: 1080))
        #expect(!layout.vertical)
        #expect(layout.frame == CGRect(x: 860, y: 150, width: 1060, height: 596))
        #expect(HeroLayout.infoWidth(vertical: false) == 760)
    }

    @Test func statusLoading() {
        #expect(HeroStatus.line(episode: nil, remaining: nil, isLastEpisode: false, paused: false, autoAdvance: true)
            == "正在加载…")
    }

    @Test func statusPaused() {
        #expect(HeroStatus.line(episode: 3, remaining: 67, isLastEpisode: false, paused: true, autoAdvance: true)
            == "已暂停 · 按播放键继续")
    }

    @Test func statusNextEpisode() {
        #expect(HeroStatus.line(episode: 3, remaining: 67, isLastEpisode: false, paused: false, autoAdvance: true)
            == "01:07 后自动播放下一集")
    }

    @Test func statusNextDrama() {
        #expect(HeroStatus.line(episode: 80, remaining: 5, isLastEpisode: true, paused: false, autoAdvance: true)
            == "00:05 后播放下一部")
    }

    @Test func statusAutoAdvanceOff() {
        #expect(HeroStatus.line(episode: 3, remaining: 67, isLastEpisode: false, paused: false, autoAdvance: false)
            == "正在播放 第 3 集")
        #expect(HeroStatus.playing(episode: 12) == "正在播放 第 12 集")
    }

    @Test func statusUnknownDuration() {
        #expect(HeroStatus.line(episode: 3, remaining: nil, isLastEpisode: false, paused: false, autoAdvance: true)
            == "正在播放 第 3 集")
    }
}
