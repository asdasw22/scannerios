import Foundation
import Vision

struct DetectedDocument: Sendable {
    let normalizedCorners: [CGPoint]
    let confidence: Float
}

enum DocumentDetectionError: LocalizedError {
    case notFound
    var errorDescription: String? { "لم يتم التعرف على حدود الورقة بشكل واضح. حاول التصوير مرة أخرى." }
}

struct DocumentDetectionService: Sendable {
    func detect(in image: CGImage) async throws -> DetectedDocument {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                guard let observation = (request.results as? [VNRectangleObservation])?.max(by: { $0.confidence < $1.confidence }), observation.confidence >= 0.55 else {
                    continuation.resume(throwing: DocumentDetectionError.notFound); return
                }
                continuation.resume(returning: DetectedDocument(normalizedCorners: [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft], confidence: observation.confidence))
            }
            request.minimumAspectRatio = 0.45; request.maximumAspectRatio = 0.9
            request.minimumSize = 0.35; request.quadratureTolerance = 25
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
            DispatchQueue.global(qos: .userInitiated).async { do { try handler.perform([request]) } catch { continuation.resume(throwing: error) } }
        }
    }
}