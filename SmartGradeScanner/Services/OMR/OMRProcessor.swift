import Foundation
import CoreGraphics
import ImageIO

private struct BubbleProbe: Sendable {
    let signal: Double
    let darkness: Double
    let confidence: Double
}

enum OMRProcessorError: LocalizedError {
    case lowQuality(String)
    case noMarkers
    case invalidTemplate(String)

    var errorDescription: String? {
        switch self {
        case .lowQuality(let message):
            return message
        case .noMarkers:
            return "علامات المحاذاة غير كافية أو غير موزعة على الورقة بشكل صحيح. صوّر الورقة كاملة بدون قص الحواف."
        case .invalidTemplate(let message):
            return message
        }
    }
}

struct OMRProcessor: Sendable {
    let documentDetector = DocumentDetectionService()
    let preprocessor = ImagePreprocessor()
    let markerDetector = MarkerDetectionService()
    let qualityAnalyzer = ImageQualityAnalyzer()
    let alignmentService = TemplateAlignmentService()
    let calibrator = ThresholdCalibrator()
    let classifier = BubbleClassifier()
    let idDetector = StudentIDDetector()

    func process(imageData: Data,
                 template: TemplateDefinition,
                 answerKey: [Int: AnswerChoice],
                 progress: @escaping @Sendable @MainActor (OMRProcessingStage) -> Void) async throws -> OMRProcessingResult {
        guard template.pageAspectRatio > 0.20,
              template.pageAspectRatio < 5.0,
              !template.questions.isEmpty,
              template.hasSafeSeparatedRegions else {
            throw OMRProcessorError.invalidTemplate("القالب غير صالح: مناطق الإجابات أو الرقم الجامعي متداخلة أو خارج حدود الورقة.")
        }

        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OMRProcessorError.lowQuality("تعذر قراءة ملف الصورة.")
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) ?? .up
        guard let image = preprocessor.orientedImage(from: rawImage, orientation: orientation) else {
            throw OMRProcessorError.lowQuality("تعذر تصحيح اتجاه الصورة.")
        }

        await progress(.detectingPaper)
        let document = try documentDetector.detect(in: image, expectedAspectRatio: template.pageAspectRatio)

        let imageSize = CGSize(width: image.width, height: image.height)
        let corners = document.normalizedCorners.map {
            CGPoint(x: $0.x * imageSize.width, y: $0.y * imageSize.height)
        }

        guard let corrected = preprocessor.correctedImage(from: image,
                                                           corners: corners,
                                                           targetAspectRatio: template.pageAspectRatio),
              let normalized = preprocessor.normalizedImage(from: corrected),
              let gray = GrayImage(cgImage: normalized) else {
            throw OMRProcessorError.lowQuality("تعذر تصحيح منظور الورقة أو تجهيزها للتحليل.")
        }

        await progress(.checkingQuality)
        let quality = qualityAnalyzer.analyze(normalized)
        guard quality.isUsable else {
            throw OMRProcessorError.lowQuality("الصورة شديدة الضبابية أو مظلمة/مضيئة أكثر من اللازم. ثبّت الهاتف وأعد التصوير بإضاءة متجانسة.")
        }

        await progress(.aligning)
        let markers = markerDetector.detect(in: normalized,
                                            expected: template.markers,
                                            profile: template.calibration)
        let alignment = alignmentService.validate(markers: markers, template: template)
        guard alignment.isCompatible else {
            throw OMRProcessorError.noMarkers
        }

        let studentRegion = template.studentID.map { alignment.transform.apply($0.region) }

        // First pass: measure all configured bubbles, then calibrate the decision
        // threshold from this specific sheet. This is crucial under phone-camera
        // lighting because printed letters/circle outlines are not near a fixed 0.08
        // signal even when the bubble is blank.
        var calibrationSamples: [Double] = []
        for question in template.questions {
            for bubble in question.bubbles {
                if let probe = probe(rect: bubble.rect,
                                     gray: gray,
                                     transform: alignment.transform,
                                     forbiddenRegion: studentRegion) {
                    calibrationSamples.append(probe.signal)
                }
            }
        }
        if let studentID = template.studentID {
            calibrationSamples.append(contentsOf: idDetector.signalSamples(definition: studentID,
                                                                            in: normalized,
                                                                            transform: alignment.transform))
        }
        let calibratedProfile = calibrator.calibratedProfile(samples: calibrationSamples,
                                                              base: template.calibration)

        await progress(.readingStudentID)
        var studentID: String?
        var idConfidence = 1.0
        var warnings: [String] = []
        if let definition = template.studentID {
            let detected = idDetector.detect(definition: definition,
                                             in: normalized,
                                             profile: calibratedProfile,
                                             transform: alignment.transform)
            studentID = detected.value
            idConfidence = detected.confidence
            if let warning = detected.warning { warnings.append(warning) }
        }

