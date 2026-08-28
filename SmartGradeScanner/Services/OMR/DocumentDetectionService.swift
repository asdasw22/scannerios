import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO

struct DetectedDocument: Sendable {
    let normalizedCorners: [CGPoint]
    let confidence: Float
}

enum DocumentDetectionError: LocalizedError {
    case notFound
    var errorDescription: String? { "لم يتم التعرف على حدود الورقة بشكل واضح. حاول التصوير مرة أخرى." }
}

struct DocumentDetectionService: Sendable {
    func detect(in image: CGImage) throws -> DetectedDocument {
        let request = VNDetectRectanglesRequest()
        request.minimumAspectRatio = 0.45
        request.maximumAspectRatio = 0.9
        request.minimumSize = 0.35
        request.quadratureTolerance = 25
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        guard let observation = (request.results as? [VNRectangleObservation])?.max(by: { $0.confidence < $1.confidence }), observation.confidence >= 0.55 else {
            throw DocumentDetectionError.notFound
        }
        return DetectedDocument(normalizedCorners: [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft], confidence: observation.confidence)
    }
}