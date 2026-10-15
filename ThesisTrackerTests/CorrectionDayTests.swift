import XCTest
@testable import Writing_Process

/// Jours de correction : le total du jour peut baisser, et le jour peut être
/// marqué « Correction » pour ne pas casser la série.
@MainActor
final class CorrectionDayTests: XCTestCase {

    private func day(_ offset: Int) -> String {
        let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: -offset, to: Date())!
        return DataStore.dateString(from: date)
    }

    func testOldEntryWithoutFlagDecodesAsNotCorrection() throws {
        let json = #"{"date":"2026-10-01","totalCount":1200}"#.data(using: .utf8)!
        let entry = try JSONDecoder().decode(DailyEntry.self, from: json)
        XCTAssertFalse(entry.isCorrection)
    }

    func testFlagSurvivesRoundTrip() throws {
        var entry = DailyEntry(date: "2026-10-01", totalCount: 1200)
        entry.isCorrection = true
        let decoded = try JSONDecoder().decode(DailyEntry.self, from: JSONEncoder().encode(entry))
        XCTAssertTrue(decoded.isCorrection)
    }

    func testNetChangeIsNegativeWhenTextWasRemoved() {
        var chapter = Chapter(name: "Ch", goal: 10_000)
        chapter.entries = [DailyEntry(date: "2026-10-01", totalCount: 5_000),
                           DailyEntry(date: "2026-10-02", totalCount: 4_200)]
        XCTAssertEqual(chapter.netChange(for: "2026-10-02"), -800)
        XCTAssertEqual(chapter.increment(for: "2026-10-02"), 0)
    }

    func testCorrectionIsKeptOnlyWhileTotalIsLower() {
        let store = DataStore.preview
        let saved = store.data.projects
        defer { store.data.projects = saved; store.dataVersion += 1 }

        var chapter = Chapter(name: "Ch", goal: 10_000)
        chapter.entries = [DailyEntry(date: day(1), totalCount: 5_000)]
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        store.data.projects = [project]

        store.setTotalForDate(4_000, for: chapter.id, in: project.id, date: day(0), isCorrection: true)
        XCTAssertEqual(store.data.projects[0].chapters[0].entryForDate(day(0))?.isCorrection, true)

        // Le total repasse au-dessus du précédent : ce n'est plus une correction.
        store.setTotalForDate(5_500, for: chapter.id, in: project.id, date: day(0))
        XCTAssertEqual(store.data.projects[0].chapters[0].entryForDate(day(0))?.isCorrection, false)
    }

    func testCorrectionDayKeepsTheStreak() {
        let store = DataStore.preview
        let saved = store.data.projects
        defer { store.data.projects = saved; store.dataVersion += 1 }

        var chapter = Chapter(name: "Ch", goal: 10_000)
        var correction = DailyEntry(date: day(1), totalCount: 4_000)
        correction.isCorrection = true
        chapter.entries = [DailyEntry(date: day(3), totalCount: 3_000),
                           DailyEntry(date: day(2), totalCount: 5_000),
                           correction,
                           DailyEntry(date: day(0), totalCount: 4_500)]
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        store.data.projects = [project]
        store.dataVersion += 1

        XCTAssertEqual(store.currentStreak, 4)

        // Sans la marque, le jour de baisse casse la série.
        store.data.projects[0].chapters[0].entries[2].isCorrection = false
        store.dataVersion += 1
        XCTAssertEqual(store.currentStreak, 1)
    }
}
