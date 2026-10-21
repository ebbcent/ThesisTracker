import XCTest
@testable import Writing_Process

/// 5.9 — calendrier d'écriture, quotas, série selon le calendrier,
/// réglages d'objectifs synchronisés.
@MainActor
final class WritingScheduleTests: XCTestCase {

    private var store: DataStore { DataStore.preview }

    /// Vide le store partagé et renvoie de quoi le remettre en état.
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

    /// Un chapitre dont le total augmente chacun des jours donnés.
    private func writeOn(_ days: [String]) {
        var chapter = Chapter(name: "Ch", goal: 100_000)
        chapter.entries = days.sorted().enumerated().map { i, d in DailyEntry(date: d, totalCount: (i + 1) * 1_000) }
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        store.data.projects = [project]
        store.dataVersion += 1
    }

    private func setSchedule(_ change: (inout WritingSchedule) -> Void) {
        var schedule = store.data.writingSchedule ?? WritingSchedule()
        change(&schedule)
        store.data.writingSchedule = schedule
        store.dataVersion += 1
    }

    private let weekdaysMonToFri = [2, 3, 4, 5, 6]

    // MARK: Décodage

    func testOldDataWithoutScheduleKeepsPreviousBehaviour() throws {
        let restore = prepare(); defer { restore() }
        let json = #"{"dailyGoal":500,"projects":[]}"#.data(using: .utf8)!
        let decoded = try DataStore.decodeAppData(json).data
        XCTAssertNil(decoded.writingSchedule)
        XCTAssertFalse(store.usesWritingCalendar)
        XCTAssertFalse(store.usesScheduledStreak)
    }

    func testScheduleDecodingIsTolerant() throws {
        let restore = prepare(); defer { restore() }
        let json = #"{"workWeekdays":[2,"x",3],"streakRule":"inconnu","graceDay":true}"#.data(using: .utf8)!
        let schedule = try JSONDecoder().decode(WritingSchedule.self, from: json)
        XCTAssertEqual(schedule.workWeekdays, [2, 3])
        XCTAssertNil(schedule.streakRule)
        XCTAssertEqual(schedule.graceDay, true)
    }

    func testScheduleSurvivesRoundTrip() throws {
        let restore = prepare(); defer { restore() }
        var data = AppData()
        var schedule = WritingSchedule()
        schedule.workWeekdays = weekdaysMonToFri
        schedule.streakRule = .scheduled
        schedule.streakPauses = [StreakPause(start: "2026-10-01", end: "2026-10-03")]
        data.writingSchedule = schedule
        let decoded = try DataStore.decodeAppData(JSONEncoder().encode(data)).data
        XCTAssertEqual(decoded.writingSchedule, schedule)
    }

    // MARK: Quotas

    func testQuotaSkipsWeekend() {
        let restore = prepare(); defer { restore() }
        setSchedule { $0.workWeekdays = weekdaysMonToFri }
        // Mer. 21 → ven. 30 octobre : 21, 22, 23, 26, 27, 28, 29, 30.
        XCTAssertEqual(store.writingDaysRemaining(until: date("2026-10-30"), from: date("2026-10-21")), 8)
        XCTAssertEqual(store.scheduledDailyQuota(remaining: 8_000, deadline: date("2026-10-30"), from: date("2026-10-21")), 1_000)
    }

    func testDeadlineDayCanBeExcluded() {
        let restore = prepare(); defer { restore() }
        setSchedule {
            $0.workWeekdays = weekdaysMonToFri
            $0.countDeadlineDay = false
        }
        XCTAssertEqual(store.writingDaysRemaining(until: date("2026-10-30"), from: date("2026-10-21")), 7)
        XCTAssertEqual(store.scheduledDailyQuota(remaining: 7_000, deadline: date("2026-10-30"), from: date("2026-10-21")), 1_000)
    }

    func testRestDayIsExcludedFromQuota() {
        let restore = prepare(); defer { restore() }
        setSchedule { $0.workWeekdays = weekdaysMonToFri }
        store.data.restDays = ["2026-10-22"]
        XCTAssertEqual(store.writingDaysRemaining(until: date("2026-10-30"), from: date("2026-10-21")), 7)
    }

    func testWithoutCalendarEveryDayCounts() {
        let restore = prepare(); defer { restore() }
        XCTAssertEqual(store.plannedWritingDays(from: date("2026-10-21"), through: date("2026-10-30")), 10)
        XCTAssertTrue(store.isPlannedWritingDay(date("2026-10-25")))
    }

    func testPastDeadlineAsksForEverythingAtOnce() {
        let restore = prepare(); defer { restore() }
        setSchedule { $0.workWeekdays = weekdaysMonToFri }
        XCTAssertEqual(store.scheduledDailyQuota(remaining: 5_000, deadline: date("2026-10-20"), from: date("2026-10-21")), 5_000)
    }

    func testAdaptedGoalUsesRemainingWritingDaysOfTheWeek() {
        let restore = prepare(); defer { restore() }
        setSchedule { $0.workWeekdays = weekdaysMonToFri }
        store.data.weeklyGoal = 3_000
        store.dataVersion += 1
        // Mercredi : mercredi, jeudi, vendredi restent.
        XCTAssertEqual(store.scheduledAdaptedDailyGoal(now: date("2026-10-21")), 1_000)
    }

    // MARK: Série selon le calendrier

