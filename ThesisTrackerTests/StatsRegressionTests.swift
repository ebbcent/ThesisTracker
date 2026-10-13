import XCTest
@testable import Writing_Process

/// Régressions sur les statistiques (plantages constatés en usage réel).
@MainActor
final class StatsRegressionTests: XCTestCase {

    /// 13/10/2026 : l'onglet Statistiques plantait dès qu'un chapitre n'avait
    /// aucune entrée (boucle sur 1..<0 dans chapterComparisonRows).
    func testChapterComparisonRowsWithEmptyChapterDoesNotCrash() {
        let store = DataStore.preview
        let emptyChapter = Chapter(name: "Chapitre vide", goal: 20_000)
        store.data.projects[0].chapters.append(emptyChapter)
        defer { store.data.projects[0].chapters.removeAll { $0.id == emptyChapter.id } }

        let rows = store.chapterComparisonRows
        let row = rows.first { $0.id == emptyChapter.id }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.latestTotal, 0)
        XCTAssertEqual(row?.avgCharsPerDay, 0)
    }

    func testChapterComparisonRowsWithSingleEntry() {
        let store = DataStore.preview
        var chapter = Chapter(name: "Une seule entrée", goal: 10_000)
        chapter.entries = [DailyEntry(date: "2026-10-01", totalCount: 2_000, note: nil)]
        store.data.projects[0].chapters.append(chapter)
        defer { store.data.projects[0].chapters.removeAll { $0.id == chapter.id } }

        let row = store.chapterComparisonRows.first { $0.id == chapter.id }
        XCTAssertEqual(row?.latestTotal, 2_000)
        XCTAssertEqual(row?.progressPct, 20)
    }
}
