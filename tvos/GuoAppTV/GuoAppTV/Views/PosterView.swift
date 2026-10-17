import SwiftUI
import UIKit

/// 海报内存缓存：同一张海报只向核心请求一次本地文件。
actor PosterCache {
    static let shared = PosterCache()

    private var images: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for drama: Drama) async -> UIImage? {
        let key = "\(drama.id)\0\(drama.cover)"
        if let cached = images[key] { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task.detached {
            do {
                let path = try await CoreClient.shared.coverPath(for: drama)
                return UIImage(contentsOfFile: path)
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { images[key] = result }
        return result
    }
}

struct PosterView: View {
    let drama: Drama
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(2 / 3, contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Text(drama.title)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(8)
                }
                .aspectRatio(2 / 3, contentMode: .fit)
            }
        }
        .clipped()
        .task {
            image = await PosterCache.shared.image(for: drama)
        }
    }
}

/// 海报网格：首页 / 搜索 / 追剧共用，点海报进详情。
/// `onReachEnd` 供首页无限滚动：最后一个海报出现时回调，由调用方拉下一页。
struct PosterGrid: View {
    let items: [Drama]
    var onReachEnd: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 28)],
                spacing: 28
            ) {
                ForEach(items) { drama in
                    NavigationLink(value: drama) {
                        VStack(alignment: .leading, spacing: 8) {
                            PosterView(drama: drama)
                            Text(drama.title)
                                .font(.system(size: 18))
                                .lineLimit(2)
                            Text(drama.category.isEmpty ? drama.releaseLabel : drama.category)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .onAppear {
                        if drama.id == items.last?.id {
                            onReachEnd?()
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }
}
