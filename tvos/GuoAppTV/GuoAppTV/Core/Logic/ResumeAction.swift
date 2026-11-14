import Foundation

/// 详情页主按钮做什么：看完了有下一部就「观看下一部」，没有就「重新观看」（从第 1 集开头）；
/// 有观看记录就「继续观看 第 N 集」；否则「立即观看」。
enum ResumeAction: Equatable, Sendable {
    case start
    case resume(episode: Int)
    case nextPart
    case restart

    /// episodeNumbers：详情里分集的集数，按列表顺序（target.index 指向其中一项）。
    static func make(target: ResumeTarget?, episodeNumbers: [Int], isFinished: Bool, hasNextPart: Bool) -> ResumeAction {
        if isFinished { return hasNextPart ? .nextPart : .restart }
        guard let target, target.index > 0 || target.position > 0,
              episodeNumbers.indices.contains(target.index)
        else { return .start }
        return .resume(episode: episodeNumbers[target.index])
    }

    var title: String {
        switch self {
        case .start: return "立即观看"
        case .resume(let episode): return "继续观看 第 \(episode) 集"
        case .nextPart: return "观看下一部"
        case .restart: return "重新观看"
        }
    }
}
