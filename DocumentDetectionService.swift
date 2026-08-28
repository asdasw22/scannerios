import CoreGraphics
import Foundation
import ImageIO
@preconcurrency import Vision

struct DetectedDocument: Sendable {
  let normalizedCorners: [CGPoint]
  let confidence: Float
  let usedFullFrameFallback: Bool
}

enum DocumentDetectionError: LocalizedError {
  case notFound

  var errorDescription: String? {
    "The full answer sheet was not detected. Keep all four page edges and black registration marks visible."
  }
}

struct DocumentDetectionService: Sendable {
  func detect(in image: CGImage, expectedAspectRatio: Double) throws -> DetectedDocument {
    let request = VNDetectRectanglesRequest()
    let expectedShortLong = Float(min(expectedAspectRatio, 1 / max(expectedAspectRatio, 0.001)))
    request.minimumAspectRatio = max(0.40, expectedShortLong - 0.18)
    request.maximumAspectRatio = min(1.0, expectedShortLong + 0.18)
    request.minimumSize = 0.22
    request.minimumConfidence = 0.30
    request.maximumObservations = 10
    request.quadratureTolerance = 32

    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    let observations = request.results ?? []

    let candidates = observations.compactMap { observation -> (VNRectangleObservation, Double)? in
      let area = polygonArea([
        observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft,
      ])
      guard area >= 0.28 else { return nil }
      let score = candidateScore(observation, expectedAspectRatio: expectedAspectRatio)
      guard score >= 0.48 else { return nil }
      return (observation, score)
    }

    if let best = candidates.max(by: { $0.1 < $1.1 }) {
      let observation = best.0
      if observation.confidence >= 0.38 {
        return DetectedDocument(
          normalizedCorners: [
            observation.topLeft, observation.topRight, observation.bottomRight,
            observation.bottomLeft,
          ],
          confidence: Float(min(1, max(Double(observation.confidence), best.1))),
          usedFullFrameFallback: false
        )
      }
    }

    // VisionKit often returns an already-cropped page. Only accept the full frame
    // when its geometry and bright page edges agree with the configured template.
    if canUseFullFrameFallback(image: image, expectedAspectRatio: expectedAspectRatio) {
      return DetectedDocument(
        normalizedCorners: [
          CGPoint(x: 0, y: 1),
          CGPoint(x: 1, y: 1),
          CGPoint(x: 1, y: 0),
          CGPoint(x: 0, y: 0),
        ],
        confidence: 0.82,
        usedFullFrameFallback: true
      )
    }

    throw DocumentDetectionError.notFound
  }

  private func candidateScore(_ observation: VNRectangleObservation, expectedAspectRatio: Double)
    -> Double
  {
    let top = distance(observation.topLeft, observation.topRight)
    let bottom = distance(observation.bottomLeft, observation.bottomRight)
    let left = distance(observation.topLeft, observation.bottomLeft)
    let right = distance(observation.topRight, observation.bottomRight)
    let observedRatio = Double((top + bottom) / max(left + right, 0.0001))
    let ratioDelta = abs(log(max(observedRatio, 0.001) / max(expectedAspectRatio, 0.001)))
    let aspectScore = exp(-ratioDelta * 4.2)

    let area = polygonArea([
      observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft,
    ])
    let areaScore = min(1, max(0, Double(area) / 0.60))

    let center = CGPoint(x: observation.boundingBox.midX, y: observation.boundingBox.midY)
    let centerDistance = hypot(Double(center.x - 0.5), Double(center.y - 0.5))
    let centerScore = min(1, max(0, 1 - centerDistance / 0.65))

    return Double(observation.confidence) * 0.38
      + aspectScore * 0.31
      + areaScore * 0.27
      + centerScore * 0.04
  }

  private func canUseFullFrameFallback(image: CGImage, expectedAspectRatio: Double) -> Bool {
    guard image.width >= 500, image.height >= 350 else { return false }
    let imageRatio = Double(image.width) / Double(max(image.height, 1))
    let ratioDelta = abs(log(max(imageRatio, 0.001) / max(expectedAspectRatio, 0.001)))
    guard ratioDelta <= log(1.20) else { return false }
    guard let gray = GrayImage(cgImage: image) else { return false }

    let w = CGFloat(gray.width)
    let h = CGFloat(gray.height)
    let strip = max(6, min(w, h) * 0.030)
    let edges = [
      CGRect(x: 0, y: 0, width: w, height: strip),
      CGRect(x: 0, y: h - strip, width: w, height: strip),
      CGRect(x: 0, y: 0, width: strip, height: h),
      CGRect(x: w - strip, y: 0, width: strip, height: h),
    ]
    let edgeLightness =
      edges.map { gray.lightFraction(in: $0, threshold: 140, step: 5) }.reduce(0, +)
      / Double(edges.count)
    return edgeLightness >= 0.60
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
