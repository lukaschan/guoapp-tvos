import SwiftUI

/// 剧场顶部「今日主推」（redfruit 的 FeaturedBanner）：340 高、圆角 24，左侧文字与按钮，
/// 右侧 760 宽的封面区——同一张封面放大 1.6 倍、模糊 40、80 % 不透明做底，清晰的 190×285 封面压在上面，
/// 从左往右淡入。立即观看直接播（续播或从第 1 集），详情进详情页。
struct FeaturedBanner: View {
    let drama: Drama
    let onPlay: () -> Void

    init(drama: Drama, onPlay: @escaping () -> Void) {
        self.drama = drama
        self.onPlay = onPlay
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("今日主推")
                    .font(.system(size: TVTheme.TextSize.caption2, weight: .semibold))
                    .tracking(2)
                    .foregroundColor(TVTheme.textPrimary.opacity(0.75))
                Text(drama.title)
                    .font(.system(size: TVTheme.TextSize.title2, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.system(size: TVTheme.TextSize.body))
                        .foregroundColor(TVTheme.textPrimary.opacity(0.75))
                        .lineLimit(1)
                }
                HStack(spacing: 20) {
                    TVPrimaryButton(title: "立即观看", icon: "play.fill", action: onPlay)
                    DetailLink(drama: drama)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            artwork
        }
        .frame(height: 340)
        .background(TVTheme.surfaceDim)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .focusSection()
        // 与海报一致：焦点在横幅按钮上时按播放键直接播。
        .onPlayPauseCommand(perform: onPlay)
    }

    private var metadata: String {
        var parts = Array(drama.tags.prefix(2))
        if !drama.releaseLabel.isEmpty { parts.append(drama.releaseLabel) }
        if drama.episodes > 0 { parts.append("共 \(drama.episodes) 集") }
        return parts.joined(separator: " · ")
    }

    private var artwork: some View {
        ZStack {
            HeroCoverImage(drama: drama, maxPointSize: 540)
                .frame(width: 760, height: 340)
                .scaleEffect(1.6)
                .blur(radius: 40)
                .opacity(0.8)
            TVPosterImage(drama: drama)
                .frame(width: 190, height: 285)
                .clipShape(RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 24, y: 16)
        }
        .frame(width: 760, height: 340)
        .clipped()
        .mask {
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

/// 「详情」：外观同 TVSecondaryButton，但是导航链接（值为这部剧）。
private struct DetailLink: View {
    let drama: Drama
    @FocusState private var focused: Bool

    var body: some View {
        NavigationLink(value: drama) {
            HStack(spacing: 12) {
                Image(systemName: "info.circle")
                    .font(.system(size: TVTheme.TextSize.caption, weight: .medium))
                Text("详情")
                    .font(.system(size: TVTheme.TextSize.body, weight: .medium))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 19)
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
