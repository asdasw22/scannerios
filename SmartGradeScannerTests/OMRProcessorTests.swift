import XCTest
@testable import SmartGradeScanner

final class OMRProcessorTests: XCTestCase {
    func testNormalizedCoordinatesRemainStableAcrossImageSizes() {
        let coordinate = NormalizedRect(x: 0.25, y: 0.4, width: 0.1, height: 0.08)
        let small = coordinate.rect(in: CGSize(width: 1000, height: 1400))
        let large = coordinate.rect(in: CGSize(width: 2000, height: 2800))
        XCTAssertEqual(small.midX / 1000, large.midX / 2000, accuracy: 0.0001)
        XCTAssertEqual(small.midY / 1400, large.midY / 2800, accuracy: 0.0001)
    }

    func testPerspectiveReprojectionErrorIsMeasured() {
        let source = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let distorted = [CGPoint(x: 0.02, y: 0.01), CGPoint(x: 0.99, y: 0.04), CGPoint(x: 0.96, y: 0.98), CGPoint(x: 0.01, y: 0.95)]
        XCTAssertLessThan(HomographySolver().reprojectionError(source: source, destination: distorted), 0.06)
    }

    func testLowConfidenceClassificationNeverSelectsConfidently() {
        let values = AnswerChoice.allCases.map { BubbleMeasurement(choice: $0, fillRatio: 0.36, darkness: 0.36, confidence: 0.2) }
        let output = BubbleClassifier().classify(measurements: values, profile: CalibrationProfile())
        XCTAssertNotEqual(output.status, .selected)
        XCTAssertLessThan(output.confidence, 0.65)
    }
}