        await progress(.readingAnswers)
        let questions = template.questions.sorted { $0.number < $1.number }.map { definition -> OMRQuestionResult in
            let measurements = definition.bubbles.map { bubble -> BubbleMeasurement in
                guard let value = probe(rect: bubble.rect,
                                        gray: gray,
                                        transform: alignment.transform,
                                        forbiddenRegion: studentRegion) else {
                    return BubbleMeasurement(choice: bubble.choice,
                                             fillRatio: 0,
                                             darkness: 0,
                                             confidence: 0)
                }
                return BubbleMeasurement(choice: bubble.choice,
                                         fillRatio: value.signal,
                                         darkness: value.darkness,
                                         confidence: value.confidence)
            }
            let classification = classifier.classify(measurements: measurements,
                                                     profile: calibratedProfile)
            return OMRQuestionResult(questionNumber: definition.number,
                                     selectedChoices: classification.choices,
                                     correctChoice: answerKey[definition.number],
                                     status: classification.status,
                                     confidence: classification.confidence,
                                     measurements: measurements,
                                     weight: definition.weight)
        }

        guard questions.contains(where: { $0.status != .invalidRegion }) else {
            throw OMRProcessorError.lowQuality("لم يتمكن التطبيق من تثبيت مناطق الإجابات على الورقة. أعد التصوير والورقة كاملة داخل الإطار.")
        }

        await progress(.calculating)
        var needsReview = questions.contains {
            $0.status == .weak || $0.status == .uncertain || $0.status == .multiple || $0.status == .invalidRegion
        } || studentID == nil || idConfidence < 0.62

        if !quality.isAcceptable {
            needsReview = true
            warnings.append("جودة الصورة مقبولة للتحليل لكنها ليست مثالية؛ راجع الإجابات المعلّمة قبل الحفظ.")
        }
        if alignment.reprojectionError > template.calibration.markerReprojectionTolerance {
            needsReview = true
            warnings.append("المحاذاة احتاجت تصحيحاً إضافياً بسبب ميل أو انحناء الورقة.")
        }
        if document.usedFullFrameFallback && template.markers.isEmpty {
            needsReview = true
            warnings.append("تم استخدام كامل الصورة كورقة لعدم وجود علامات محاذاة في القالب.")
        }

        let qualityComponent = quality.score
        let alignmentComponent = template.markers.isEmpty ? 1 : alignment.confidence
        let paperConfidence = min(1, max(0,
            Double(document.confidence) * 0.30
            + alignmentComponent * 0.42
            + qualityComponent * 0.28
        ))
        if paperConfidence < 0.66 {
            needsReview = true
            warnings.append("ثقة قراءة الورقة منخفضة نسبياً؛ يفضّل التأكد يدوياً أو إعادة التصوير.")
        }

        await progress(.complete)
        let alignedData = ImageRenderer.jpegData(from: normalized)
        return OMRProcessingResult(studentID: studentID,
                                   questions: questions,
                                   paperConfidence: paperConfidence,
                                   needsReview: needsReview,
                                   warnings: Array(Set(warnings)).sorted(),
                                   alignedImageData: alignedData)
    }

    private func probe(rect: NormalizedRect,
                       gray: GrayImage,
                       transform: AlignmentTransform,
                       forbiddenRegion: CGRect?) -> BubbleProbe? {
        let transformed = transform.apply(rect)
        guard !transformed.isNull,
              transformed.width > 0.002,
              transformed.height > 0.002,
              transformed.midX >= 0,
              transformed.midX <= 1,
              transformed.midY >= 0,
              transformed.midY <= 1 else { return nil }

        if let forbiddenRegion,
           !forbiddenRegion.isNull,
           transformed.intersects(forbiddenRegion) {
            let intersection = transformed.intersection(forbiddenRegion)
            let area = max(transformed.width * transformed.height, 0.000_001)
            let ratio = intersection.isNull ? 0 : (intersection.width * intersection.height) / area
            if ratio > 0.10 { return nil }
        }

        let size = CGSize(width: gray.width, height: gray.height)
        let pixelRect = CGRect(x: transformed.minX * size.width,
                               y: transformed.minY * size.height,
                               width: transformed.width * size.width,
                               height: transformed.height * size.height)
        guard pixelRect.width >= 5, pixelRect.height >= 5 else { return nil }

        let stats = gray.statistics(in: pixelRect)
        let signal = min(1, max(0, stats.fillRatio * 0.72 + stats.darkness * 0.28))
        let confidence = min(1, max(0.08, 0.38 + stats.contrast * 0.48 + abs(stats.fillRatio - 0.5) * 0.12))
        return BubbleProbe(signal: signal, darkness: stats.darkness, confidence: confidence)
    }
}
