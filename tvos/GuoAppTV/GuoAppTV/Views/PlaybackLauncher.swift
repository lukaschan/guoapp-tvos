import SwiftUI

/// 一次「直接播放」的展示参数（交给 PlayerView）。
struct PlaybackPresentation: Identifiable {
    let id = UUID()
    let drama: Drama
    let episodes: [Episode]
    let startIndex: Int
    let startPosition: Double
}

/// 「播这部剧」：先取详情拿分集列表，再按观看记录续播（找不到就从第 1 集开头）。
/// 继续观看卡片、海报上的播放键共用；每个页面持有一个，配合 `.playbackLauncher(_:)` 弹出播放页。
@MainActor
final class PlaybackLauncher: ObservableObject {
    /// 正在取详情的剧（卡片上显示加载中；期间重复按键忽略）。
    @Published private(set) var loadingDramaID: String?
    @Published var presentation: PlaybackPresentation?
    @Published var errorMessage: String?

    func play(_ drama: Drama, store: Store) {
        guard LaunchGate.canStart(loadingDramaID: loadingDramaID, presenting: presentation != nil) else { return }
        loadingDramaID = drama.id
        Task {
            defer { loadingDramaID = nil }
            do {
                let detail = try await DetailPrefetch.shared.detail(for: drama)
                let latest = store.latestProgress(for: drama.id)
                guard let target = ResumeTarget.playbackStart(
                    episodeNumbers: detail.episodes.map(\.number),
                    latestEpisode: latest?.episode,
                    position: latest?.position ?? 0,
                    duration: latest?.duration ?? 0,
                    releaseStatus: detail.drama.releaseStatus
                ) else {
                    errorMessage = "暂无可播放的分集"
                    return
                }
                presentation = PlaybackPresentation(
                    // 与详情页一致：用详情里的剧信息；解析不出 id 时退回传入的剧，保证进度记在同一部剧下。
                    drama: Self.withEpisodeCount(detail.drama.id.isEmpty ? drama : detail.drama, detail.episodes.count),
                    episodes: detail.episodes,
                    startIndex: target.index,
                    startPosition: target.position
                )
            } catch {
                errorMessage = UserFacingError.message(for: error)
            }
        }
    }
}

extension PlaybackLauncher {
    /// 已有分集列表时直接弹出播放页（详情页点分集、继续观看按钮），与 play 共用同一个播放页与防重入。
    func present(drama: Drama, episodes: [Episode], startIndex: Int, startPosition: Double) {
        guard LaunchGate.canStart(loadingDramaID: loadingDramaID, presenting: presentation != nil),
              episodes.indices.contains(startIndex)
        else { return }
        presentation = PlaybackPresentation(
            drama: Self.withEpisodeCount(drama, episodes.count),
            episodes: episodes,
            startIndex: startIndex,
            startPosition: startPosition
        )
    }

    /// 剧信息没给总集数时用分集列表数量补上，记进观看记录后「共 M 集」/「已看完」才能工作。
    static func withEpisodeCount(_ drama: Drama, _ count: Int) -> Drama {
        var copy = drama
        copy.episodes = EpisodeCount.effective(reported: drama.episodes, detailCount: count)
        return copy
    }
}

private struct PlaybackLauncherModifier: ViewModifier {
    @ObservedObject var launcher: PlaybackLauncher
    /// 交给播放会话存进度（播放页本身也从环境里读同一个 Store）。
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $launcher.presentation) { presentation in
                PlayerView(
                    drama: presentation.drama,
                    episodes: presentation.episodes,
                    startIndex: presentation.startIndex,
                    startPosition: presentation.startPosition,
                    store: store
                )
            }
            .alert("无法播放", isPresented: errorShown) {
                Button("好", role: .cancel) {}
            } message: {
                Text(launcher.errorMessage ?? "")
            }
    }

    private var errorShown: Binding<Bool> {
        Binding(
            get: { launcher.errorMessage != nil },
            set: { if !$0 { launcher.errorMessage = nil } }
        )
    }
}

extension View {
    /// 挂上「直接播放」：弹出播放页与失败提示。
    func playbackLauncher(_ launcher: PlaybackLauncher) -> some View {
        modifier(PlaybackLauncherModifier(launcher: launcher))
    }
}
