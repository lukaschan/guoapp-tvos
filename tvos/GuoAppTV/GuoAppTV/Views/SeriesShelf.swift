import SwiftUI

/// 详情页「本系列」：同一部剧的各部海报，标出当前这部与下一部；点按进入那一部的详情。
struct SeriesShelf: View {
    let group: SeriesGroup<Drama>
    let currentID: String

    @EnvironmentObject private var store: Store

    var body: some View {
        let currentPart = group.parts.first { $0.item.id == currentID }?.part
        let nextPart = currentPart.flatMap { current in group.partNumbers.first { $0 > current } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("本系列")
                    .font(.system(size: TVTheme.TextSize.headline, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                Text("共 \(group.parts.count) \(group.unit)")
                    .font(.system(size: TVTheme.TextSize.caption))
                    .foregroundColor(TVTheme.textTertiary)
            }
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(group.parts, id: \.item.id) { part in
                        let isCurrent = part.item.id == currentID
                        TVPosterCard(
                            drama: part.item,
                            title: "第 \(part.part) \(group.unit)",
                            subtitle: caption(part.item),
                            badge: isCurrent ? "当前" : (part.part == nextPart ? "下一部" : nil),
                            badgeColor: isCurrent ? TVTheme.accent : TVTheme.surfaceBright
                        )
                        .frame(width: 160)
                        // 当前这部就是本页，不再重复进入。
                        .disabled(isCurrent)
                        .id(part.item.id)
                    }
                }
                // 给焦点放大留出空间
                .padding(.vertical, 30)
                .padding(.horizontal, 4)
            }
            // 长系列（几十季）一打开就停在当前这部附近，不用从第 1 部翻过去。
            .onAppear { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
    }

    private func caption(_ drama: Drama) -> String {
        let latest = store.latestProgress(for: drama.id)
        return WatchStatus(
            latestEpisode: latest?.episode,
            position: latest?.position ?? 0,
            duration: latest?.duration ?? 0,
            totalEpisodes: max(drama.episodes, latest?.drama.episodes ?? 0)
        ).posterCaption
    }
}

/// 「本系列」还没出来时占的位置：查找中，或没查到（重试）。查完是单部剧就什么都不显示。
/// 查本系列要搜一次红果（2～3 秒），不提示的话看的人会以为这部剧没有其他季。
struct SeriesShelfPlaceholder: View {
    /// true 为没查到（搜索失败），false 为查找中。
    let failed: Bool
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("本系列")
                .font(.system(size: TVTheme.TextSize.headline, weight: .bold))
                .foregroundColor(TVTheme.textPrimary)
            if failed {
                HStack(spacing: 28) {
                    Text("暂时没查到同系列的其他季 / 部")
                        .font(.system(size: TVTheme.TextSize.body))
                        .foregroundColor(TVTheme.textSecondary)
                    TVSecondaryButton(title: "重试", icon: "arrow.clockwise", action: retry)
                }
            } else {
                HStack(spacing: 14) {
                    ProgressView()
                    Text("正在查找同系列的其他季 / 部…")
                        .font(.system(size: TVTheme.TextSize.body))
                        .foregroundColor(TVTheme.textSecondary)
                }
            }
        }
        .padding(.vertical, 12)
    }
}
