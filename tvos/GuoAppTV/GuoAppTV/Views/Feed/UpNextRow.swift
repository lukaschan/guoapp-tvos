import SwiftUI

/// 推荐页底部「接下来」：之后的 10 部，160×240 海报，间距 32，裁在 1192 宽的一行里。
/// 焦点停留 1 秒预览（hero 先放它），按下才切换；焦点变化交给上层（PreviewSelection）。
struct UpNextRow: View {
    let dramas: [Drama]
    let onFocus: (String?) -> Void
    let onCommit: (Drama) -> Void

    @FocusState private var focusedID: String?

    static var posterSize: CGSize { CGSize(width: 160, height: 240) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("接下来")
                    .font(.system(size: TVTheme.TextSize.callout, weight: .bold))
                    .foregroundColor(TVTheme.textPrimary)
                Text(" · 停留预览，按下切换")
                    .font(.system(size: TVTheme.TextSize.caption))
                    .foregroundColor(TVTheme.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 32) {
                    ForEach(dramas) { drama in
                        poster(drama)
                    }
                }
                // 给焦点放大留出空间，不被裁掉。
                .padding(.vertical, 20)
                .padding(.horizontal, 12)
            }
            .frame(width: 1192, alignment: .leading)
            .clipped()
        }
        .focusSection()
        .onChange(of: focusedID) { id in
            onFocus(id)
        }
    }

    private func poster(_ drama: Drama) -> some View {
        let isFocused = focusedID == drama.id
        return Button {
            onCommit(drama)
        } label: {
            TVPosterImage(drama: drama)
                .frame(width: Self.posterSize.width, height: Self.posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: TVTheme.posterRadius, style: .continuous))
        }
        .buttonStyle(TVPressButtonStyle())
        .focused($focusedID, equals: drama.id)
        .tvFocusEffect(focused: isFocused, scale: TVTheme.focusScale, cornerRadius: TVTheme.posterRadius, stroke: false)
        .zIndex(isFocused ? 1 : 0)
    }
}
