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
                    }
                }
                // 给焦点放大留出空间
                .padding(.vertical, 30)
                .padding(.horizontal, 4)
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
