import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if loading {
                    ProgressView("正在加载详情…").frame(maxWidth: .infinity)
                } else if let error {
                    VStack(spacing: 16) {
                        Text(error).foregroundColor(.secondary)
                        Button("重试") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity)
                } else if let detail {
                    episodeGrid(detail.episodes)
                }
            }
            .padding(48)
        }
        .navigationTitle(drama.title)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 40) {
            PosterView(drama: drama).frame(width: 280)
            VStack(alignment: .leading, spacing: 14) {
                Text(drama.title).font(.largeTitle)
                Text(metaLine).font(.subheadline).foregroundColor(.secondary)
                if !drama.description.isEmpty {
                    Text(drama.description).font(.body).foregroundColor(.secondary)
                }
                HStack(spacing: 16) {
                    Button(resumeLabel) { playResume() }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                    Button(store.isFollowing(drama) ? "已追剧" : "追剧") {
                        store.toggleFollow(drama)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                if let progress = store.latestProgress(for: drama.id) {
                    Text("上次看到 第\(progress.episode)集 \(formatTime(progress.position))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !drama.category.isEmpty { parts.append(drama.category) }
        if !drama.releaseLabel.isEmpty { parts.append(drama.releaseLabel) }
        if drama.episodes > 0 { parts.append("共 \(drama.episodes) 集") }
        if !drama.heat.isEmpty { parts.append("热度 \(drama.heat)") }
        return parts.joined(separator: " · ")
    }

    private var resumeLabel: String {
        store.latestProgress(for: drama.id) == nil ? "播放" : "继续播放"
    }

    private func episodeGrid(_ episodes: [Episode]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("选集").font(.title2)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)],
                spacing: 16
            ) {
                ForEach(episodes) { episode in
                    Button(episode.title + (episode.vip ? " · VIP" : "")) {
                        playTarget = PlayTarget(episode: episode, position: 0)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
    }

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

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
