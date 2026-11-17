import XCTest
@testable import Writing_Process

/// 5.24 — découpage des titres de chapitre (affichage Tuiles, récap du mois).
final class TilesAndRecapTests: XCTestCase {
    func testNumberedTitleWithSubtitle() {
        let t = TilesChapterTitle("4. La « Lingua Nebulae Rexistae » : développement(s) et diffusion(s) d'un langage politique")
        XCTAssertEqual(t.number, "4")
        XCTAssertEqual(t.title, "La « Lingua Nebulae Rexistae »")
        XCTAssertEqual(t.subtitle, "développement(s) et diffusion(s) d'un langage politique")
    }

    func testNumberedTitleWithoutSubtitle() {
        let t = TilesChapterTitle("7. Léon Degrelle, un homme, un chef")
        XCTAssertEqual(t.number, "7")
        XCTAssertEqual(t.title, "Léon Degrelle, un homme, un chef")
        XCTAssertNil(t.subtitle)
    }

    func testPlainTitle() {
        let t = TilesChapterTitle("Dictionnaire rexistes")
        XCTAssertNil(t.number)
        XCTAssertEqual(t.title, "Dictionnaire rexistes")
        XCTAssertNil(t.subtitle)
    }

    func testYearIsNotAChapterNumber() {
        // « 1939, ou le dernier… » : pas de point après le nombre, donc pas de numéro.
        let t = TilesChapterTitle("1939, ou le dernier soubresaut")
        XCTAssertNil(t.number)
        XCTAssertEqual(t.title, "1939, ou le dernier soubresaut")
    }

    func testMonthKeyAndPreviousMonth() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 17
        let now = DataStore.gregorianCal.date(from: c)!
        let previous = MonthlyRecap.previousMonthStart(from: now)
        XCTAssertEqual(MonthlyRecap.monthKey(previous), "2026-10")
        XCTAssertEqual(MonthlyRecap.monthName(previous), "octobre")
    }

    func testPreviousMonthAcrossYear() {
        var c = DateComponents(); c.year = 2027; c.month = 1; c.day = 1
        let now = DataStore.gregorianCal.date(from: c)!
        XCTAssertEqual(MonthlyRecap.monthKey(MonthlyRecap.previousMonthStart(from: now)), "2026-12")
    }
}
