import XCTest
@testable import SmartGradeScanner

final class BubbleClassifierTests: XCTestCase {
    private let profile = CalibrationProfile()
    private func measurements(_ values: [Double]) -> [BubbleMeasurement] { zip(AnswerChoice.allCases, values).map { BubbleMeasurement(choice: $0.0, fillRatio: $0.1, darkness: $0.1, confidence: 1) } }
    func testSelectedAnswer() { let output = BubbleClassifier().classify(measurements: measurements([0.08, 0.75, 0.09, 0.08, 0.07]), profile: profile); XCTAssertEqual(output.choices, [.b]); XCTAssertEqual(output.status, .selected) }
    func testEmptyAnswer() { let output = BubbleClassifier().classify(measurements: measurements([0.08, 0.1, 0.09, 0.07, 0.08]), profile: profile); XCTAssertEqual(output.status, .empty); XCTAssertTrue(output.choices.isEmpty) }
    func testMultipleAnswers() { let output = BubbleClassifier().classify(measurements: measurements([0.08, 0.72, 0.09, 0.7, 0.08]), profile: profile); XCTAssertEqual(output.status, .multiple); XCTAssertEqual(Set(output.choices), Set([.b, .d])) }
    func testWeakMarkNeedsReview() { let output = BubbleClassifier().classify(measurements: measurements([0.08, 0.25, 0.09, 0.08, 0.07]), profile: profile); XCTAssertEqual(output.status, .weak) }
    func testLowConfidenceIsUncertain() { let weak = measurements([0.08, 0.72, 0.1, 0.08, 0.08]).map { BubbleMeasurement(choice: $0.choice, fillRatio: $0.fillRatio, darkness: $0.darkness, confidence: 0.1) }; let output = BubbleClassifier().classify(measurements: weak, profile: profile); XCTAssertEqual(output.status, .uncertain) }
}