import Foundation
import CoreGraphics

struct ImageQualityReport: Sendable {
    let sharpness: Double
    let brightness: Double
    let contrast: Double
    var isAcceptable: Bool { sharpness >= 0.08 && brightness >= 0.12 && brightness <= 0.99 && contrast >= 0.08 }
}

struct ImageQualityAnalyzer: Sendable {
    func analyze(_ image: CGImage) -> ImageQualityReport {
        guard let gray = GrayImage(cgImage: image), !gray.pixels.isEmpty else { return ImageQualityReport(sharpness: 0, brightness: 0, contrast: 0) }
        let values = gray.pixels.map(Double.init); let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        var edges = 0.0
        if gray.width > 1 && gray.height > 1 { for y in stride(from: 1, to: gray.height, by: 2) { for x in stride(from: 1, to: gray.width, by: 2) { edges += abs(Double(gray.value(x: x, y: y)) - Double(gray.value(x: x - 1, y: y))) + abs(Double(gray.value(x: x, y: y)) - Double(gray.value(x: x, y: y - 1))) } } }
        return ImageQualityReport(sharpness: min(1, edges / Double(max(gray.width * gray.height / 4, 1)) / 80), brightness: mean / 255, contrast: min(1, sqrt(variance) / 100))
    }
}