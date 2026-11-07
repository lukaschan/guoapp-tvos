import SwiftUI
import UIKit

/// 详情页：沉浸式影视详情。
///
/// 上半部分（redfruit 样式）：左侧海报，右侧标题 / 信息胶囊 / 简介 / 主操作「继续观看 第 N 集」或「立即观看」与追剧；
/// 下半部分为分段集数选集网格，已看的格子变暗，上次看到的那集为强调色。
struct DetailView: View {
    let drama: Drama
    @EnvironmentObject private var store: Store
    @State private var detail: DramaDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var playTarget: PlayTarget?

    private struct PlayTarget: Identifiable {
        let episode: Episode
        let position: Double
        var id: String { "\(episode.number)" }
    }

    /// 展示用的剧信息：详情接口返回的完整数据优先（简介 / 分类等更全），
    /// 详情未加载出来时回落到目录传来的剧信息。
    private var displayDrama: Drama { detail?.drama ?? drama }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                header
                episodesSection
            }
            .padding(.bottom, 56)
        }
        .background(TVTheme.background.ignoresSafeArea())
        .task { await load() }
        .fullScreenCover(item: $playTarget) { target in
            PlayerView(
                drama: detail?.drama ?? drama,
                episodes: detail?.episodes ?? [],
                startIndex: (detail?.episodes.firstIndex { $0.id == target.episode.id }) ?? 0,
                startPosition: target.position
            )
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 44) {
            posterColumn
            infoColumn
        }
        .padding(.horizontal, TVTheme.pageInset)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var posterColumn: some View {
        PosterView(drama: drama)
            .frame(width: 300)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(TVTheme.textPrimary.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(displayDrama.title)
                .font(.system(size: TVTheme.TextSize.title2, weight: .heavy))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            metaPills
            if !displayDrama.description.isEmpty {
                Text(displayDrama.description)
                    .font(.system(size: TVTheme.TextSize.body))
                    .foregroundColor(TVTheme.textSecondary)
                    .lineSpacing(8)
                    .lineLimit(3)
            }
            HStack(spacing: 20) {
                TVPrimaryButton(title: resumeLabel, icon: "play.fill") {
                    playResume()
                }
                TVSecondaryButton(
                    title: store.isFollowing(drama) ? "已追剧" : "追剧",
                    icon: store.isFollowing(drama) ? "bookmark.fill" : "bookmark"
                ) {
                    store.toggleFollow(drama)
                }
            }
        }
    }

    /// 状态信息胶囊：分类 / 更新状态 / 集数 / 热度，有才显示。
    private var metaPills: some View {
        let parts = metaParts
        return Group {
            if !parts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(parts, id: \.self) { part in
                        Text(part)
                            .font(.system(size: TVTheme.TextSize.caption2))
                            .foregroundColor(TVTheme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(TVTheme.surface))
                    }
                }
            }
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if !displayDrama.category.isEmpty { parts.append(displayDrama.category) }
        if !displayDrama.releaseLabel.isEmpty { parts.append(displayDrama.releaseLabel) }
        if displayDrama.episodes > 0 { parts.append("共 \(displayDrama.episodes) 集") }
        if !displayDrama.heat.isEmpty { parts.append("热度 \(displayDrama.heat)") }
        return parts
    }

    /// 主操作文案：记录里的那集在分集列表中时「继续观看 第 N 集」，否则「立即观看」。
    private var resumeLabel: String {
        guard let target = resumeTarget, target.position > 0 || target.index > 0,
              let episodes = detail?.episodes, episodes.indices.contains(target.index)
        else { return "立即观看" }
        return "继续观看 第 \(episodes[target.index].number) 集"
    }

    private var resumeTarget: ResumeTarget? {
        let latest = store.latestProgress(for: drama.id)
        return ResumeTarget.resolve(
            episodeNumbers: detail?.episodes.map(\.number) ?? [],
            latestEpisode: latest?.episode,
            position: latest?.position ?? 0
        )
    }

    // MARK: - 选集

    @ViewBuilder
    private var episodesSection: some View {
        if loading {
            TVLoadingView("正在加载详情…")
                .padding(.vertical, 80)
        } else if let error {
            VStack(spacing: 26) {
                TVStatusView(
                    icon: "exclamationmark.triangle",
                    title: "详情加载失败",
                    message: error,
                    expands: false
                )
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    Task { await load() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if let detail {
            episodeSection(detail)
        }
    }

    private func episodeSection(_ detail: DramaDetail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            if !detail.warning.isEmpty {
                Text(detail.warning)
                    .font(.system(size: TVTheme.TextSize.caption2))
                    .foregroundColor(TVTheme.textTertiary)
            }
            EpisodeNumberGrid(
                episodes: detail.episodes,
                currentEpisode: store.latestProgress(for: drama.id)?.episode,
                progress: episodeProgress,
                trailing: "共 \(detail.episodes.count) 集"
            ) { index in
                playTarget = PlayTarget(episode: detail.episodes[index], position: 0)
            }
        }
        .padding(.horizontal, TVTheme.pageInset)
    }

    private func episodeProgress(_ episode: Episode) -> Double? {
        guard let progress = store.progress(for: drama.id, episode: episode.number),
              progress.duration > 0
        else { return nil }
        let fraction = progress.position / progress.duration
        guard fraction > 0.005 else { return nil }
        return min(max(fraction, 0), 1)
    }

    // MARK: - 播放与加载（业务逻辑与原版一致）

    private func playResume() {
        guard let target = resumeTarget, let episodes = detail?.episodes else { return }
        playTarget = PlayTarget(episode: episodes[target.index], position: target.position)
    }

    private func load() async {
        loading = true
        error = nil
        do {
            detail = try await CoreClient.shared.detail(drama: drama)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
