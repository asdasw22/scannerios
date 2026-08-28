import XCTest
import CoreGraphics
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
        let values = AnswerChoice.allCases.map {
            BubbleMeasurement(choice: $0, fillRatio: 0.82, darkness: 0.82, confidence: 0.1)
        }
        let output = BubbleClassifier().classify(measurements: values, profile: CalibrationProfile())
        XCTAssertNotEqual(output.status, .selected)
        XCTAssertLessThan(output.confidence, 0.65)
    }

    func testAffineAlignmentRecoversSmallCameraShift() {
        let expected: [CGPoint] = [
            CGPoint(x: 0.2, y: 0.15), CGPoint(x: 0.75, y: 0.15),
            CGPoint(x: 0.2, y: 0.55), CGPoint(x: 0.75, y: 0.55),
            CGPoint(x: 0.2, y: 0.92), CGPoint(x: 0.75, y: 0.92)
        ]
        let markers = expected.map { point in
            DetectedMarker(expectedCenter: point,
                           center: CGPoint(x: point.x * 0.985 + 0.012, y: point.y * 1.01 - 0.006),
                           confidence: 0.95,
                           kind: .registration)
        }
        var template = SampleDataSeeder.template()
        template.markers = expected.map {
            MarkerDefinition(kind: .registration,
                             expectedRect: NormalizedRect(x: Double($0.x) - 0.01,
                                                          y: Double($0.y) - 0.01,
                                                          width: 0.02,
                                                          height: 0.02))
        }
        template.calibration.minimumMarkerCount = 5
        let report = TemplateAlignmentService().validate(markers: markers, template: template)
        XCTAssertTrue(report.isCompatible)
        XCTAssertLessThan(report.reprojectionError, 0.01)
    }
}
