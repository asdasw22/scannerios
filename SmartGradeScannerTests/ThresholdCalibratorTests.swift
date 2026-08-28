import XCTest
@testable import SmartGradeScanner

final class ThresholdCalibratorTests: XCTestCase {
    func testSeparatesBlankAndFilledSamples() { let profile = ThresholdCalibrator().calibratedProfile(samples: [0.05, 0.08, 0.09, 0.11, 0.68, 0.72, 0.75, 0.8]); XCTAssertGreaterThan(profile.decisionBoundary, profile.blankCenter); XCTAssertLessThan(profile.decisionBoundary, profile.filledCenter) }
    func testKeepsBaseForUnseparatedSamples() { let base = CalibrationProfile(); XCTAssertEqual(ThresholdCalibrator().calibratedProfile(samples: [0.1, 0.11, 0.12], base: base), base) }
}