import SwiftUI

/// 追剧页：统一的海报卡片网格。
/// 每张卡显示上次看到的位置；长按（遥控器菜单键）可取消追剧。
struct FollowingView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.follows.isEmpty {
                    TVStatusView(
                        icon: "bookmark",
                        title: "还没有追剧",
                        message: "在详情页点「追剧」，即可收藏到这里。",
                        expands: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, TVTheme.pageInset)
                } else {
                    ScrollView {
                        LazyVGrid(columns: TVTheme.posterColumns(), spacing: 32) {
                            ForEach(store.follows, id: \.drama.id) { followed in
                                TVPosterCard(
                                    drama: followed.drama,
                                    subtitle: followSubtitle(followed.drama)
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        store.toggleFollow(followed.drama)
                                    } label: {
                                        Label("取消追剧", systemImage: "bookmark.slash")
                                    }
                                }
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

    private func followSubtitle(_ drama: Drama) -> String? {
        guard let progress = store.latestProgress(for: drama.id) else { return nil }
        return "上次看到 第\(progress.episode)集"
    }
}
