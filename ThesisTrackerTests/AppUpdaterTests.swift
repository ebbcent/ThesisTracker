import XCTest
@testable import Writing_Process

/// Lecture des noms de version publiés par la CI (« v5.7-build23 »).
@MainActor
final class AppUpdaterTests: XCTestCase {
    func testBuildNumberFromTag() {
        XCTAssertEqual(AppUpdater.buildNumber(from: "v5.6-build21"), 21)
        XCTAssertEqual(AppUpdater.buildNumber(from: "v5.10-build123"), 123)
        XCTAssertNil(AppUpdater.buildNumber(from: "v5.6"))
    }

    func testVersionStringFromTag() {
        XCTAssertEqual(AppUpdater.versionString(from: "v5.6-build21"), "5.6")
        XCTAssertEqual(AppUpdater.versionString(from: "5.7-build30"), "5.7")
    }
}
