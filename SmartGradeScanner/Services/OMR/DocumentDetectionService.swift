import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO

struct DetectedDocument: Sendable {
    let normalizedCorners: [CGPoint]
    let confidence: Float
    let usedFullFrameFallback: Bool
}

enum DocumentDetectionError: LocalizedError {
    case notFound

    var errorDescription: String? {
        "لم يتم التعرف على حدود الورقة بشكل واضح. حاول وضع الورقة كاملة داخل الإطار أو استخدم وضع Document."
    }
}

struct DocumentDetectionService: Sendable {
    func detect(in image: CGImage, expectedAspectRatio: Double) throws -> DetectedDocument {
        let request = VNDetectRectanglesRequest()
        let expectedShortLong = Float(min(expectedAspectRatio, 1 / max(expectedAspectRatio, 0.001)))
        request.minimumAspectRatio = max(0.35, expectedShortLong - 0.24)
        request.maximumAspectRatio = min(1.0, expectedShortLong + 0.24)
        request.minimumSize = 0.24
        request.minimumConfidence = 0.30
        request.maximumObservations = 8
        request.quadratureTolerance = 35

        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        let observations = request.results ?? []

        if let best = observations.max(by: {
            candidateScore($0, expectedAspectRatio: expectedAspectRatio) < candidateScore($1, expectedAspectRatio: expectedAspectRatio)
        }) {
            let score = candidateScore(best, expectedAspectRatio: expectedAspectRatio)
            if best.confidence >= 0.40, score >= 0.46 {
                return DetectedDocument(
                    normalizedCorners: [best.topLeft, best.topRight, best.bottomRight, best.bottomLeft],
                    confidence: Float(min(1, max(Double(best.confidence), score))),
                    usedFullFrameFallback: false
                )
            }
        }

        // VisionKit already returns a cropped, perspective-corrected page. Running a
        // second rectangle detector on such an image often has no outer background to
        // detect. When the whole frame looks like paper and its aspect ratio matches the
        // configured sheet, accept the frame instead of failing or locking onto an
        // internal answer/ID box.
        if canUseFullFrameFallback(image: image, expectedAspectRatio: expectedAspectRatio) {
            return DetectedDocument(
                normalizedCorners: [
                    CGPoint(x: 0, y: 1),
                    CGPoint(x: 1, y: 1),
                    CGPoint(x: 1, y: 0),
                    CGPoint(x: 0, y: 0)
                ],
                confidence: 0.78,
                usedFullFrameFallback: true
            )
        }

        throw DocumentDetectionError.notFound
    }

    private func candidateScore(_ observation: VNRectangleObservation, expectedAspectRatio: Double) -> Double {
        let top = distance(observation.topLeft, observation.topRight)
        let bottom = distance(observation.bottomLeft, observation.bottomRight)
        let left = distance(observation.topLeft, observation.bottomLeft)
        let right = distance(observation.topRight, observation.bottomRight)
        let observedRatio = Double((top + bottom) / max(left + right, 0.0001))
        let ratioDelta = abs(log(max(observedRatio, 0.001) / max(expectedAspectRatio, 0.001)))
        let aspectScore = exp(-ratioDelta * 3.0)

        let area = polygonArea([observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft])
        let areaScore = min(1, max(0, Double(area) / 0.62))

        let center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
        let centerDistance = hypot(Double(center.x - 0.5), Double(center.y - 0.5))
        let centerScore = min(1, max(0, 1 - centerDistance / 0.70))

        return Double(observation.confidence) * 0.44 + aspectScore * 0.28 + areaScore * 0.23 + centerScore * 0.05
    }

    private func canUseFullFrameFallback(image: CGImage, expectedAspectRatio: Double) -> Bool {
        guard image.width >= 500, image.height >= 350 else { return false }
        let imageRatio = Double(image.width) / Double(max(image.height, 1))
        let ratioDelta = abs(log(max(imageRatio, 0.001) / max(expectedAspectRatio, 0.001)))
        guard ratioDelta <= log(1.28) else { return false }
        guard let gray = GrayImage(cgImage: image) else { return false }

        let w = CGFloat(gray.width)
        let h = CGFloat(gray.height)
        let strip = max(6, min(w, h) * 0.035)
        let edges = [
            CGRect(x: 0, y: 0, width: w, height: strip),
            CGRect(x: 0, y: h - strip, width: w, height: strip),
            CGRect(x: 0, y: 0, width: strip, height: h),
            CGRect(x: w - strip, y: 0, width: strip, height: h)
        ]
        let edgeLightness = edges.map { gray.lightFraction(in: $0, threshold: 135, step: 5) }.reduce(0, +) / Double(edges.count)
        return edgeLightness >= 0.52
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func polygonArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            sum += points[index].x * next.y - next.x * points[index].y
        }
        return abs(sum) / 2
    }
}
