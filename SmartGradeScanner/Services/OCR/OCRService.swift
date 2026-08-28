import Foundation
import Vision

struct OCRService: Sendable {
    func recognizeText(in image: CGImage) async -> [String] {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let texts = (request.results as? [VNRecognizedTextObservation])?.compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: texts)
            }
            request.recognitionLevel = .fast; request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .utility).async { try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request]) }
        }
    }
}