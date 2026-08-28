import Foundation
import CoreGraphics

enum AnswerChoice: String, CaseIterable, Codable, Identifiable, Sendable {
    case a = "A", b = "B", c = "C", d = "D", e = "E"
    var id: String { rawValue }
}

enum ResponseStatus: String, Codable, CaseIterable, Sendable {
    case selected, empty, multiple, weak, uncertain, invalidRegion
}

enum MarkerKind: String, Codable, CaseIterable, Sendable {
    case registration, rowGuide
}

enum OMRProcessingStage: String, Codable, CaseIterable, Sendable {
    case detectingPaper = "Detecting paper…"
    case checkingQuality = "Checking image quality…"
    case aligning = "Aligning template…"
    case readingStudentID = "Reading student ID…"
    case readingAnswers = "Reading answers…"
    case calculating = "Calculating score…"
    case complete = "Complete"
}

struct NormalizedRect: Codable, Equatable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    init(_ rect: CGRect, in size: CGSize) {
        let safeWidth = max(size.width, 1), safeHeight = max(size.height, 1)
        self.init(x: rect.minX / safeWidth, y: rect.minY / safeHeight,
                  width: rect.width / safeWidth, height: rect.height / safeHeight)
    }
    func rect(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height,
               width: width * size.width, height: height * size.height)
    }
}

struct BubbleCoordinate: Codable, Equatable, Hashable, Sendable {
    var choice: AnswerChoice
    var rect: NormalizedRect
}

struct TemplateQuestionDefinition: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var number: Int
    var bubbles: [BubbleCoordinate]
    var weight: Double = 1
}

struct StudentIDDefinition: Codable, Equatable, Sendable {
    var region: NormalizedRect
    var columns: [NormalizedRect]
    var digitRows: [NormalizedRect]
    var prefix: String = ""
}

struct MarkerDefinition: Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var kind: MarkerKind
    var expectedRect: NormalizedRect
}

struct CalibrationProfile: Codable, Equatable, Sendable {
    var blankCenter: Double = 0.08
    var blankSpread: Double = 0.04
    var filledCenter: Double = 0.72
    var filledSpread: Double = 0.12
    var decisionBoundary: Double = 0.35
    var weakBoundary: Double = 0.18
    var minimumSelectionMargin: Double = 0.08
    var minimumLocalContrast: Double = 0.08
    var markerReprojectionTolerance: Double = 0.035
    var minimumMarkerCount: Int = 4
}

struct TemplateDefinition: Codable, Equatable, Sendable {
    var pageAspectRatio: Double = 0.707
    var questions: [TemplateQuestionDefinition] = []
    var studentID: StudentIDDefinition?
    var markers: [MarkerDefinition] = []
    var ignoredAreas: [NormalizedRect] = []
    var calibration = CalibrationProfile()
    var revision: Int = 1
}

struct BubbleMeasurement: Codable, Equatable, Sendable {
    var choice: AnswerChoice
    var fillRatio: Double
    var darkness: Double
    var confidence: Double
}

struct OMRQuestionResult: Codable, Equatable, Sendable, Identifiable {
    var id: Int { questionNumber }
    var questionNumber: Int
    var selectedChoices: [AnswerChoice]
    var correctChoice: AnswerChoice?
    var status: ResponseStatus
    var confidence: Double
    var measurements: [BubbleMeasurement]
    var weight: Double = 1
    var isCorrect: Bool { status == .selected && selectedChoices.count == 1 && selectedChoices.first == correctChoice }
}

struct OMRProcessingResult: Codable, Equatable, Sendable {
    var studentID: String?
    var questions: [OMRQuestionResult]
    var paperConfidence: Double
    var needsReview: Bool
    var warnings: [String]
    var alignedImageData: Data?
    var correctCount: Int { questions.filter { $0.isCorrect }.count }
    var wrongCount: Int { questions.filter { !$0.isCorrect && $0.status != .empty }.count }
    var emptyCount: Int { questions.filter { $0.status == .empty }.count }
    var multipleCount: Int { questions.filter { $0.status == .multiple }.count }
    var earnedScore: Double {
        questions.reduce(0) { $0 + ($1.isCorrect ? $1.weight : 0) }
    }
}