import Foundation
@preconcurrency import Vision
import CoreGraphics
import ImageIO

enum OMRProcessorError: LocalizedError {
    case lowQuality(String)
    case noMarkers
    var errorDescription: String? {
        switch self { case .lowQuality(let message): return message; case .noMarkers: return "علامات المحاذاة غير واضحة. حاول التصوير مرة أخرى." }
    }
}

struct OMRProcessor: Sendable {
    let documentDetector = DocumentDetectionService()
    let preprocessor = ImagePreprocessor()
    let markerDetector = MarkerDetectionService()
    let qualityAnalyzer = ImageQualityAnalyzer()
    let alignmentService = TemplateAlignmentService()
    let classifier = BubbleClassifier()
    let idDetector = StudentIDDetector()

    func process(imageData: Data, template: TemplateDefinition, answerKey: [Int: AnswerChoice], progress: @escaping @Sendable @MainActor (OMRProcessingStage) -> Void) async throws -> OMRProcessingResult {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OMRProcessorError.lowQuality("تعذر قراءة ملف الصورة.")
        }
        await progress(.detectingPaper)
        let document = try documentDetector.detect(in: image)
        guard document.confidence >= 0.55 else { throw OMRProcessorError.lowQuality("الورقة بعيدة أو غير مكتملة في الصورة.") }
        await progress(.checkingQuality)
        let imageSize = CGSize(width: image.width, height: image.height)
        let corners = document.normalizedCorners.map { CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height) }
        guard let corrected = preprocessor.correctedImage(from: image, corners: corners), let normalized = preprocessor.normalizedImage(from: corrected), let gray = GrayImage(cgImage: normalized) else { throw OMRProcessorError.lowQuality("تعذر تحليل جودة الصورة.") }
        let quality = qualityAnalyzer.analyze(normalized)
        guard quality.isAcceptable else { throw OMRProcessorError.lowQuality("الصورة غير واضحة أو الإضاءة غير مناسبة. ثبّت الكاميرا وحاول مرة أخرى.") }
        let markers = markerDetector.detect(in: normalized, expected: template.markers, profile: template.calibration)
        guard template.markers.isEmpty || alignmentService.validate(markers: markers, template: template).isCompatible else { throw OMRProcessorError.noMarkers }
        await progress(.aligning)
        await progress(.readingStudentID)
        var studentID: String?, warnings: [String] = []
        if let definition = template.studentID {
            let detected = idDetector.detect(definition: definition, in: normalized, profile: template.calibration)
            studentID = detected.value; if let warning = detected.warning { warnings.append(warning) }
        }
        await progress(.readingAnswers)
        let size = CGSize(width: gray.width, height: gray.height)
        let questions = template.questions.sorted { $0.number < $1.number }.map { definition -> OMRQuestionResult in
            let measurements = definition.bubbles.map { bubble in
                let stats = gray.statistics(in: bubble.rect.rect(in: size))
                let confidence = min(1, max(0, stats.contrast * 1.8 + 0.25))
                let normalizedFill = min(1, max(0, stats.fillRatio * 0.75 + stats.darkness * 0.25))
                return BubbleMeasurement(choice: bubble.choice, fillRatio: normalizedFill, darkness: stats.darkness, confidence: confidence)
            }
            let classification = classifier.classify(measurements: measurements, profile: template.calibration)
            return OMRQuestionResult(questionNumber: definition.number, selectedChoices: classification.choices,
                                     correctChoice: answerKey[definition.number], status: classification.status,
                                     confidence: classification.confidence, measurements: measurements, weight: definition.weight)
        }
        await progress(.calculating)
        var needsReview = questions.contains { $0.status == .weak || $0.status == .uncertain || $0.status == .multiple } || studentID == nil
        if quality.sharpness < 0.2 || quality.contrast < 0.18 {
            needsReview = true
            warnings.append("Image quality is borderline; verify the highlighted answers before saving.")
        }
        await progress(.complete)
        let alignedData = ImageRenderer.jpegData(from: normalized)
        return OMRProcessingResult(studentID: studentID, questions: questions, paperConfidence: Double(document.confidence) * quality.sharpness, needsReview: needsReview, warnings: warnings, alignedImageData: alignedData)
    }
}