    func testWeekendIsNeutralForScheduledStreak() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-16", "2026-10-19", "2026-10-20", "2026-10-21"])   // ven., lun., mar., mer.
        setSchedule {
            $0.workWeekdays = weekdaysMonToFri
            $0.streakRule = .scheduled
        }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-21")).current, 4)
    }

    func testRestDayIsNeutralForScheduledStreak() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-16", "2026-10-18"])
        store.data.restDays = ["2026-10-17"]
        setSchedule { $0.streakRule = .scheduled }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-18")).current, 2)
    }

    func testGraceDayForgivesOneMissedDay() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-15", "2026-10-16", "2026-10-18", "2026-10-19"])
        setSchedule { $0.streakRule = .scheduled }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-19")).current, 2)
        setSchedule { $0.graceDay = true }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-19")).current, 4)
    }

    func testTwoMissedDaysBreakEvenWithGrace() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-15", "2026-10-18", "2026-10-19"])
        setSchedule {
            $0.streakRule = .scheduled
            $0.graceDay = true
        }
        let streaks = store.scheduledStreaks(today: date("2026-10-19"))
        XCTAssertEqual(streaks.current, 2)
        XCTAssertEqual(streaks.longest, 2)
    }

    func testGraceKeepsStreakWhileTodayIsStillOpen() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-17", "2026-10-18"])   // le 19 manqué, le 20 pas encore écrit
        setSchedule {
            $0.streakRule = .scheduled
            $0.graceDay = true
        }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-20")).current, 2)
    }

    func testPausedDaysAreNeutral() {
        let restore = prepare(); defer { restore() }
        writeOn(["2026-10-14", "2026-10-15", "2026-10-19"])
        setSchedule {
            $0.streakRule = .scheduled
            $0.streakPauses = [StreakPause(start: "2026-10-16", end: "2026-10-18")]
        }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-19")).current, 3)
    }

    func testCorrectionDayStillCountsForScheduledStreak() {
        let restore = prepare(); defer { restore() }
        var chapter = Chapter(name: "Ch", goal: 10_000)
        var correction = DailyEntry(date: "2026-10-20", totalCount: 4_000)
        correction.isCorrection = true
        chapter.entries = [DailyEntry(date: "2026-10-19", totalCount: 5_000), correction]
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        store.data.projects = [project]
        setSchedule { $0.streakRule = .scheduled }
        XCTAssertEqual(store.scheduledStreaks(today: date("2026-10-20")).current, 2)
    }

    func testDefaultRuleIsUnchanged() {
        let restore = prepare(); defer { restore() }
        let cal = Calendar(identifier: .gregorian)
        let days = (0..<3).map { DataStore.dateString(from: cal.date(byAdding: .day, value: -$0, to: Date())!) }
        writeOn(days)
        XCTAssertFalse(store.usesScheduledStreak)
        XCTAssertEqual(store.currentStreak, 3)
        // Un jour de repos ne protège pas la série classique (comportement 5.8).
        writeOn([days[0], days[2]])
        store.data.restDays = [days[1]]
        store.dataVersion += 1
        XCTAssertEqual(store.currentStreak, 1)
    }

    // MARK: Réglages synchronisés (UserDefaults → data.json)

    func testLocalGoalSettingsAreMigratedOnce() throws {
        let restore = prepare(); defer { restore() }
        let suite = "WritingScheduleTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode(["2": 1_200, "7": 300]), forKey: "weekdayGoals")
        defaults.set(3, forKey: "deadlineBuffer")

        store.migrateLocalGoalSettingsIfNeeded(defaults: defaults)
        XCTAssertEqual(store.data.writingSchedule?.weekdayGoals, ["2": 1_200, "7": 300])
        XCTAssertEqual(store.data.writingSchedule?.deadlineBufferDays, 3)
        XCTAssertEqual(store.weekdayGoals[2], 1_200)

        // Une valeur déjà synchronisée n'est jamais écrasée par la copie locale.
        defaults.set(9, forKey: "deadlineBuffer")
        store.migrateLocalGoalSettingsIfNeeded(defaults: defaults)
        XCTAssertEqual(store.data.writingSchedule?.deadlineBufferDays, 3)
    }

    func testTwoMacsEditingDifferentWeekdaysAreMerged() throws {
        let restore = prepare(); defer { restore() }
        var base = AppData()
        var schedule = WritingSchedule()
        schedule.weekdayGoals = ["2": 1_000, "3": 1_000]
        base.writingSchedule = schedule
        var mine = base
        mine.writingSchedule?.weekdayGoals?["2"] = 1_500
        var theirs = base
        theirs.writingSchedule?.weekdayGoals?["3"] = 800

        let encoder = JSONEncoder()
        let merged = try XCTUnwrap(DataSync.merge(base: encoder.encode(base), mine: encoder.encode(mine), theirs: encoder.encode(theirs)))
        let result = try DataStore.decodeAppData(merged).data
        XCTAssertEqual(result.writingSchedule?.weekdayGoals, ["2": 1_500, "3": 800])
    }

    /// Risque connu : un Mac resté en 5.8 ne connaît pas `writingSchedule` et
    /// l'efface en réécrivant le fichier. D'où la consigne de mettre à jour les
    /// deux Mac avant d'utiliser le calendrier.
    func testOldVersionOnTheOtherMacDropsTheSchedule() throws {
        let restore = prepare(); defer { restore() }
        var base = AppData()
        var schedule = WritingSchedule()
        schedule.workWeekdays = weekdaysMonToFri
        base.writingSchedule = schedule
        let baseBytes = try JSONEncoder().encode(base)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: baseBytes) as? [String: Any])
        object.removeValue(forKey: "writingSchedule")
        let oldMacBytes = try JSONSerialization.data(withJSONObject: object)

        let merged = try XCTUnwrap(DataSync.merge(base: baseBytes, mine: oldMacBytes, theirs: baseBytes))
        XCTAssertNil(try DataStore.decodeAppData(merged).data.writingSchedule)
    }
}
