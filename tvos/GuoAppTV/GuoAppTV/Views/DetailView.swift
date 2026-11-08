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
    /// 同名剧的各部（第 N 部 / 季），后台查询；单部剧为 nil。
    @State private var series: SeriesGroup<Drama>?
    /// 本页所有播放（点分集、继续观看、观看下一部）都走同一个播放页，避免两个全屏页互相抢。
    @StateObject private var launcher = PlaybackLauncher()

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
        .task {
            await load()
            // 详情到了再查本系列：搜索排在详情之后，不挡第一屏。
            series = await SeriesLookup.shared.parts(of: drama)
        }
        .playbackLauncher(launcher)
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
                TVPrimaryButton(
                    title: launcher.loadingDramaID != nil ? "正在准备…" : resumeLabel,
                    icon: "play.fill",
                    isLoading: launcher.loadingDramaID != nil
                ) {
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

    /// 主操作文案：观看下一部 / 重新观看 / 继续观看 第 N 集 / 立即观看（见 ResumeAction）。
    private var resumeLabel: String { resumeAction.title }

    private var resumeAction: ResumeAction {
        ResumeAction.make(
            target: resumeTarget,
            episodeNumbers: detail?.episodes.map(\.number) ?? [],
            isFinished: isFinished,
            hasNextPart: nextPart != nil
        )
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
                launcher.present(drama: displayDrama, episodes: detail.episodes, startIndex: index, startPosition: 0)
            }
            // 取下一部详情时（观看下一部）暂不响应分集点按，避免同时弹两个播放页。
            .disabled(launcher.loadingDramaID != nil)
            if let series {
                SeriesShelf(group: series, currentID: drama.id)
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

    /// 本系列里这一部之后的那一部（没有系列或已是最后一部时为 nil）。
    private var nextPart: Drama? {
        guard let series,
              let current = series.parts.first(where: { $0.item.id == drama.id }),
              let next = series.parts.first(where: { $0.part > current.part })
        else { return nil }
        return next.item
    }

    /// 这一部是否已看完（最后一集看到 99 %）。
    private var isFinished: Bool {
        guard let detail, let latest = store.latestProgress(for: drama.id) else { return false }
        return WatchStatus(
            latestEpisode: latest.episode,
            position: latest.position,
            duration: latest.duration,
            totalEpisodes: detail.episodes.count
        ).isFinished
    }

    private func playResume() {
        guard let episodes = detail?.episodes else { return }
        switch resumeAction {
        case .nextPart:
            if let next = nextPart { launcher.play(next, store: store) }
        case .restart:
            // 看完了且没有下一部：从第 1 集开头重新看。
            launcher.present(drama: displayDrama, episodes: episodes, startIndex: 0, startPosition: 0)
        case .start, .resume:
            guard let target = resumeTarget else { return }
            launcher.present(drama: displayDrama, episodes: episodes, startIndex: target.index, startPosition: target.position)
        }
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
