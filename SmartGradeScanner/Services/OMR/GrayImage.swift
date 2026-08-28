import Foundation
import CoreGraphics

struct GrayImage: Sendable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init?(cgImage: CGImage) {
        width = cgImage.width
        height = cgImage.height
        pixels = []
        guard width > 0, height > 0 else { return nil }

        var values = [UInt8](repeating: 255, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &values,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }

        // Normalize the pixel buffer to a top-left origin. Template coordinates use the
        // same convention as a printed page: x grows right, y grows down.
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = values
    }

    func value(x: Int, y: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 255 }
        return pixels[y * width + x]
    }

    func statistics(in rect: CGRect, inset: CGFloat = 0.18) -> (fillRatio: Double, darkness: Double, contrast: Double) {
        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let clamped = rect.standardized.intersection(imageBounds)
        guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return (0, 0, 0) }

        let safeInset = min(max(inset, 0), 0.38)
        let inner = clamped.insetBy(dx: clamped.width * safeInset, dy: clamped.height * safeInset)
        guard inner.width >= 2, inner.height >= 2 else { return (0, 0, 0) }

        let innerValues = sampledValues(in: inner)
        guard !innerValues.isEmpty else { return (0, 0, 0) }

        // Estimate local paper brightness from a robust bright percentile around the
        // bubble. This makes the reader resilient to shadows and uneven lighting.
        let expansionX = max(2, clamped.width * 0.28)
        let expansionY = max(2, clamped.height * 0.28)
        let outer = clamped.insetBy(dx: -expansionX, dy: -expansionY).intersection(imageBounds)
        var backgroundValues: [Double] = []
        if !outer.isNull {
            let minX = max(0, Int(outer.minX.rounded(.down)))
            let maxX = min(width, Int(outer.maxX.rounded(.up)))
            let minY = max(0, Int(outer.minY.rounded(.down)))
            let maxY = min(height, Int(outer.maxY.rounded(.up)))
            backgroundValues.reserveCapacity(max((maxX - minX) * (maxY - minY) / 3, 16))
            for y in minY..<maxY {
                for x in minX..<maxX {
                    if !clamped.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        backgroundValues.append(Double(value(x: x, y: y)))
                    }
                }
            }
        }

        let localBackground: Double
        if backgroundValues.count >= 8 {
            localBackground = percentile(backgroundValues, 0.75)
        } else {
            // Bright pixels inside a blank bubble still represent paper better than a
            // global threshold. For a filled bubble this branch is rarely used.
            localBackground = percentile(innerValues, 0.90)
        }

        let background = min(255, max(70, localBackground))
        let adaptiveDrop = max(18.0, background * 0.085)
        let adaptiveThreshold = max(35, min(235, background - adaptiveDrop))

        let darkCount = innerValues.reduce(into: 0) { count, pixel in
            if pixel < adaptiveThreshold { count += 1 }
        }
        let fillRatio = Double(darkCount) / Double(max(innerValues.count, 1))
        let mean = innerValues.reduce(0, +) / Double(innerValues.count)
        let lowerQuartile = percentile(innerValues, 0.25)

        let darkness = clamp((background - mean) / max(background, 90))
        let contrast = clamp((background - lowerQuartile) / 180)
        return (fillRatio, darkness, contrast)
    }

    func markerStatistics(in rect: CGRect) -> (score: Double, contrast: Double, fillRatio: Double) {
        let stats = statistics(in: rect, inset: 0.10)
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clamped.isNull else { return (0, 0, 0) }
        let values = sampledValues(in: clamped.insetBy(dx: clamped.width * 0.08, dy: clamped.height * 0.08))
        guard !values.isEmpty else { return (0, 0, 0) }

        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        let uniformity = clamp(1 - sqrt(variance) / 100)
        let score = clamp(stats.fillRatio * 0.58 + stats.darkness * 0.27 + stats.contrast * 0.15) * (0.72 + uniformity * 0.28)
        return (score, stats.contrast, stats.fillRatio)
    }

    func lightFraction(in rect: CGRect, threshold: UInt8 = 150, step: Int = 3) -> Double {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !clamped.isNull else { return 0 }
        let minX = max(0, Int(clamped.minX))
        let maxX = min(width, Int(clamped.maxX))
        let minY = max(0, Int(clamped.minY))
        let maxY = min(height, Int(clamped.maxY))
        var light = 0
        var count = 0
        for y in stride(from: minY, to: maxY, by: max(step, 1)) {
            for x in stride(from: minX, to: maxX, by: max(step, 1)) {
                count += 1
                if value(x: x, y: y) >= threshold { light += 1 }
            }
        }
        return Double(light) / Double(max(count, 1))
    }

    private func sampledValues(in rect: CGRect) -> [Double] {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return [] }
        let minX = max(0, Int(rect.minX.rounded(.up)))
        let maxX = min(width, Int(rect.maxX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.up)))
        let maxY = min(height, Int(rect.maxY.rounded(.down)))
        guard minX < maxX, minY < maxY else { return [] }

        var result: [Double] = []
        result.reserveCapacity((maxX - minX) * (maxY - minY))
        for y in minY..<maxY {
            for x in minX..<maxX {
                result.append(Double(value(x: x, y: y)))
            }
        }
        return result
    }

    private func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 255 }
        let sorted = values.sorted()
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
