import XCTest
@testable import Writing_Process

/// 5.12 — profils de rythme, jours ouvrés par chapitre, journées sans écriture,
/// pages de thèse.
@MainActor
final class PacingTests: XCTestCase {

    private var store: DataStore { DataStore.preview }
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ s: String) -> Date { DataStore.parseDate(s)! }

    /// Données vides, sans marge d'échéance (indépendant des UserDefaults du Mac).
    private func prepare() -> () -> Void {
        let saved = store.data
        store.data.projects = []
        store.data.restDays = []
        store.data.dayOffKinds = nil
        var schedule = WritingSchedule()
        schedule.deadlineBufferDays = 0
        store.data.writingSchedule = schedule
        store.dataVersion += 1
        return { [store] in
            store.data = saved
            store.dataVersion += 1
        }
    }

    @discardableResult
    private func install(_ chapter: Chapter) -> (chapter: Chapter, projectId: UUID) {
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        store.data.projects = [project]
        store.dataVersion += 1
        return (chapter, project.id)
    }

    // MARK: Profils

    func testProfileShapes() {
        let samples = (0...20).map { Double($0) / 20 }
        let steady = samples.map { PacingProfile.steady.weight(at: $0) }
        XCTAssertEqual(Set(steady), [1])

        let ramp = samples.map { PacingProfile.rampUp.weight(at: $0) }
        XCTAssertEqual(ramp, ramp.sorted(), "Montée : croissante")

        let sprint = samples.map { PacingProfile.sprint.weight(at: $0) }
        XCTAssertEqual(sprint, sprint.sorted(by: >), "Sprint : décroissant")

        let mountain = samples.map { PacingProfile.mountain.weight(at: $0) }
        let peakIndex = mountain.firstIndex(of: mountain.max()!)!
        XCTAssertEqual(samples[peakIndex], 0.65, accuracy: 0.05, "Montagne : pic aux deux tiers")
        XCTAssertLessThan(mountain.last!, mountain[peakIndex], "Montagne : décrue avant l'échéance")

        for profile in PacingProfile.allCases {
            XCTAssertTrue(samples.allSatisfy { profile.weight(at: $0) > 0 }, "\(profile) : poids toujours positifs")
        }
    }

    func testDistributeSumsExactlyToRemaining() {
        let quotas = PacingEngine.distribute(remaining: 10_001, weights: [1, 2, 3, 0.5, 7])
        XCTAssertEqual(quotas.reduce(0, +), 10_001)
        XCTAssertGreaterThan(quotas[4], quotas[0])
        XCTAssertEqual(PacingEngine.distribute(remaining: 0, weights: [1, 1]), [0, 0])
        XCTAssertEqual(PacingEngine.distribute(remaining: 500, weights: []), [])
    }

    // MARK: Plan pur

    /// Du lundi 2 au vendredi 13 novembre 2026, jours ouvrés du lundi au vendredi.
    private func weekdayPlan(profile: PacingProfile, today: String, remaining: Int) -> PacingPlan {
        PacingEngine.plan(profile: profile,
                          windowStart: date("2026-11-02"),
                          deadline: date("2026-11-13"),
                          today: date(today),
                          remaining: remaining,
                          calendar: cal,
                          isWorkingDay: { (2...6).contains(self.cal.component(.weekday, from: $0)) })
    }

    func testSteadyPlanOnWeekdaysOnly() {
        let plan = weekdayPlan(profile: .steady, today: "2026-11-02", remaining: 10_000)
        XCTAssertEqual(plan.workingDaysLeft, 10)
        XCTAssertEqual(plan.todayQuota, 1_000)
        XCTAssertEqual(plan.days.reduce(0) { $0 + $1.quota }, 10_000)
        let sunday = plan.days.first { $0.dateString == "2026-11-08" }
        XCTAssertEqual(sunday?.quota, 0)
        XCTAssertEqual(sunday?.isWorkingDay, false)
    }

    /// Le lendemain, le reste réel est réparti à nouveau : pas d'arriéré cumulé.
    func testPlanSelfHeals() {
        let ahead = weekdayPlan(profile: .steady, today: "2026-11-03", remaining: 8_000)
        let behind = weekdayPlan(profile: .steady, today: "2026-11-03", remaining: 10_000)
        XCTAssertEqual(ahead.workingDaysLeft, 9)
        XCTAssertEqual(ahead.days.reduce(0) { $0 + $1.quota }, 8_000)
        XCTAssertEqual(behind.days.reduce(0) { $0 + $1.quota }, 10_000)
        // En retard d'une journée : le quota monte d'un neuvième, il ne double pas.
        XCTAssertEqual(behind.todayQuota, 1_111, accuracy: 1)
        XCTAssertLessThan(ahead.todayQuota, behind.todayQuota)
    }

    func testProfileQuotaUsesFormula() {
        let plan = weekdayPlan(profile: .rampUp, today: "2026-11-02", remaining: 10_000)
        let future = plan.days.filter { $0.isWorkingDay && !$0.isPast }
        let total = future.reduce(0.0) { $0 + PacingProfile.rampUp.weight(at: $1.t) }
        let expected = 10_000 * PacingProfile.rampUp.weight(at: future[0].t) / total
        XCTAssertEqual(Double(plan.todayQuota), expected, accuracy: 1)
        XCTAssertLessThan(plan.todayQuota, 1_000, "Montée : début plus léger que le linéaire")
    }

    func testDeadlineDayCanBeExcluded() {
        let plan = PacingEngine.plan(profile: .steady, windowStart: date("2026-11-02"), deadline: date("2026-11-06"),
                                     today: date("2026-11-02"), remaining: 4_000, countDeadlineDay: false,
                                     calendar: cal, isWorkingDay: { _ in true })
        XCTAssertEqual(plan.workingDaysLeft, 4)
        XCTAssertEqual(plan.todayQuota, 1_000)
    }

    // MARK: Plan d'un chapitre du DataStore

    func testChapterWeekdaysAndDayOffAreRespected() {
        let restore = prepare(); defer { restore() }
        var chapter = Chapter(name: "Ch 2", goal: 12_000, deadline: "2026-11-13")
        chapter.entries = [DailyEntry(date: "2026-11-01", totalCount: 2_000)]
        chapter.pacing = ChapterPacing(profile: .steady, startDate: "2026-11-02", workWeekdays: [2, 3, 4, 5, 6])
        install(chapter)
        store.setDayOff("2026-11-04", kind: .archives)

        let plan = store.pacingPlan(for: store.data.projects[0].chapters[0], now: date("2026-11-02"))
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.workingDaysLeft, 9)          // 10 jours ouvrés moins la journée d'archives
        XCTAssertEqual(plan?.remaining, 10_000)
        XCTAssertEqual(plan?.days.first { $0.dateString == "2026-11-04" }?.quota, 0)
        XCTAssertEqual(plan?.days.reduce(0) { $0 + $1.quota }, 10_000)
    }

    func testRequiredPaceFollowsChosenProfile() {
        let restore = prepare(); defer { restore() }
        let deadline = DataStore.dateString(from: cal.date(byAdding: .day, value: 20, to: Date())!)
        var chapter = Chapter(name: "Ch", goal: 30_000, deadline: deadline)
        chapter.entries = [DailyEntry(date: DataStore.dateString(from: cal.date(byAdding: .day, value: -1, to: Date())!),
                                      totalCount: 5_000)]
        let installed = install(chapter)
        let project = store.data.projects[0]
        let linear = store.requiredPacePerDay(for: store.data.projects[0].chapters[0], in: project)
        XCTAssertNil(store.pacedDailyQuota(for: store.data.projects[0].chapters[0]), "Sans profil : calcul d'avant")

        store.updatePacing(chapterId: installed.chapter.id, in: installed.projectId) { $0.profile = .sprint }
        let updated = store.data.projects[0].chapters[0]
        XCTAssertNotNil(updated.pacing?.startDate, "Le début de la fenêtre est fixé au choix du profil")
        let paced = store.requiredPacePerDay(for: updated, in: store.data.projects[0])
        XCTAssertEqual(paced, store.pacedDailyQuota(for: updated))
        XCTAssertNotEqual(paced, linear)

        store.updatePacing(chapterId: installed.chapter.id, in: installed.projectId) { $0.profile = nil; $0.startDate = nil }
        XCTAssertNil(store.data.projects[0].chapters[0].pacing, "Réglage vide : rien n'est écrit dans data.json")
    }

    // MARK: Journées sans écriture

    func testDayOffKindsAndToggle() {
        let restore = prepare(); defer { restore() }
        store.data.restDays = ["2026-11-10"]   // jour de repos d'avant la 5.12
        XCTAssertEqual(store.dayOffKind(for: "2026-11-10"), .rest)

        store.toggleDayOff("2026-11-11", kind: .seminar)
        XCTAssertEqual(store.dayOffKind(for: "2026-11-11"), .seminar)
        XCTAssertTrue(store.data.restDays.contains("2026-11-11"))

        store.toggleDayOff("2026-11-11", kind: .archives)   // autre nature : remplace
        XCTAssertEqual(store.dayOffKind(for: "2026-11-11"), .archives)

        store.toggleDayOff("2026-11-11", kind: .archives)   // même nature : retire
        XCTAssertNil(store.dayOffKind(for: "2026-11-11"))
        XCTAssertFalse(store.data.restDays.contains("2026-11-11"))
        XCTAssertNil(store.data.dayOffKinds)
    }

    func testDaysOffKeepTheLongestStreak() {
        let restore = prepare(); defer { restore() }
        var chapter = Chapter(name: "Ch", goal: 100_000)
        chapter.entries = ["2026-09-01", "2026-09-02", "2026-09-05", "2026-09-06"].enumerated()
            .map { DailyEntry(date: $1, totalCount: ($0 + 1) * 1_000) }
        install(chapter)
        XCTAssertEqual(store.longestStreak, 2)
        store.data.restDays = ["2026-09-03", "2026-09-04"]
        store.dataVersion += 1
        XCTAssertEqual(store.longestStreak, 4)
    }

    func testDayOffIsExcludedFromVelocityAverage() {
        let restore = prepare(); defer { restore() }
        let days = (1...30).map { DataStore.dateString(from: cal.date(byAdding: .day, value: -$0, to: Date())!) }
        var chapter = Chapter(name: "Ch", goal: 1_000_000)
        // 1 000 car. par jour pendant 30 jours, sauf 10 journées d'archives sans écriture.
        let archives = Set(days.prefix(10))
        var total = 0
        chapter.entries = days.reversed().compactMap { d in
            guard !archives.contains(d) else { return nil }
            total += 1_000
            return DailyEntry(date: d, totalCount: total)
        }
        install(chapter)
        let before = store.velocityProjections().last30.avgPerDay
        store.data.restDays = Array(archives)
        store.dataVersion += 1
        let after = store.velocityProjections().last30.avgPerDay
        XCTAssertEqual(after, 1_000, accuracy: 0.5)
        XCTAssertLessThan(before, after)
    }

    // MARK: Données

    func testOldDataDecodesWithoutPacing() throws {
        let json = #"{"name":"Ch","goal":1000}"#.data(using: .utf8)!
        let chapter = try JSONDecoder().decode(Chapter.self, from: json)
        XCTAssertNil(chapter.pacing)
    }

    func testPacingRoundTripAndUnknownValuesAreTolerated() throws {
        var chapter = Chapter(name: "Ch", goal: 1000)
        chapter.pacing = ChapterPacing(profile: .mountain, startDate: "2026-11-02", workWeekdays: [2, 3])
        let decoded = try JSONDecoder().decode(Chapter.self, from: JSONEncoder().encode(chapter))
        XCTAssertEqual(decoded.pacing, chapter.pacing)

        let future = #"{"profile":"wave","workWeekdays":[2,"x",4]}"#.data(using: .utf8)!
        let pacing = try JSONDecoder().decode(ChapterPacing.self, from: future)
        XCTAssertNil(pacing.profile)
        XCTAssertEqual(pacing.workWeekdays, [2, 4])

        let app = #"{"restDays":["2026-11-02","2026-11-03"],"dayOffKinds":{"2026-11-02":"archives","2026-11-03":"conference"}}"#
        let data = try JSONDecoder().decode(AppData.self, from: app.data(using: .utf8)!)
        XCTAssertEqual(data.restDays.count, 2)
        XCTAssertEqual(data.dayOffKinds, ["2026-11-02": .archives])
    }

    // MARK: Pages

    func testFormatPages() {
        let restore = prepare(); defer { restore() }
        XCTAssertEqual(DataStore.formatPages(3_000, charsPerPage: 1_500), "2 p.")
        XCTAssertEqual(DataStore.formatPages(5_250, charsPerPage: 1_500, digits: 1), "3,5 p.")
        XCTAssertEqual(DataStore.formatPages(5_250, charsPerPage: 1_500, digits: 0), "4 p.")
        XCTAssertEqual(store.formatPages(4_500), "3 p.", "1 500 car./p par défaut")
        XCTAssertEqual(store.pageCalibrationLabel, "calibrage 1\u{202F}500 car./p")
        store.data.writingSchedule?.charsPerPage = 0
        XCTAssertNil(store.formatPages(4_500))
        XCTAssertNil(store.pageCalibrationLabel)
    }
}
