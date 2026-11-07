import SwiftUI

/// 「继续观看」卡片（redfruit 样式）：小海报、剧名、看到第 N 集 / 共 M 集、整部剧进度条。
/// 取详情准备续播时在海报上叠一个加载圈。
struct ContinueWatchingCard: View {
    let progress: WatchProgress
    var isLoading = false
    /// 系列里的某一部：标题用系列名，进度文案前加「第 N 部 · 」。
    var seriesTitle: String? = nil
    var partLabel: String? = nil

    var body: some View {
        let status = WatchStatus(
            latestEpisode: progress.episode,
            position: progress.position,
            duration: progress.duration,
            totalEpisodes: progress.drama.episodes
        )
        HStack(alignment: .top, spacing: 24) {
            PosterView(drama: progress.drama)
                .frame(width: 140, height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    if isLoading {
                        ZStack {
                            Color.black.opacity(0.45)
                            ProgressView()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            VStack(alignment: .leading, spacing: 10) {
                Text(seriesTitle ?? progress.drama.title)
                    .font(.system(size: TVTheme.TextSize.body, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                    .lineLimit(2)
                Text([partLabel, status.cardCaption].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: TVTheme.TextSize.caption))
                    .foregroundColor(TVTheme.textPrimary.opacity(0.7))
                    .lineLimit(1)
                TVProgressBar(fraction: status.seriesFraction)
                    .frame(width: 290, height: 8)
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 500, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TVTheme.textPrimary.opacity(0.08))
        )
    }
}

/// 卡片按钮的焦点效果：放大 5% + 外侧白环 + 抬升投影（与海报一致）。
struct ContinueCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ContinueCardFocusBody(configuration: configuration)
    }
}

private struct ContinueCardFocusBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .tvFocusEffect(focused: isFocused, scale: configuration.isPressed ? 1.02 : 1.05, cornerRadius: 20)
            .zIndex(isFocused ? 1 : 0)
    }
}
