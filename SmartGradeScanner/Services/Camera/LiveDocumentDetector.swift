@preconcurrency import AVFoundation
@preconcurrency import Vision
import Combine
import CoreMedia
import CoreVideo

@MainActor final class LiveDocumentDetector: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, ObservableObject {
    @Published private(set) var documentConfidence: Double = 0
    @Published private(set) var isReady = false
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.smartgrade.live-document", qos: .userInitiated)

    func attach(to session: AVCaptureSession) {
        guard !session.outputs.contains(where: { $0 === output }), session.canAddOutput(output) else { return }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue); session.addOutput(output)
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectRectanglesRequest { request, _ in
            let observation = (request.results as? [VNRectangleObservation])?.max { $0.confidence < $1.confidence }
            let confidence = Double(observation?.confidence ?? 0)
            Task { @MainActor [weak self] in self?.update(confidence: confidence) }
        }
        request.minimumSize = 0.35; request.minimumAspectRatio = 0.45; request.maximumAspectRatio = 0.9; request.quadratureTolerance = 25
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .right).perform([request])
    }

    private func update(confidence: Double) { documentConfidence = confidence; isReady = confidence >= 0.72 }
}