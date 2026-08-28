import CoreGraphics
import Foundation

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
    guard
      let context = CGContext(
        data: &values,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.none.rawValue)
    else { return nil }

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

  // Generic rectangular statistics. Kept for quality and marker analysis.
  func statistics(in rect: CGRect, inset: CGFloat = 0.18) -> (
    fillRatio: Double, darkness: Double, contrast: Double
  ) {
    let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
    let clamped = rect.standardized.intersection(imageBounds)
    guard !clamped.isNull, clamped.width >= 4, clamped.height >= 4 else { return (0, 0, 0) }

    let safeInset = min(max(inset, 0), 0.38)
    let inner = clamped.insetBy(dx: clamped.width * safeInset, dy: clamped.height * safeInset)
    guard inner.width >= 2, inner.height >= 2 else { return (0, 0, 0) }

    let innerValues = sampledValues(in: inner)
    guard !innerValues.isEmpty else { return (0, 0, 0) }
    let background = localBackground(
      around: clamped, excluding: clamped, fallbackValues: innerValues)
    return signalStatistics(values: innerValues, background: background)
  }

  // Bubble-specific statistics use an ellipse mask to exclude the printed circle border.
  // This prevents the OMR engine from confusing a dark outline with a filled mark.
  func bubbleStatistics(in rect: CGRect) -> (fillRatio: Double, darkness: Double, contrast: Double)
  {
    let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
    let clamped = rect.standardized.intersection(imageBounds)
    guard !clamped.isNull, clamped.width >= 6, clamped.height >= 6 else { return (0, 0, 0) }

    let center = CGPoint(x: clamped.midX, y: clamped.midY)
    let radiusX = max(2.0, clamped.width * 0.34)
    let radiusY = max(2.0, clamped.height * 0.34)
    let minX = max(0, Int((center.x - radiusX).rounded(.down)))
    let maxX = min(width, Int((center.x + radiusX).rounded(.up)))
    let minY = max(0, Int((center.y - radiusY).rounded(.down)))
    let maxY = min(height, Int((center.y + radiusY).rounded(.up)))

    var coreValues: [Double] = []
    coreValues.reserveCapacity(max((maxX - minX) * (maxY - minY), 16))
    for y in minY..<maxY {
      for x in minX..<maxX {
        let nx = (CGFloat(x) + 0.5 - center.x) / radiusX
        let ny = (CGFloat(y) + 0.5 - center.y) / radiusY
        if nx * nx + ny * ny <= 1.0 {
          coreValues.append(Double(value(x: x, y: y)))
        }
      }
    }
    guard coreValues.count >= 8 else { return (0, 0, 0) }

    let expansionX = max(3, clamped.width * 0.38)
    let expansionY = max(3, clamped.height * 0.38)
    let outer = clamped.insetBy(dx: -expansionX, dy: -expansionY).intersection(imageBounds)
    let background = localBackground(around: outer, excluding: clamped, fallbackValues: coreValues)
    return signalStatistics(values: coreValues, background: background)
  }

  func markerStatistics(in rect: CGRect) -> (score: Double, contrast: Double, fillRatio: Double) {
    let stats = statistics(in: rect, inset: 0.08)
    let clamped = rect.intersection(CGRect(x: 0, y: 0, width: width, height: height))
    guard !clamped.isNull else { return (0, 0, 0) }
    let values = sampledValues(
      in: clamped.insetBy(dx: clamped.width * 0.06, dy: clamped.height * 0.06))
    guard !values.isEmpty else { return (0, 0, 0) }

    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
    let uniformity = clamp(1 - sqrt(variance) / 92)
    let score =
      clamp(stats.fillRatio * 0.62 + stats.darkness * 0.25 + stats.contrast * 0.13)
      * (0.68 + uniformity * 0.32)
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

  private func signalStatistics(values: [Double], background rawBackground: Double) -> (
    fillRatio: Double, darkness: Double, contrast: Double
  ) {
    guard !values.isEmpty else { return (0, 0, 0) }
    let background = min(255, max(70, rawBackground))
    let adaptiveDrop = max(18.0, background * 0.085)
    let adaptiveThreshold = max(35, min(235, background - adaptiveDrop))
    let darkCount = values.reduce(into: 0) { count, pixel in
      if pixel < adaptiveThreshold { count += 1 }
    }
    let fillRatio = Double(darkCount) / Double(values.count)
    let mean = values.reduce(0, +) / Double(values.count)
    let lowerQuartile = percentile(values, 0.25)
    let darkness = clamp((background - mean) / max(background, 90))
    let contrast = clamp((background - lowerQuartile) / 180)
    return (fillRatio, darkness, contrast)
  }

  private func localBackground(
    around outerRect: CGRect,
    excluding excludedRect: CGRect,
    fallbackValues: [Double]
  ) -> Double {
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    let outer = outerRect.intersection(bounds)
    var values: [Double] = []
    if !outer.isNull {
      let minX = max(0, Int(outer.minX.rounded(.down)))
      let maxX = min(width, Int(outer.maxX.rounded(.up)))
      let minY = max(0, Int(outer.minY.rounded(.down)))
      let maxY = min(height, Int(outer.maxY.rounded(.up)))
      values.reserveCapacity(max((maxX - minX) * (maxY - minY) / 3, 16))
      for y in minY..<maxY {
        for x in minX..<maxX {
          let point = CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)
          if !excludedRect.contains(point) {
            values.append(Double(value(x: x, y: y)))
          }
        }
      }
    }
    if values.count >= 8 { return percentile(values, 0.78) }
    return percentile(fallbackValues, 0.90)
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
