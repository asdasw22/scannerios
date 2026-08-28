import Foundation
import CoreGraphics

struct DetectedMarker: Sendable {
    let center: CGPoint
    let confidence: Double
}

struct MarkerDetectionService: Sendable {
    func detect(in image: CGImage, expected: [MarkerDefinition], profile: CalibrationProfile) -> [DetectedMarker] {
        guard let gray = GrayImage(cgImage: image) else { return [] }
        return expected.compactMap { marker in
            let size = CGSize(width: gray.width, height: gray.height)
            let expectedRect = marker.expectedRect.rect(in: size)
            let offsets = stride(from: -0.06, through: 0.06, by: 0.01)
            var best: (rect: CGRect, score: Double, contrast: Double)?
            for yOffset in offsets { for xOffset in offsets {
                let candidate = expectedRect.offsetBy(dx: xOffset * size.width, dy: yOffset * size.height)
                let stats = gray.statistics(in: candidate, inset: 0.05)
                let score = stats.fillRatio * 0.65 + stats.darkness * 0.25 + stats.contrast * 0.10
                if best == nil || score > best!.score { best = (candidate, score, stats.contrast) }
            }}
            guard let best, best.score > 0.48, best.contrast > 0.12 else { return nil }
            return DetectedMarker(center: CGPoint(x: best.rect.midX / size.width, y: best.rect.midY / size.height), confidence: min(1, best.score))
        }
    }
}