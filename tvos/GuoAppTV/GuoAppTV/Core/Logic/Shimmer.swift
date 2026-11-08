import Foundation

/// 骨架屏的闪光：1.4 秒一次的线性扫光；开了「减弱动态效果」时不动。
enum Shimmer {
    static let period: Double = 1.4

    static func animates(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }
}
