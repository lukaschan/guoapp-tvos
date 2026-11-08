import CoreGraphics
import Foundation
import ImageIO

/// 把封面直接解码成显示所需大小的缩略图（ImageIO），大图不会以原尺寸常驻内存（与 redfruit 一致）。
enum ImageDownsampler {
    /// maxPixelSize：最长边像素数；文件读不了或尺寸不合法时为 nil。
    static func downsample(fileURL: URL, maxPixelSize: Int) -> CGImage? {
        guard maxPixelSize > 0 else { return nil }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }

    /// 显示最长边 points（pt）在 scale 倍屏上需要的像素数（scale 小于 1 按 1 算）。
    static func maxPixelSize(forPoints points: CGFloat, scale: CGFloat) -> Int {
        Int((points * max(scale, 1)).rounded(.up))
    }
}
