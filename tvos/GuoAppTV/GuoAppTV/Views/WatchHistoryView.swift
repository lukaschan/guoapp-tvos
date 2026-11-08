import SwiftUI

/// 「我的」→ 看过的剧：看过的每部剧一张海报（最近看的在前），海报下标出看到第几集；
/// 点按进详情，播放键直接续播，长按可从观看记录中移除。部数与卡片上的数字一致（WatchHistory）。
struct WatchHistoryView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var launcher = PlaybackLauncher()

    var body: some View {
        let dramas = WatchHistory.dramas(
            store.progress, dramaID: \.drama.id, position: \.position, updatedAt: \.updatedAt
        )
        Group {
            if dramas.isEmpty {
                TVStatusView(
                    icon: "clock.arrow.circlepath",
                    title: "还没有观看记录",
                    message: "看过的短剧会出现在这里",
                    expands: false
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, TVTheme.pageInset)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(count: dramas.count)
                        LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
                            ForEach(dramas, id: \.drama.id) { entry in
                                TVPosterCard(
                                    drama: entry.drama,
                                    subtitle: caption(entry),
                                    isLoading: launcher.loadingDramaID == entry.drama.id
                                )
                                .onPlayPauseCommand { launcher.play(entry.drama, store: store) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.deleteHistory(for: entry.drama)
                                    } label: {
                                        Label("从观看记录中移除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
            }
        }
        .navigationDestination(for: Drama.self) { drama in
            DetailView(drama: drama)
        }
        .playbackLauncher(launcher)
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text("观看记录")
                .font(.system(size: TVTheme.TextSize.headline, weight: .bold))
                .foregroundColor(TVTheme.textPrimary)
            Text("\(count) 部 · 按播放键直接续播 · 长按可移除")
                .font(.system(size: TVTheme.TextSize.caption))
                .foregroundColor(TVTheme.textTertiary)
        }
    }

    private func caption(_ entry: WatchProgress) -> String {
        WatchStatus(
            latestEpisode: entry.episode,
            position: entry.position,
            duration: entry.duration,
            totalEpisodes: entry.drama.episodes
        ).posterCaption
    }
}
