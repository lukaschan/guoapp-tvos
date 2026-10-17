import SwiftUI
import UIKit

/// 详情页：沉浸式影视详情。
///
/// 上半部分以模糊海报为底：左侧海报、右侧标题 / 信息胶囊 / 简介 / 主次操作；
/// 下半部分为选集网格，已看分集带进度条，「上次看到」的分集用强调色标出。
struct DetailView: View {
    let drama: Drama
    @EnvironmentObject private var store: Store
    @State private var detail: DramaDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var playTarget: PlayTarget?
    @State private var backdropImage: UIImage?

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
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(drama.title)
        .task { await load() }
        .task(id: "\(drama.id)\0\(drama.cover)") {
            backdropImage = await PosterCache.shared.image(for: drama)
        }
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
        ZStack(alignment: .bottomLeading) {
            TVBlurredBackdrop(image: backdropImage)
            TVTheme.detailScrim
            HStack(alignment: .bottom, spacing: 44) {
                posterColumn
                infoColumn
            }
            .padding(.horizontal, TVTheme.pageInset)
            .padding(.vertical, 40)
        }
        .frame(minHeight: 520)
        .frame(maxWidth: .infinity)
        .clipped()
        .overlay(alignment: .top) {
            // 顶部向纯黑过渡，与导航栏自然衔接。
            TVTheme.topFade.frame(height: 110).allowsHitTesting(false)
        }
    }

    private var posterColumn: some View {
        PosterView(drama: drama)
            .frame(width: 300)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
    }

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(displayDrama.title)
                .font(.system(size: 46, weight: .bold))
                .lineLimit(3)
            metaPills
            if !displayDrama.description.isEmpty {
                Text(displayDrama.description)
                    .font(.system(size: 21))
                    .foregroundColor(TVTheme.textSecondary)
                    .lineSpacing(6)
                    .lineLimit(4)
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
            if let progress = store.latestProgress(for: drama.id) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 19))
                        .foregroundColor(TVTheme.textTertiary)
                    Text("上次看到 第\(progress.episode)集 \(tvTimecode(progress.position))")
                        .font(.system(size: 20))
                        .foregroundColor(TVTheme.textTertiary)
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
                            .font(.system(size: 18))
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

    private var resumeLabel: String {
        store.latestProgress(for: drama.id) == nil ? "播放" : "继续播放"
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
            TVSectionHeader(
                title: "选集",
                icon: "play.rectangle.on.rectangle",
                trailing: "共 \(detail.episodes.count) 集"
            )
            if !detail.warning.isEmpty {
                Text(detail.warning)
                    .font(.system(size: 19))
                    .foregroundColor(TVTheme.textTertiary)
            }
            LazyVGrid(columns: TVTheme.episodeColumns(), spacing: 16) {
                ForEach(detail.episodes) { episode in
                    TVEpisodeButton(
                        title: episode.title,
                        vip: episode.vip,
                        progress: episodeProgress(episode),
                        isCurrent: store.latestProgress(for: drama.id)?.episode == episode.number
                    ) {
                        playTarget = PlayTarget(episode: episode, position: 0)
                    }
                }
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
        if let progress = store.latestProgress(for: drama.id),
           let episode = detail?.episodes.first(where: { $0.number == progress.episode }) {
            playTarget = PlayTarget(episode: episode, position: progress.position)
        } else if let first = detail?.episodes.first {
            playTarget = PlayTarget(episode: first, position: 0)
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
