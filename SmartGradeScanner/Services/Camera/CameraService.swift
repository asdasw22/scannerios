import AVFoundation
import CoreImage
import SwiftUI
import Combine

@MainActor final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published private(set) var lastImage: CGImage?
    @Published private(set) var isConfigured = false
    let liveDetector = LiveDocumentDetector()

    func configure() async {
        guard await CameraPermissionService.request(), !isConfigured else { return }
        session.beginConfiguration(); session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addInput(input); session.addOutput(output); liveDetector.attach(to: session); session.commitConfiguration(); isConfigured = true
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    func capture() { output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self) }
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = CIImage(data: data), let cgImage = CIContext().createCGImage(image, from: image.extent) else { return }
        Task { @MainActor in self.lastImage = cgImage }
    }
    func stop() { if session.isRunning { session.stopRunning() } }
}