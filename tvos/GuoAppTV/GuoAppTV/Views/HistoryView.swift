import SwiftUI

/// 最近观看：展示播放历史（Store 里的观看进度，按部剧去重、按观看时间倒序）。
/// 点海报进详情页，详情页已有“继续播放”续播。
struct HistoryView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.recentHistory.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有观看记录")
                        Text("播放过的剧集会显示在这里。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 28)],
                            spacing: 28
                        ) {
                            ForEach(store.recentHistory, id: \.episodeKey) { entry in
                                NavigationLink(value: entry.drama) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        PosterView(drama: entry.drama)
                                        Text(entry.drama.title)
                                            .font(.system(size: 18))
                                            .lineLimit(2)
                                        Text(subtitle(for: entry))
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                        GeometryReader { geometry in
                                            ZStack(alignment: .leading) {
                                                Rectangle().fill(Color.white.opacity(0.15))
                                                Rectangle().fill(Color.white)
                                                    .frame(width: geometry.size.width * progressFraction(for: entry))
                                            }
                                        }
                                        .frame(height: 4)
                                        .cornerRadius(2)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .padding(.horizontal, 48)
            .navigationTitle("最近观看")
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
        }
    }

    private func progressFraction(for entry: WatchProgress) -> CGFloat {
        guard entry.duration > 0 else { return 0 }
        return CGFloat(min(max(entry.position / entry.duration, 0), 1))
    }

    private func subtitle(for entry: WatchProgress) -> String {
        let episodeText = "第\(entry.episode)集"
        if entry.duration > 1 && entry.position >= entry.duration - 1 {
            return "\(episodeText) · 已看完"
        }
        return "\(episodeText) · 看到 \(formatTime(entry.position))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
