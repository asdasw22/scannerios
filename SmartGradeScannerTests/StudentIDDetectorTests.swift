import XCTest
@testable import SmartGradeScanner

final class StudentIDDetectorTests: XCTestCase {
    func testDefinitionHasNineColumnsAndTenRows() {
        let template = SampleDataSeeder.template(); XCTAssertEqual(template.studentID?.columns.count, 9); XCTAssertEqual(template.studentID?.digitRows.count, 10); XCTAssertEqual(template.studentID?.prefix, "320")
    }
}