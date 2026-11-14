import XCTest
@testable import Writing_Process

/// 5.19 — étiquette courte des chapitres aux titres du plan.
final class ChapterLabelTests: XCTestCase {
    func testShortLabel() {
        XCTAssertEqual(Chapter(name: "4. La « Lingua Nebulae Rexistae » : développement(s)", goal: 0).shortLabel, "Ch. 4")
        XCTAssertEqual(Chapter(name: "10. Conclusion générale", goal: 0).shortLabel, "Ch. 10")
        XCTAssertEqual(Chapter(name: "4.", goal: 0).shortLabel, "4.")
        XCTAssertEqual(Chapter(name: "Intro Partie I", goal: 0).shortLabel, "Intro Partie I")
        XCTAssertEqual(Chapter(name: "1939, ou le dernier soubresaut", goal: 0).shortLabel, "1939, ou le dernier soubresaut")
    }
}
