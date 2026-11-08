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

    @Test func teaserLoading() {
        #expect(HeroStatus.teaserLine(episode: nil, paused: false, finished: false) == "正在加载…")
    }

    @Test func teaserPaused() {
        #expect(HeroStatus.teaserLine(episode: 3, paused: true, finished: false) == "已暂停 · 按播放键继续")
    }

    @Test func teaserPlaying() {
        #expect(HeroStatus.teaserLine(episode: 3, paused: false, finished: false) == "正在播放 第 3 集")
        #expect(HeroStatus.playing(episode: 12) == "正在播放 第 12 集")
    }

    @Test func teaserFinished() {
        #expect(HeroStatus.teaserLine(episode: 3, paused: true, finished: true) == "预告已播完 · 按全屏观看接着看")
    }
}
