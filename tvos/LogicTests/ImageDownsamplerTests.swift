import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GuoAppLogic

struct ImageDownsamplerTests {
    /// 在临时目录写一张纯色 PNG，返回文件地址。
    private func writePNG(width: Int, height: Int) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("downsample-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func downsampleBoundsLongestSide() throws {
        let url = try writePNG(width: 1200, height: 1800)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(ImageDownsampler.downsample(fileURL: url, maxPixelSize: 600))
        #expect(image.width == 400)
        #expect(image.height == 600)
    }

    @Test func smallImageKeepsItsSize() throws {
        let url = try writePNG(width: 300, height: 450)
        defer { try? FileManager.default.removeItem(at: url) }
        let image = try #require(ImageDownsampler.downsample(fileURL: url, maxPixelSize: 924))
        #expect(image.width == 300)
        #expect(image.height == 450)
    }

    @Test func unreadableFileIsNil() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).png")
        #expect(ImageDownsampler.downsample(fileURL: missing, maxPixelSize: 600) == nil)
        #expect(ImageDownsampler.downsample(fileURL: missing, maxPixelSize: 0) == nil)
    }

    @Test func pixelSizeForScale() {
        #expect(ImageDownsampler.maxPixelSize(forPoints: 462, scale: 2) == 924)
        #expect(ImageDownsampler.maxPixelSize(forPoints: 462, scale: 1) == 462)
        #expect(ImageDownsampler.maxPixelSize(forPoints: 462, scale: 0) == 462)
    }
}
