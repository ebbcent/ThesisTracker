import XCTest
@testable import Writing_Process

/// 5.10 — chapitres hors total, équivalent en pages, objectif plancher /
/// plafond / environ, simulateur d'échéance.
@MainActor
final class ChapterGoalTests: XCTestCase {

    private var store: DataStore { DataStore.preview }

    private func prepare() -> () -> Void {
        let saved = store.data
        store.data.projects = []
        store.data.restDays = []
        store.data.writingSchedule = nil
        store.dataVersion += 1
        return { [store] in
            store.data = saved
            store.dataVersion += 1
        }
    }

    private func date(_ s: String) -> Date { DataStore.parseDate(s)! }

    private func chapter(_ name: String, goal: Int, total: Int) -> Chapter {
        var ch = Chapter(name: name, goal: goal)
        ch.entries = [DailyEntry(date: "2026-10-01", totalCount: total)]
        return ch
    }

    // MARK: Modèle

    func testOldChapterDecodesWithDefaults() throws {
        let json = #"{"name":"Ch 1","goal":20000}"#.data(using: .utf8)!
        let ch = try JSONDecoder().decode(Chapter.self, from: json)
        XCTAssertNil(ch.goalKind)
        XCTAssertEqual(ch.effectiveGoalKind, .atLeast)
        XCTAssertTrue(ch.countsInThesisTotal)
    }

    func testUnknownGoalKindFallsBackToAtLeast() throws {
        let json = #"{"name":"Ch 1","goal":20000,"goalKind":"bientot"}"#.data(using: .utf8)!
        let ch = try JSONDecoder().decode(Chapter.self, from: json)
        XCTAssertEqual(ch.effectiveGoalKind, .atLeast)
    }

    func testNewFieldsSurviveRoundTrip() throws {
        var ch = Chapter(name: "Annexes", goal: 10_000)
        ch.goalKind = .atMost
        ch.excludedFromThesisTotal = true
        let decoded = try JSONDecoder().decode(Chapter.self, from: JSONEncoder().encode(ch))
        XCTAssertEqual(decoded.goalKind, .atMost)
        XCTAssertFalse(decoded.countsInThesisTotal)
    }

    // MARK: Type d'objectif

    func testAtLeastGoal() {
        let ch = Chapter(name: "Ch", goal: 10_000)
        XCTAssertEqual(ch.goalState(total: 9_000), .inProgress)
        XCTAssertEqual(ch.goalState(total: 11_200), .reached)
        XCTAssertEqual(ch.overflow(total: 11_200), 1_200)
    }

    func testAtMostGoal() {
        var ch = Chapter(name: "Ch", goal: 10_000)
        ch.goalKind = .atMost
        XCTAssertEqual(ch.goalState(total: 10_000), .inProgress)
        XCTAssertEqual(ch.goalState(total: 10_001), .overCeiling)
    }

    func testAroundGoal() {
        var ch = Chapter(name: "Ch", goal: 10_000)
        ch.goalKind = .around
        XCTAssertEqual(ch.goalState(total: 8_900), .inProgress)
        XCTAssertEqual(ch.goalState(total: 9_000), .reached)
        XCTAssertEqual(ch.goalState(total: 11_000), .reached)
        XCTAssertEqual(ch.goalState(total: 11_100), .overCeiling)
    }

    func testNoGoal() {
        XCTAssertEqual(Chapter(name: "Ch", goal: 0).goalState(total: 500), .noGoal)
    }

    // MARK: Hors total

    func testExcludedChapterLeavesThesisRemaining() {
        let restore = prepare(); defer { restore() }
        var annexes = chapter("Annexes", goal: 50_000, total: 10_000)
        annexes.excludedFromThesisTotal = true
        var project = Project(name: "Thèse")
        project.chapters = [chapter("Ch 1", goal: 30_000, total: 10_000), annexes]
        store.data.projects = [project]
        store.dataVersion += 1
        XCTAssertEqual(store.thesisRemainingChars, 20_000)

        store.data.projects[0].chapters[1].excludedFromThesisTotal = nil
        store.dataVersion += 1
        XCTAssertEqual(store.thesisRemainingChars, 60_000)
    }

    // MARK: Pages

    func testPagesLabel() {
        XCTAssertEqual(DataStore.pagesLabel(chars: 3_000, charsPerPage: 1_500), "≈ 2 p.")
        XCTAssertEqual(DataStore.pagesLabel(chars: 5_250, charsPerPage: 1_500), "≈ 3,5 p.")
        XCTAssertEqual(DataStore.pagesLabel(chars: 63_100, charsPerPage: 1_500), "≈ 42 p.")
        XCTAssertEqual(DataStore.pages(chars: 1_000, charsPerPage: 0), 0)
    }

    func testNoPagesWithoutSetting() {
        let restore = prepare(); defer { restore() }
        XCTAssertNil(store.pagesLabel(3_000))
        var schedule = WritingSchedule()
        schedule.charsPerPage = 1_500
        store.data.writingSchedule = schedule
        XCTAssertEqual(store.pagesLabel(3_000), "≈ 2 p.")
    }

    // MARK: Simulateur

    func testQuotaPreviewWithoutCalendarMatchesDeadlineGoal() {
        let restore = prepare(); defer { restore() }
        let preview = store.quotaPreview(remaining: 10_000, deadline: date("2026-10-31"), from: date("2026-10-21"))
        XCTAssertEqual(preview.days, 10)
        XCTAssertEqual(preview.perDay, 1_000)
    }

    func testQuotaPreviewWithCalendar() {
        let restore = prepare(); defer { restore() }
        var schedule = WritingSchedule()
        schedule.workWeekdays = [2, 3, 4, 5, 6]
        store.data.writingSchedule = schedule
        let preview = store.quotaPreview(remaining: 8_000, deadline: date("2026-10-30"), from: date("2026-10-21"))
        XCTAssertEqual(preview.days, 8)
        XCTAssertEqual(preview.perDay, 1_000)
    }
}
