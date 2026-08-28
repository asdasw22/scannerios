@preconcurrency import AVFoundation
@preconcurrency import Vision
import Combine
import CoreMedia
import CoreVideo
import CoreGraphics

@MainActor final class LiveDocumentDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    @Published private(set) var documentConfidence: Double = 0
    @Published private(set) var isReady = false
    var expectedPageAspectRatio: Double = 591.0 / 518.0

    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.smartgrade.live-document", qos: .userInitiated)
    private var stableFrames = 0

    func attach(to session: AVCaptureSession) {
        guard !session.outputs.contains(where: { $0 === output }), session.canAddOutput(output) else { return }
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectRectanglesRequest { request, _ in
            let observations = request.results as? [VNRectangleObservation] ?? []
            let observation = observations.max { $0.confidence < $1.confidence }
            let confidence = Double(observation?.confidence ?? 0)
            let aspectRatio: Double
            let area: Double
            if let observation {
                let top = hypot(observation.topRight.x - observation.topLeft.x,
                                observation.topRight.y - observation.topLeft.y)
                let bottom = hypot(observation.bottomRight.x - observation.bottomLeft.x,
                                   observation.bottomRight.y - observation.bottomLeft.y)
                let left = hypot(observation.topLeft.x - observation.bottomLeft.x,
                                 observation.topLeft.y - observation.bottomLeft.y)
                let right = hypot(observation.topRight.x - observation.bottomRight.x,
                                  observation.topRight.y - observation.bottomRight.y)
                aspectRatio = Double((top + bottom) / max(left + right, 0.0001))
                area = Double(observation.boundingBox.width * observation.boundingBox.height)
            } else {
                aspectRatio = 0
                area = 0
            }
            Task { @MainActor [weak self] in
                self?.update(confidence: confidence, aspectRatio: aspectRatio, area: area)
            }
        }
        request.minimumSize = 0.24
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        request.minimumConfidence = 0.30
        request.maximumObservations = 4
        request.quadratureTolerance = 35
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right).perform([request])
    }

    private func update(confidence: Double, aspectRatio: Double, area: Double) {
        let expected = max(expectedPageAspectRatio, 0.001)
        let aspectScore = aspectRatio > 0 ? exp(-abs(log(aspectRatio / expected)) * 3.0) : 0
        let areaScore = min(1, max(0, area / 0.48))
        let score = min(1, max(0, confidence * 0.52 + aspectScore * 0.30 + areaScore * 0.18))
        documentConfidence = score

        if score >= 0.66 && aspectScore >= 0.62 {
            stableFrames = min(6, stableFrames + 1)
        } else {
            stableFrames = max(0, stableFrames - 2)
        }
        isReady = stableFrames >= 3
    }
}
