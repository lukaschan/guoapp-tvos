import SwiftUI

// 播放控件（Apple TV 系统播放器风格）：标题、按钮行（倍速 / 弹幕 / 选集）、进度条与时间。
// 「弹幕」按一下就开 / 关，与「我的」里的弹幕开关是同一个设置，下次播放沿用。
// 画面始终按 mpv 默认的等比适应显示（原「画面：适应 / 填充 / 拉伸」已按 owner 要求删除）。
// 只是画在 mpv 画面上的一层界面：播放、解析、预取、缓存逻辑都在 PlayerController / PlayerView，
// 这里不碰。遥控器：控件隐藏时点按 = 暂停 / 播放，← → = 快退 / 快进 10 秒，↑ ↓ = 调出控件；
// 控件显示时 ↑ 到按钮行、↓ 回进度条，Menu 先收起控件、再按退出播放。

// MARK: - 焦点与弹窗

enum PlayerFocus: Hashable {
    case surface, scrubber, speed, danmaku, episodes
}

enum PlayerSheet: String, Identifiable {
    case speed, episodes

    var id: String { rawValue }
}

// MARK: - 显示 / 自动隐藏

/// 控件显示状态：有操作时显示并重新计时，播放中 5 秒无操作自动隐藏；暂停或开着弹窗时不隐藏。
@MainActor
final class PlayerControlsState: ObservableObject {
    @Published private(set) var visible = false

    private static let autoHideDelay: Duration = .seconds(5)
    private var hideTask: Task<Void, Never>?

    func show(autoHide: Bool) {
        visible = true
        hideTask?.cancel()
        hideTask = nil
        guard autoHide else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autoHideDelay)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        visible = false
    }
}

// MARK: - 控件浮层

struct PlayerControlsOverlay: View {
    let title: String
    let subtitle: String
    let progress: PlaybackProgress
    let isPaused: Bool
    let speed: Double
    let danmakuOn: Bool
    let showsEpisodes: Bool
    let focus: FocusState<PlayerFocus?>.Binding
    let onSeek: (Double) -> Void
    let onTogglePause: () -> Void
    let onToggleDanmaku: () -> Void
    let onOpen: (PlayerSheet) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 40) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: TVTheme.TextSize.headline, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: TVTheme.TextSize.body))
                        .foregroundColor(TVTheme.textSecondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    PlayerControlButton(icon: "speedometer", title: "倍速 " + String(format: "%.2fx", speed)) {
                        onOpen(.speed)
                    }
                    .focused(focus, equals: .speed)
                    PlayerControlButton(
                        icon: danmakuOn ? "text.bubble.fill" : "text.bubble",
                        title: danmakuOn ? "弹幕 开" : "弹幕 关",
                        action: onToggleDanmaku
                    )
                    .focused(focus, equals: .danmaku)
                    if showsEpisodes {
                        PlayerControlButton(icon: "list.number", title: "选集") {
                            onOpen(.episodes)
                        }
                        .focused(focus, equals: .episodes)
                    }
                }
                .focusSection()
            }
            PlayerScrubber(fraction: fraction, focused: focus.wrappedValue == .scrubber)
                .focusable()
                .focused(focus, equals: .scrubber)
                .onMoveCommand { direction in
                    switch direction {
                    case .left: onSeek(-10)
                    case .right: onSeek(10)
                    default: break // ↑ ↓ 交给焦点引擎在按钮行与进度条间移动
                    }
                }
                .onTapGesture { onTogglePause() }
            HStack(spacing: 14) {
                Image(systemName: isPaused ? "pause.fill" : "play.fill")
                Text(tvTimecode(progress.position))
                Spacer()
                Text("-" + tvTimecode(max(0, progress.duration - progress.position)))
            }
            .font(.system(size: TVTheme.TextSize.caption, weight: .medium).monospacedDigit())
            .foregroundColor(TVTheme.textSecondary)
        }
        // 安全区：左右 80、上下 60（tvOS HIG）
        .padding(.horizontal, 80)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.black.opacity(0.88), .black.opacity(0)], startPoint: .bottom, endPoint: .top)
                .frame(height: 460)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var fraction: Double {
        progress.duration > 0 ? min(max(progress.position / progress.duration, 0), 1) : 0
    }
}

/// 进度条：获得焦点时变粗并显示拖动点（← → 每次跳 10 秒）。
private struct PlayerScrubber: View {
    let fraction: Double
    let focused: Bool

    var body: some View {
        GeometryReader { geometry in
            let barHeight: CGFloat = focused ? 12 : 7
            let knob: CGFloat = 26
            ZStack(alignment: .leading) {
                Capsule().fill(TVTheme.textPrimary.opacity(0.28))
                Capsule()
                    .fill(TVTheme.textPrimary)
                    .frame(width: geometry.size.width * fraction)
                Circle()
                    .fill(TVTheme.textPrimary)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.5), radius: 6)
                    .offset(x: geometry.size.width * fraction - knob / 2)
                    .opacity(focused ? 1 : 0)
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity)
            .animation(TVTheme.focusAnimation, value: focused)
        }
        .frame(height: 30)
    }
}

/// 按钮行里的胶囊按钮：焦点态白底黑字（与应用内 TVChip 一致）。
private struct PlayerControlButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: TVTheme.TextSize.body, weight: .medium))
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .foregroundColor(focused ? TVTheme.ink : TVTheme.textPrimary)
                .background(Capsule().fill(focused ? TVTheme.textPrimary : TVTheme.surfaceBright))
        }
        .buttonStyle(TVPressButtonStyle())
        .focused($focused)
        .scaleEffect(focused ? TVTheme.buttonScale : 1)
        .shadow(color: .black.opacity(focused ? 0.5 : 0), radius: focused ? 20 : 0, y: focused ? 16 : 0)
        .animation(TVTheme.focusAnimation, value: focused)
    }
}

// MARK: - 选集弹窗

/// 播放中选集：与详情页同一套分段集数网格，默认停在正在看的那集所在分段并聚焦它；选中后由调用方换集。
struct PlayerEpisodeSheet: View {
    let episodes: [Episode]
    let currentIndex: Int
    let progress: (Episode) -> Double?
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            EpisodeNumberGrid(
                episodes: episodes,
                currentEpisode: episodes.indices.contains(currentIndex) ? episodes[currentIndex].number : nil,
                progress: progress,
                columns: 10,
                trailing: "共 \(episodes.count) 集"
            ) { index in
                dismiss()
                onSelect(index)
            }
            // 给焦点放大留出空间
            .padding(24)
        }
        .padding(48)
        .frame(width: 1500, height: 820)
    }
}
