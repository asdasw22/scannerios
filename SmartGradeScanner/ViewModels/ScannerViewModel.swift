import Foundation
import SwiftUI
import CoreGraphics
import Combine
import UIKit

@MainActor final class ScannerViewModel: ObservableObject {
    @Published var stage: OMRProcessingStage = .detectingPaper
    @Published var isProcessing = false
    @Published var error: AppError?
    @Published var result: OMRProcessingResult?
    @Published var isShowingDocumentScanner = false
    @Published var selectedImage: CGImage?
    let camera = CameraService()
    private let processor = OMRProcessor()
    let exam: Exam?

    init(exam: Exam? = nil) { self.exam = exam }
    func startCamera() async { await camera.configure() }
    func capture() { camera.capture() }
    func process(image: CGImage) {
        selectedImage = image; isProcessing = true; error = nil
        let definition = exam?.template?.definition ?? SampleDataSeeder.template()
        let key = exam?.answerKey?.entries ?? [:]
        let updateProgress: @Sendable (OMRProcessingStage) -> Void = { [weak self] stage in
            Task { @MainActor in self?.stage = stage }
        }
        Task.detached(priority: .userInitiated) { [processor] in
            do {
                let value = try await processor.process(image: image, template: definition, answerKey: key, progress: updateProgress)
                await MainActor.run { self.result = value; self.isProcessing = false }
            } catch {
                await MainActor.run { self.error = .message(error.localizedDescription); self.isProcessing = false }
            }
        }
    }
    func process(uiImage: UIImage) { if let image = uiImage.cgImage { process(image: image) } }
    func stopCamera() { camera.stop() }
}