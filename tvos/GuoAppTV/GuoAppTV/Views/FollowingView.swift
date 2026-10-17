import SwiftUI

struct FollowingView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        NavigationStack {
            Group {
                if store.follows.isEmpty {
                    VStack(spacing: 12) {
                        Text("还没有追剧")
                        Text("在详情页点「追剧」，即可收藏到这里。")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    PosterGrid(items: store.follows.map { $0.drama })
                }
            }
            .padding(.horizontal, 48)
            .navigationTitle("追剧")
            .navigationDestination(for: Drama.self) { drama in
                DetailView(drama: drama)
            }
        }
    }
}
