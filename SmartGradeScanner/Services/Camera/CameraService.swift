@preconcurrency import AVFoundation
import CoreImage
import CoreGraphics
import SwiftUI
import Combine

private final class CameraSessionBox: @unchecked Sendable {
    let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }
}

@MainActor final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    @Published private(set) var lastImageData: Data?
    @Published private(set) var isConfigured = false
    let liveDetector = LiveDocumentDetector()
    private let sessionQueue = DispatchQueue(label: "com.smartgrade.camera.session", qos: .userInitiated)

    func configure() async {
        guard await CameraPermissionService.request(), !isConfigured else { return }
        session.beginConfiguration(); session.sessionPreset = .photo
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input), session.canAddOutput(output) else { session.commitConfiguration(); return }
        session.addInput(input); session.addOutput(output); liveDetector.attach(to: session); session.commitConfiguration(); isConfigured = true
        let sessionBox = CameraSessionBox(session: session)
        sessionQueue.async {
            sessionBox.session.startRunning()
        }
    }

    func capture() { output.capturePhoto(with: AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]), delegate: self) }
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        Task { @MainActor [weak self] in self?.lastImageData = data }
    }
    func stop() { if session.isRunning { session.stopRunning() } }
}