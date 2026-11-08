import SwiftUI

/// 推荐页 hero 左侧信息栏（x 80、y 250 起，竖排间距 22）：
/// 角标（热播 / 预览）、标签与状态、大标题、简介、播放进度行、操作按钮（全屏观看 / 暂停 / 追剧 / 选集）。
struct HeroInfoPanel: View {
    let drama: Drama
    let isPreview: Bool
    let status: HeroPlayback.Status
    let autoAdvance: Bool
    let width: CGFloat
    let isFollowing: Bool
    let defaultFocus: Namespace.ID
    let onWatch: () -> Void
    /// 出错时主按钮变成「重试」：重新起播这部剧。
    let onRetry: () -> Void
    let onTogglePause: () -> Void
    /// 自动播放关着、还没开始：按钮显示「播放」，状态行提示按播放键开始。
    var isIdle = false
    let onFollow: () -> Void
    let onEpisodes: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            badge
            if !metadata.isEmpty {
                Text(metadata)
                    .font(.system(size: TVTheme.TextSize.caption, weight: .medium))
                    .foregroundColor(TVTheme.textSecondary)
                    .lineLimit(1)
            }
            Text(drama.title)
                .font(.system(size: TVTheme.TextSize.hero, weight: .heavy))
                .foregroundColor(TVTheme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if !drama.description.isEmpty {
                Text(drama.description)
                    .font(.system(size: TVTheme.TextSize.body))
                    .foregroundColor(TVTheme.textPrimary.opacity(0.78))
                    .lineLimit(2)
                    .frame(maxWidth: 900, alignment: .leading)
            }
            progressRow
            buttons
                .padding(.top, 8)
        }
        .frame(width: width, alignment: .leading)
    }

    private var badge: some View {
        Text(isPreview ? "预览" : "热播")
            .font(.system(size: TVTheme.TextSize.caption2, weight: .bold))
            .foregroundColor(TVTheme.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(isPreview ? TVTheme.surfaceBright : TVTheme.accent))
    }

    private var metadata: String {
        var parts = Array(drama.tags.prefix(3))
        if !drama.releaseLabel.isEmpty { parts.append(drama.releaseLabel) }
        if drama.episodes > 0 { parts.append("共 \(drama.episodes) 集") }
        return parts.joined(separator: " · ")
    }

    private var statusLine: String {
        if isIdle { return "按播放键开始播放" }
        if let error = status.error { return error }
        return HeroStatus.line(
            episode: status.showsVideo ? status.episode : nil,
            remaining: status.remaining,
            isLastEpisode: status.isLastEpisode,
            paused: status.paused,
            autoAdvance: autoAdvance
        )
    }

    private var progressRow: some View {
        HStack(spacing: 20) {
            if let episode = status.episode, statusLine != HeroStatus.playing(episode: episode) {
                Text(HeroStatus.playing(episode: episode))
                    .font(.system(size: TVTheme.TextSize.caption, weight: .semibold))
                    .foregroundColor(TVTheme.textPrimary)
            }
            if let fraction = status.fraction {
                TVProgressBar(fraction: fraction)
                    .frame(width: 320, height: 6)
            }
            Text(statusLine)
                .font(.system(size: TVTheme.TextSize.caption))
                .foregroundColor(status.error == nil ? TVTheme.textTertiary : TVTheme.accent)
                .lineLimit(1)
        }
        .frame(height: 36)
    }

    private var buttons: some View {
        HStack(spacing: 24) {
            // 同一个按钮换文字和动作（不换视图），焦点在它上面时出错也不会丢焦点。
            TVPrimaryButton(
                title: status.error == nil ? "全屏观看" : "重试",
                icon: status.error == nil ? "play.fill" : "arrow.clockwise",
                isLoading: !isIdle && !status.showsVideo && status.error == nil
            ) {
                if status.error == nil { onWatch() } else { onRetry() }
            }
            .prefersDefaultFocus(true, in: defaultFocus)
            TVSecondaryButton(
                title: isIdle ? "播放" : (status.paused ? "继续" : "暂停"),
                icon: isIdle || status.paused ? "play.fill" : "pause.fill"
            ) {
                onTogglePause()
            }
            TVSecondaryButton(title: isFollowing ? "已追剧" : "追剧", icon: isFollowing ? "heart.fill" : "heart") {
                onFollow()
            }
            TVSecondaryButton(title: "选集", icon: "list.number") {
                onEpisodes()
            }
        }
        .focusSection()
    }
}
