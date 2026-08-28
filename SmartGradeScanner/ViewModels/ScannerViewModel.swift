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
    let templateAspectRatio: Double

    init(exam: Exam? = nil) {
        self.exam = exam
        let ratio = exam?.template?.definition.pageAspectRatio ?? SampleDataSeeder.template().pageAspectRatio
        self.templateAspectRatio = ratio
        camera.liveDetector.expectedPageAspectRatio = ratio
    }

    func startCamera() async { await camera.configure() }
    func capture() { camera.capture() }

    func process(image: CGImage) {
        selectedImage = image
        guard let imageData = ImageRenderer.jpegData(from: image) else {
            error = .message("تعذر تجهيز الصورة للتحليل.")
            return
        }
        process(imageData: imageData)
    }

    func process(imageData: Data) {
        guard !isProcessing else { return }
        isProcessing = true
        error = nil
        result = nil

        var preparedDefinition = exam?.template?.definition ?? SampleDataSeeder.template()
        if let exam {
            let activeQuestionNumbers = Set(exam.questions.map(\.number))
            preparedDefinition.questions = preparedDefinition.questions.filter { activeQuestionNumbers.contains($0.number) }
        }
        let definition = preparedDefinition

        // Keep a second built-in profile for the portrait five-question reference sheet.
        // We only use it if the primary sheet cannot be aligned, so existing 20-question
        // exams and custom templates keep their original behaviour.
        var portraitFallback = SampleDataSeeder.portraitFiveQuestionTemplate()
        if let exam {
            let activeQuestionNumbers = Set(exam.questions.map(\.number))
            portraitFallback.questions = portraitFallback.questions.filter { activeQuestionNumbers.contains($0.number) }
        }
        let fallbackDefinition: TemplateDefinition? = portraitFallback.questions.isEmpty ? nil : portraitFallback

        guard !definition.questions.isEmpty else {
            error = .message("لا توجد مناطق أسئلة قابلة للمسح لهذا الاختبار. القالب المرفق يدعم ورقة الأسئلة من 1 إلى 20.")
            isProcessing = false
            return
        }
        let key = exam?.answerKey?.entries ?? [:]
        let omrProcessor = processor
        stage = .detectingPaper
        let updateProgress: @MainActor @Sendable (OMRProcessingStage) -> Void = { [weak self] stage in
            self?.stage = stage
        }

        Task { [weak self, omrProcessor] in
            guard let self else { return }
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    do {
                        return try await omrProcessor.process(imageData: imageData,
                                                              template: definition,
                                                              answerKey: key,
                                                              progress: updateProgress)
                    } catch OMRProcessorError.noMarkers {
                        guard let fallbackDefinition else { throw OMRProcessorError.noMarkers }
                        return try await omrProcessor.process(imageData: imageData,
                                                              template: fallbackDefinition,
                                                              answerKey: key,
                                                              progress: updateProgress)
                    } catch DocumentDetectionError.notFound {
                        guard let fallbackDefinition else { throw DocumentDetectionError.notFound }
                        return try await omrProcessor.process(imageData: imageData,
                                                              template: fallbackDefinition,
                                                              answerKey: key,
                                                              progress: updateProgress)
                    }
                }.value
                guard !Task.isCancelled else { return }
                self.result = value
                self.isProcessing = false
            } catch {
                self.error = .message(error.localizedDescription)
                self.isProcessing = false
            }
        }
    }

    func process(uiImage: UIImage) {
        if let image = uiImage.cgImage { selectedImage = image }
        guard let imageData = uiImage.jpegData(compressionQuality: 0.96) else {
            error = .message("تعذر تجهيز الصورة للتحليل.")
            return
        }
        process(imageData: imageData)
    }

    func stopCamera() { camera.stop() }
}
