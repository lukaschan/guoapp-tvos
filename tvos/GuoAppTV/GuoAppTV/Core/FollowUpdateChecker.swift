import Foundation

/// 追剧更新的后台检查：对追的剧逐部调用核心的 followCheck（读通道，一次一部），记下现有集数。
/// 启动后推荐页第一屏出来时、App 回到前台时各查一次（6 小时内查过的跳过）；「我的」里可以手动全部检查。
/// 已完结的剧不会再出新集，自动检查跳过；追平了的连载剧正是要查的。
@MainActor
final class FollowUpdateChecker: ObservableObject {
    static let shared = FollowUpdateChecker()

    @Published private(set) var isChecking = false
    @Published private(set) var lastFinished: Date?

    private static let completedStatuses: Set<String> = ["finished", "completed"]

    func checkIfDue(store: Store, force: Bool = false) {
        guard !isChecking else { return }
        let now = Date()
        let due = store.follows.filter { follow in
            let completed = Self.completedStatuses.contains(follow.drama.releaseStatus)
            return FollowUpdate.shouldCheck(checkedAt: follow.checkedAt, now: now, finished: completed, force: force)
        }.map(\.drama)
        guard !due.isEmpty else {
            if force { lastFinished = now }
            return
        }
        isChecking = true
        Task {
            for drama in due {
                // 单部失败（网络、下架）跳过，不打断其它的。
                if let fresh = try? await CoreClient.shared.followCheck(drama: drama), fresh.episodes > 0 {
                    store.recordCheck(
                        dramaID: drama.id, latestEpisodes: fresh.episodes, releaseStatus: fresh.releaseStatus, at: Date()
                    )
                }
            }
            isChecking = false
            lastFinished = Date()
        }
    }
}
