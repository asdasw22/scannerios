import XCTest
@testable import SmartGradeScanner

final class BubbleClassifierTests: XCTestCase {
    private let profile = CalibrationProfile()

    private func measurements(_ values: [Double]) -> [BubbleMeasurement] {
        zip(AnswerChoice.allCases, values).map {
            BubbleMeasurement(choice: $0.0, fillRatio: $0.1, darkness: $0.1, confidence: 1)
        }
    }

    func testSelectedAnswer() {
        let output = BubbleClassifier().classify(measurements: measurements([0.40, 0.91, 0.42, 0.39, 0.41]), profile: profile)
        XCTAssertEqual(output.choices, [.b])
        XCTAssertEqual(output.status, .selected)
    }

    func testEmptyAnswer() {
        let output = BubbleClassifier().classify(measurements: measurements([0.38, 0.43, 0.41, 0.37, 0.40]), profile: profile)
        XCTAssertEqual(output.status, .empty)
        XCTAssertTrue(output.choices.isEmpty)
    }

    func testMultipleAnswers() {
        let output = BubbleClassifier().classify(measurements: measurements([0.39, 0.88, 0.41, 0.86, 0.40]), profile: profile)
        XCTAssertEqual(output.status, .multiple)
        XCTAssertEqual(Set(output.choices), Set([.b, .d]))
    }

    func testWeakMarkNeedsReview() {
        let output = BubbleClassifier().classify(measurements: measurements([0.39, 0.58, 0.41, 0.40, 0.39]), profile: profile)
        XCTAssertEqual(output.status, .weak)
    }

    func testLowConfidenceIsNeverSelectedConfidently() {
        let weak = measurements([0.39, 0.90, 0.41, 0.40, 0.39]).map {
            BubbleMeasurement(choice: $0.choice, fillRatio: $0.fillRatio, darkness: $0.darkness, confidence: 0.1)
        }
        let output = BubbleClassifier().classify(measurements: weak, profile: profile)
        XCTAssertNotEqual(output.status, .selected)
    }
}
