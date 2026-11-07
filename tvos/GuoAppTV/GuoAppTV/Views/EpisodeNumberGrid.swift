import SwiftUI

/// 选集（redfruit 样式）：分段标签（1–30、31–60…）+ 集数格子网格。
/// 已看的格子变暗、上次看到的那集为强调色、焦点为白底深色字；VIP 集右上角小标签，
/// 看了一部分的集底部一条细进度条。详情页与播放中选集共用。
struct EpisodeNumberGrid: View {
    let episodes: [Episode]
    /// 上次看到的集数（Episode.number）；nil 表示没看过。
    let currentEpisode: Int?
    let progress: (Episode) -> Double?
    var columns: Int = 15
    var title: String = "选集"
    /// 标题右侧的补充信息，如「共 80 集」。
    var trailing: String? = nil
    /// 参数为 episodes 里的下标。
    let onSelect: (Int) -> Void

    @State private var selectedRange: Int?
    @Namespace private var scope

    init(
        episodes: [Episode],
        currentEpisode: Int?,
        progress: @escaping (Episode) -> Double?,
        columns: Int = 15,
        title: String = "选集",
        trailing: String? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.episodes = episodes
        self.currentEpisode = currentEpisode
        self.progress = progress
        self.columns = max(columns, 1)
        self.title = title
        self.trailing = trailing
        self.onSelect = onSelect
    }

    var body: some View {
        // 分段按分集在列表里的位置（从 1 起）切，格子上显示各集自己的集数。
        let ranges = EpisodeRanges(episodeCount: episodes.count)
        let currentIndex = currentEpisode.flatMap { number in episodes.firstIndex { $0.number == number } }
        let rangeIndex = selectedRange ?? ranges.clampedIndex(containing: (currentIndex ?? 0) + 1)
        VStack(alignment: .leading, spacing: 24) {
            header(ranges: ranges, rangeIndex: rangeIndex)
            if ranges.ranges.indices.contains(rangeIndex) {
                grid(range: ranges.ranges[rangeIndex], currentIndex: currentIndex)
            }
        }
        .focusScope(scope)
    }

    private func header(ranges: EpisodeRanges, rangeIndex: Int) -> some View {
        HStack(alignment: .center, spacing: 40) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(.system(size: TVTheme.TextSize.headline, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: TVTheme.TextSize.caption))
                        .foregroundColor(TVTheme.textTertiary)
                }
            }
            if ranges.ranges.count > 1 {
                HStack(spacing: 12) {
                    ForEach(Array(ranges.ranges.enumerated()), id: \.offset) { index, range in
                        TVChip(title: EpisodeRanges.label(for: range), isSelected: index == rangeIndex, compact: true) {
                            selectedRange = index
                        }
                    }
                }
                .focusSection()
            }
        }
    }

    private func grid(range: ClosedRange<Int>, currentIndex: Int?) -> some View {
        let indices = Array((range.lowerBound - 1)...(range.upperBound - 1)).filter { episodes.indices.contains($0) }
        let rows = stride(from: 0, to: indices.count, by: columns).map { Array(indices[$0..<min($0 + columns, indices.count)]) }
        return VStack(alignment: .leading, spacing: 20) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 20) {
                    ForEach(row, id: \.self) { index in
                        cell(index: index, isDefault: index == currentIndex)
                    }
                    // 最后一行不满时补空位，保持格子等宽对齐。
                    ForEach(row.count..<columns, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
        .focusSection()
    }

    private func cell(index: Int, isDefault: Bool) -> some View {
        let episode = episodes[index]
        return Button("\(episode.number)") { onSelect(index) }
            .buttonStyle(EpisodeCellStyle(
                state: EpisodeCellState(episode: episode.number, currentEpisode: currentEpisode),
                vip: episode.vip,
                progress: progress(episode)
            ))
            .frame(maxWidth: .infinity)
            .prefersDefaultFocus(isDefault, in: scope)
    }
}

/// 集数格子：已看变暗、当前集强调色、焦点白底深色字并放大；VIP 小标签；部分进度细条。
private struct EpisodeCellStyle: ButtonStyle {
    let state: EpisodeCellState
    let vip: Bool
    let progress: Double?

    func makeBody(configuration: Configuration) -> some View {
        EpisodeCellBody(configuration: configuration, state: state, vip: vip, progress: progress)
    }
}

private struct EpisodeCellBody: View {
    let configuration: ButtonStyleConfiguration
    let state: EpisodeCellState
    let vip: Bool
    let progress: Double?

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        configuration.label
            .font(.system(size: TVTheme.TextSize.callout, weight: .bold).monospacedDigit())
            .foregroundColor(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottom) {
                if let progress, progress > 0.005 {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(isFocused ? TVTheme.ink.opacity(0.5) : (state == .current ? TVTheme.textPrimary : TVTheme.accent))
                            .frame(width: geometry.size.width * min(progress, 1), height: 4)
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if vip {
                    Text("VIP")
                        .font(.system(size: TVTheme.TextSize.caption2, weight: .bold))
                        .foregroundColor(isFocused ? TVTheme.ink.opacity(0.7) : TVTheme.accent)
                        .padding(.top, 4)
                        .padding(.trailing, 8)
                }
            }
            .scaleEffect(isFocused ? (configuration.isPressed ? TVTheme.focusScale - 0.04 : TVTheme.focusScale) : 1)
            .shadow(color: .black.opacity(isFocused ? 0.6 : 0), radius: 15, y: 12)
            .zIndex(isFocused ? 1 : 0)
            .animation(TVTheme.focusAnimation, value: isFocused)
            .animation(TVTheme.focusAnimation, value: configuration.isPressed)
    }

    private var foreground: Color {
        if isFocused { return TVTheme.ink }
        return state == .watched ? TVTheme.textPrimary.opacity(0.45) : TVTheme.textPrimary
    }

    private var background: Color {
        if isFocused { return TVTheme.textPrimary }
        switch state {
        case .watched: return TVTheme.textPrimary.opacity(0.06)
        case .current: return TVTheme.accent
        case .unwatched: return TVTheme.surface
        }
    }
}
