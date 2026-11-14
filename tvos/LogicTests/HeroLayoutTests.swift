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

/// mpv 起播后不跟随图层尺寸变化，所以 hero 的播放器图层固定铺满整个画布、从不改尺寸，
/// 由 mpv 用边距把画面摆到面板位置（竖屏右侧整高面板、横屏右侧横框，与原设计一致）。
struct HeroMarginsTests {
    /// 边距围出的区域（画布 1920×1080 里）。
    private func area(_ margins: [String: String]) -> CGRect {
        let left = Double(margins["video-margin-ratio-left"] ?? "") ?? -1
        let right = Double(margins["video-margin-ratio-right"] ?? "") ?? -1
        let top = Double(margins["video-margin-ratio-top"] ?? "") ?? -1
        let bottom = Double(margins["video-margin-ratio-bottom"] ?? "") ?? -1
        return CGRect(x: left * 1920, y: top * 1080, width: (1 - left - right) * 1920, height: (1 - top - bottom) * 1080)
    }

    private func close(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    @Test func verticalVideoIsPlacedOnTheRightPanel() {
        let margins = HeroLayout.mpvMargins(videoSize: CGSize(width: 1080, height: 1920))
        #expect(close(area(margins), HeroLayout.verticalPanel))
    }

    @Test func landscapeVideoIsPlacedOnTheLandscapeBox() {
        let margins = HeroLayout.mpvMargins(videoSize: CGSize(width: 1920, height: 1080))
        #expect(close(area(margins), HeroLayout.landscapePanel))
    }

    @Test func unknownSizeStartsOnTheVerticalPanel() {
        #expect(HeroLayout.mpvMargins(videoSize: nil) == HeroLayout.mpvMargins(videoSize: CGSize(width: 720, height: 1280)))
    }
}
