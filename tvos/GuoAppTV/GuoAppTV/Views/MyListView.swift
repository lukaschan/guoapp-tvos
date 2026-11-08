import SwiftUI

/// 追剧页（redfruit 样式）：上面「继续观看」卡片（点按或播放键直接续播），下面「我的追剧」海报。
/// 合并了原来的「追剧」和「最近观看」两页。
struct MyListView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var launcher = PlaybackLauncher()
    @State private var path: [Drama] = []

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: Drama.self) { drama in
                    DetailView(drama: drama)
                }
        }
        .playbackLauncher(launcher)
    }

    @ViewBuilder
    private var content: some View {
        if store.recentHistory.isEmpty && store.follows.isEmpty {
            TVStatusView(
                icon: "heart.text.square",
                title: "还没有追剧",
                message: "在详情页按「追剧」，或看过的短剧，都会出现在这里",
                expands: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, TVTheme.pageInset)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    continueWatching
                    followed
                }
                .padding(.vertical, 40)
            }
        }
    }

    // MARK: - 继续观看

    @ViewBuilder
    private var continueWatching: some View {
        // 同一系列只留最新看的那一部（第二部看到一半就不再单独列第一部）。
        let history = SeriesGrouping.newestPartPerSeries(
            store.recentHistory, title: \.drama.title, source: \.drama.source
        )
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                shelfHeader("继续观看", hint: "按播放键直接续播 · 长按可查看详情或移除")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 40) {
                        ForEach(history, id: \.item.drama.id) { collapsed in
                            let entry = collapsed.item
                            Button {
                                launcher.play(entry.drama, store: store)
                            } label: {
                                ContinueWatchingCard(
                                    progress: entry,
                                    isLoading: launcher.loadingDramaID == entry.drama.id,
                                    seriesTitle: collapsed.seriesTitle,
                                    partLabel: collapsed.partLabel,
                                    updateBadge: store.updateBadge(for: entry.drama.id)
                                )
                            }
                            .buttonStyle(ContinueCardButtonStyle())
                            .onPlayPauseCommand { launcher.play(entry.drama, store: store) }
                            .contextMenu {
                                Button {
                                    path.append(entry.drama)
                                } label: {
                                    Label("查看详情", systemImage: "info.circle")
                                }
                                Button(role: .destructive) {
                                    store.deleteHistory(for: entry.drama)
                                } label: {
                                    Label("从观看记录中移除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    // 给焦点放大与投影留出空间
                    .padding(.horizontal, 80)
                    .padding(.vertical, 30)
                }
            }
        }
    }

    // MARK: - 我的追剧

    @ViewBuilder
    private var followed: some View {
        if !store.follows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                shelfHeader("我的追剧", hint: "长按可取消追剧")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(store.follows, id: \.drama.id) { follow in
                            TVPosterCard(
                                drama: follow.drama,
                                subtitle: followCaption(follow.drama),
                                badge: store.updateBadge(for: follow.drama.id),
                                isLoading: launcher.loadingDramaID == follow.drama.id
                            )
                                .frame(width: 200)
                                .onPlayPauseCommand { launcher.play(follow.drama, store: store) }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.toggleFollow(follow.drama)
                                    } label: {
                                        Label("取消追剧", systemImage: "bookmark.slash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 30)
                }
            }
        }
    }

    private func followCaption(_ drama: Drama) -> String {
        let latest = store.latestProgress(for: drama.id)
        // 追剧里存的是目录版剧信息，观看记录里是详情版：哪边知道总集数就用哪边。
        let total = max(drama.episodes, latest?.drama.episodes ?? 0)
        return WatchStatus(
            latestEpisode: latest?.episode,
            position: latest?.position ?? 0,
            duration: latest?.duration ?? 0,
            totalEpisodes: total
        ).posterCaption
    }

    private func shelfHeader(_ title: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: TVTheme.TextSize.headline, weight: .bold))
                .foregroundColor(TVTheme.textPrimary)
            Text(hint)
                .font(.system(size: TVTheme.TextSize.caption))
                .foregroundColor(TVTheme.textTertiary)
        }
        .padding(.horizontal, 80)
    }
}
