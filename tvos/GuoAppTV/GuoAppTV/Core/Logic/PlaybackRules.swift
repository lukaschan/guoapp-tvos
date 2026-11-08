import Foundation

/// 播放页的纯规则（预取下一集、进度落盘节流、换集时预取是否还能用），
/// 由 PlaybackSession 调用；抽出来是为了在 Mac 上单测。
enum PlaybackRules {
    /// 距本集结束还剩多少秒时开始预取下一集。
    static let prefetchLeadSeconds = 10.0
    /// 进度落盘间隔（秒），与 Dart 侧一致。
    static let saveIntervalSeconds = 5.0

    /// 还剩 10 秒（且大于 0）时返回要预取的下一集下标；最后一集、已预取过或正在预取时为 nil。
    static func prefetchIndex(
        position: Double,
        duration: Double,
        currentIndex: Int,
        episodeCount: Int,
        prefetchedIndex: Int?,
        prefetchInFlight: Bool
    ) -> Int? {
        let remaining = duration - position
        guard remaining <= prefetchLeadSeconds, remaining > 0 else { return nil }
        let nextIndex = currentIndex + 1
        guard nextIndex < episodeCount else { return nil }
        guard prefetchedIndex != nextIndex, !prefetchInFlight else { return nil }
        return nextIndex
    }

    /// 与上次落盘的位置相差至少 5 秒才再存一次。
    static func shouldSaveProgress(position: Double, lastSaved: Double) -> Bool {
        abs(position - lastSaved) >= saveIntervalSeconds
    }

    /// 换到 target 集时，预取若是为它或它的下一集准备的就留着，否则释放。
    static func keepsPrefetch(prefetchedIndex: Int?, target: Int) -> Bool {
        prefetchedIndex == target || prefetchedIndex == target + 1
    }
}
