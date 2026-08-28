import Foundation
import CoreGraphics
import CoreImage

struct GrayImage: Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(cgImage: CGImage) {
        width = cgImage.width; height = cgImage.height; pixels = []
        guard width > 0, height > 0 else { return nil }
        var values = [UInt8](repeating: 255, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &values, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = values
    }

    func value(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 255 }
        return pixels[y * width + x]
    }

    func statistics(in rect: CGRect, inset: CGFloat = 0.18) -> (fillRatio: Double, darkness: Double, contrast: Double) {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { return (0, 0, 0) }
        let inner = clamped.insetBy(dx: clamped.width * inset, dy: clamped.height * inset)
        var sum = 0.0, sumOutside = 0.0, count = 0, outsideCount = 0, dark = 0
        let minX = Int(inner.minX.rounded(.up)), maxX = Int(inner.maxX.rounded(.down))
        let minY = Int(inner.minY.rounded(.up)), maxY = Int(inner.maxY.rounded(.down))
        for y in minY..<maxY { for x in minX..<maxX {
            let value = Double(self.value(x: x, y: y)); sum += value; count += 1
            if value < 128 { dark += 1 }
        }}
        let outer = clamped.insetBy(dx: -clamped.width * 0.5, dy: -clamped.height * 0.5)
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        for y in Int(outer.minY)..<Int(outer.maxY) { for x in Int(outer.minX)..<Int(outer.maxX) {
            if !inner.contains(CGPoint(x: x, y: y)) { sumOutside += Double(self.value(x: x, y: y)); outsideCount += 1 }
        }}
        let mean = count > 0 ? sum / Double(count) : 255
        let background = outsideCount > 0 ? sumOutside / Double(outsideCount) : 255
        let darkness = max(0, min(1, (background - mean) / 255))
        return (Double(dark) / Double(max(count, 1)), darkness, max(0, min(1, abs(background - mean) / 255)))
    }
}