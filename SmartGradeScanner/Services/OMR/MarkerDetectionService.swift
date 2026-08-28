import Foundation
import CoreGraphics

struct DetectedMarker: Sendable {
    let expectedCenter: CGPoint
    let center: CGPoint
    let confidence: Double
    let kind: MarkerKind
}

struct MarkerDetectionService: Sendable {
    func detect(in image: CGImage,
                expected: [MarkerDefinition],
                profile: CalibrationProfile) -> [DetectedMarker] {
        guard let gray = GrayImage(cgImage: image), !expected.isEmpty else { return [] }
        let size = CGSize(width: gray.width, height: gray.height)

        return expected.compactMap { marker in
            let expectedRect = marker.expectedRect.rect(in: size)
            let baseWidth = max(expectedRect.width, 7)
            let baseHeight = max(expectedRect.height, 7)
            let searchX = max(baseWidth * 1.8, size.width * 0.014)
            let searchY = max(baseHeight * 1.8, size.height * 0.014)
            let stepX = max(2, baseWidth * 0.30)
            let stepY = max(2, baseHeight * 0.30)
            let scales: [CGFloat] = [0.82, 1.0, 1.20]

            var bestRect: CGRect?
            var bestScore = 0.0
            var bestContrast = 0.0
            var bestFill = 0.0

            var y = -searchY
            while y <= searchY {
                var x = -searchX
                while x <= searchX {
                    for scale in scales {
                        let width = baseWidth * scale
                        let height = baseHeight * scale
                        let candidate = CGRect(x: expectedRect.midX + x - width / 2,
                                               y: expectedRect.midY + y - height / 2,
                                               width: width,
                                               height: height)
                        let stats = gray.markerStatistics(in: candidate)
                        let offsetPenalty = min(0.20,
                                                hypot(Double(x / max(searchX, 1)), Double(y / max(searchY, 1))) * 0.08)
                        let score = stats.score - offsetPenalty
                        if score > bestScore {
                            bestScore = score
                            bestRect = candidate
                            bestContrast = stats.contrast
                            bestFill = stats.fillRatio
                        }
                    }
                    x += stepX
                }
                y += stepY
            }

            guard let bestRect,
                  bestScore >= 0.58,
                  bestContrast >= max(0.08, profile.minimumLocalContrast),
                  bestFill >= 0.48 else { return nil }

            return DetectedMarker(
                expectedCenter: marker.expectedRect.center,
                center: CGPoint(x: bestRect.midX / size.width, y: bestRect.midY / size.height),
                confidence: min(1, max(0, bestScore)),
                kind: marker.kind
            )
        }
    }
}
