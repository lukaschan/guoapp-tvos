import SwiftUI

/// 最近观看：播放历史（Store 里的观看进度，按部剧去重、按观看时间倒序）。
/// 卡片展示海报、看到第几集与进度条；点海报进详情页续播。
struct HistoryView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.recentHistory.isEmpty {
                    TVStatusView(
                        icon: "clock",
                        title: "还没有观看记录",
                        message: "播放过的剧集会显示在这里。",
                        expands: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, TVTheme.pageInset)
                } else {
                    ScrollView {
                        LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
                            ForEach(store.recentHistory, id: \.episodeKey) { entry in
                                TVPosterCard(
                                    drama: entry.drama,
                                    subtitle: subtitle(for: entry),
                                    progress: progressFraction(for: entry)
                                )
                            }
                        }
                        .padding(.horizontal, TVTheme.pageInset)
                        .padding(.top, 20)
                        .padding(.bottom, 56)
                    }
                }
            }
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
        }
    }

    private func progressFraction(for entry: WatchProgress) -> Double {
        guard entry.duration > 0 else { return 0 }
        return min(max(entry.position / entry.duration, 0), 1)
    }

    private func subtitle(for entry: WatchProgress) -> String {
        let episodeText = "第\(entry.episode)集"
        if entry.duration > 1 && entry.position >= entry.duration - 1 {
            return "\(episodeText) · 已看完"
        }
        return "\(episodeText) · 看到 \(tvTimecode(entry.position))"
    }
}
