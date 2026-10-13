import XCTest
@testable import Writing_Process

/// Import de tableaux (CSV, copier-coller depuis Excel ou Numbers).
@MainActor
final class ImportParsingTests: XCTestCase {

    func testISODateAndCountWithThinSpaces() {
        let entry = ImportView.parseRow(["2024-01-15", "12 345"])
        XCTAssertEqual(entry?.date, "2024-01-15")
        XCTAssertEqual(entry?.count, 12_345)
    }

    func testFrenchDateAndThousandsSeparator() {
        let entry = ImportView.parseRow(["15/01/2024", "1.234"])
        XCTAssertEqual(entry?.date, "2024-01-15")
        XCTAssertEqual(entry?.count, 1_234)
    }

    func testSingleDigitDayIsADateNotACount() {
        let entry = ImportView.parseRow(["1.3.2024", "5000"])
        XCTAssertEqual(entry?.date, "2024-03-01")
        XCTAssertEqual(entry?.count, 5_000)
    }

    func testExcelSerialDateHasNoOffByOne() {
        // 45306 = 15 janvier 2024 dans Excel (système 1900).
        let entry = ImportView.parseRow(["45306", "12000"])
        XCTAssertEqual(entry?.date, "2024-01-15")
        XCTAssertEqual(entry?.count, 12_000)
    }

    func testRowWithoutDateIsIgnored() {
        XCTAssertNil(ImportView.parseRow(["Total", "12000"]))
    }
}
