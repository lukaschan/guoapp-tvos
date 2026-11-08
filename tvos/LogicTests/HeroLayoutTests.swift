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
        #expect(HeroLayout.infoWidth == 1040)
    }

    @Test func landscape() {
        // 横屏视频铺满整屏（owner 2026-11-08：全屏沉浸、看不到边框），信息栏宽度不变、切换时文字不重排。
        let layout = HeroLayout.panel(videoSize: CGSize(width: 1920, height: 1080))
        #expect(!layout.vertical)
        #expect(layout.frame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(HeroLayout.infoWidth == 1040)
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
