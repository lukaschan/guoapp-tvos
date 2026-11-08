import SwiftUI

/// 出品方剧作页：从详情页的出品方入口进入后才向核心检索——先按剧名定
/// 出品方，再拉它的全部剧作。顶部可按最新 / 最热排序，点任意剧进详情。
struct ProducerView: View {
    let drama: Drama
    @State private var works: ProducerWorks?
    @State private var loading = true
    @State private var error: String?
    @State private var newest = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TVTheme.sectionSpacing) {
                header
                content
            }
            .padding(.horizontal, TVTheme.pageInset)
            .padding(.vertical, 40)
        }
        .background(Color.black.ignoresSafeArea())
        .task { await load() }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                Text(works?.producer.isEmpty == false ? works!.producer : "出品方")
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(1)
                if let works, !works.producer.isEmpty {
                    Text("出品方剧作 · 共 \(works.items.count) 部")
                        .font(.system(size: 20))
                        .foregroundColor(TVTheme.textSecondary)
                }
            }
            Spacer()
            HStack(spacing: 14) {
                sortButton("最新", selected: newest) { newest = true }
                sortButton("最热", selected: !newest) { newest = false }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sortButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: selected ? .bold : .regular))
                .foregroundColor(selected ? .white : TVTheme.textPrimary)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Capsule().fill(selected ? TVTheme.accent : TVTheme.surface))
        }
        .buttonStyle(TVPressButtonStyle())
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if loading {
            TVLoadingView("正在查找出品方剧作…")
                .padding(.vertical, 80)
        } else if let error {
            VStack(spacing: 26) {
                TVStatusView(
                    icon: "exclamationmark.triangle",
                    title: "加载失败",
                    message: error,
                    expands: false
                )
                TVPrimaryButton(title: "重试", icon: "arrow.clockwise") {
                    Task { await load() }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if let works, works.producer.isEmpty {
            TVStatusView(
                icon: "building.2",
                title: "未找到出品方",
                message: "该剧暂无出品方信息。",
                expands: false
            )
            .padding(.vertical, 60)
        } else if let works {
            TVPosterGrid(
                items: sorted(works.items),
                subtitle: { drama in
                    if newest {
                        drama.onlineDate.isEmpty ? nil : drama.onlineDate
                    } else {
                        drama.heat.isEmpty ? nil : "热度 \(drama.heat)"
                    }
                }
            )
        }
    }

    private func sorted(_ items: [Drama]) -> [Drama] {
        items.sorted { a, b in
            if newest {
                if a.onlineDate != b.onlineDate { return a.onlineDate > b.onlineDate }
                return heatValue(a.heat) > heatValue(b.heat)
            }
            let byHeat = heatValue(a.heat) - heatValue(b.heat)
            if byHeat != 0 { return byHeat > 0 }
            return a.onlineDate > b.onlineDate
        }
    }

    private func heatValue(_ raw: String) -> Double {
        var text = raw.trimmingCharacters(in: .whitespaces)
        var scale = 1.0
        if text.hasSuffix("亿") {
            scale = 100_000_000
            text.removeLast()
        } else if text.hasSuffix("万") {
            scale = 10_000
            text.removeLast()
        }
        return (Double(text) ?? 0) * scale
    }

    private func load() async {
        loading = true
        error = nil
        do {
            works = try await CoreClient.shared.producerWorks(drama: drama)
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
