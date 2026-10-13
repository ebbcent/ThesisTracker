import XCTest
@testable import Writing_Process

/// Fusion entre deux Mac et décodage tolérant : ce qui protège les données.
@MainActor
final class DataSyncTests: XCTestCase {

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func object(_ data: Data?) -> NSDictionary {
        guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? NSDictionary else {
            XCTFail("JSON invalide"); return [:]
        }
        return obj
    }

    // MARK: - merge3

    func testNoChangeOnOneSideTakesTheOther() {
        let base = json(["goal": 500])
        let mine = json(["goal": 500])
        let theirs = json(["goal": 800])
        XCTAssertEqual(object(DataSync.merge(base: base, mine: mine, theirs: theirs))["goal"] as? Int, 800)
    }

    func testIndependentFieldChangesAreBothKept() {
        let base = json(["dailyGoal": 500, "weeklyGoal": 3000])
        let mine = json(["dailyGoal": 600, "weeklyGoal": 3000])
        let theirs = json(["dailyGoal": 500, "weeklyGoal": 4000])
        let merged = object(DataSync.merge(base: base, mine: mine, theirs: theirs))
        XCTAssertEqual(merged["dailyGoal"] as? Int, 600)
        XCTAssertEqual(merged["weeklyGoal"] as? Int, 4000)
    }

    func testSameFieldConflictPrefersThisMac() {
        let base = json(["dailyGoal": 500])
        let mine = json(["dailyGoal": 600])
        let theirs = json(["dailyGoal": 700])
        XCTAssertEqual(object(DataSync.merge(base: base, mine: mine, theirs: theirs))["dailyGoal"] as? Int, 600)
    }

    func testIdentifiedArraysMergeAdditionsFromBothSides() {
        let base = json(["items": [["id": "A", "v": 1]]])
        let mine = json(["items": [["id": "A", "v": 1], ["id": "B", "v": 2]]])
        let theirs = json(["items": [["id": "A", "v": 1], ["id": "C", "v": 3]]])
        let items = object(DataSync.merge(base: base, mine: mine, theirs: theirs))["items"] as? [NSDictionary] ?? []
        XCTAssertEqual(Set(items.compactMap { $0["id"] as? String }), ["A", "B", "C"])
    }

    func testDeletionOnOneSideIsApplied() {
        let base = json(["items": [["id": "A"], ["id": "B"]]])
        let mine = json(["items": [["id": "A"]]])
        let theirs = json(["items": [["id": "A"], ["id": "B"]]])
        let items = object(DataSync.merge(base: base, mine: mine, theirs: theirs))["items"] as? [NSDictionary] ?? []
        XCTAssertEqual(items.compactMap { $0["id"] as? String }, ["A"])
    }

    func testModificationWinsOverDeletion() {
        let base = json(["items": [["id": "A", "v": 1]]])
        let mine = json(["items": [] as [Any]])
        let theirs = json(["items": [["id": "A", "v": 2]]])
        let items = object(DataSync.merge(base: base, mine: mine, theirs: theirs))["items"] as? [NSDictionary] ?? []
        XCTAssertEqual(items.first?["v"] as? Int, 2)
    }

    func testNestedChangesInSameElementAreCombined() {
        let base = json(["items": [["id": "A", "name": "Intro", "goal": 100]]])
        let mine = json(["items": [["id": "A", "name": "Introduction", "goal": 100]]])
        let theirs = json(["items": [["id": "A", "name": "Intro", "goal": 200]]])
        let item = (object(DataSync.merge(base: base, mine: mine, theirs: theirs))["items"] as? [NSDictionary])?.first
        XCTAssertEqual(item?["name"] as? String, "Introduction")
        XCTAssertEqual(item?["goal"] as? Int, 200)
    }

    func testScalarArraysMergeAddsAndRemoves() {
        let base = json(["tags": ["a", "b"]])
        let mine = json(["tags": ["a", "b", "c"]])
        let theirs = json(["tags": ["a"]])
        let tags = object(DataSync.merge(base: base, mine: mine, theirs: theirs))["tags"] as? [String] ?? []
        XCTAssertEqual(tags, ["a", "c"])
    }

    func testWithoutBaseKeepsUnion() {
        let mine = json(["items": [["id": "A"]], "x": 1])
        let theirs = json(["items": [["id": "B"]], "y": 2])
        let merged = object(DataSync.merge(base: nil, mine: mine, theirs: theirs))
        let ids = (merged["items"] as? [NSDictionary] ?? []).compactMap { $0["id"] as? String }
        XCTAssertEqual(Set(ids), ["A", "B"])
        XCTAssertEqual(merged["x"] as? Int, 1)
        XCTAssertEqual(merged["y"] as? Int, 2)
    }

    // MARK: - AppData de bout en bout

    func testTwoMacsWritingDifferentDaysKeepsBothEntries() throws {
        var chapter = Chapter(name: "Intro", goal: 10_000)
        chapter.entries = [DailyEntry(date: "2026-10-01", totalCount: 1000, note: nil)]
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        var base = AppData()
        base.projects = [project]

        var mine = base
        mine.projects[0].chapters[0].entries.append(DailyEntry(date: "2026-10-02", totalCount: 1500, note: nil))
        var theirs = base
        theirs.projects[0].chapters[0].entries.append(DailyEntry(date: "2026-10-03", totalCount: 1800, note: nil))

        let encoder = JSONEncoder()
        let mergedData = try XCTUnwrap(DataSync.merge(base: try encoder.encode(base),
                                                      mine: try encoder.encode(mine),
                                                      theirs: try encoder.encode(theirs)))
        var merged = try DataStore.decodeAppData(mergedData).data
        DataSync.normalize(&merged)
        let dates = merged.projects[0].chapters[0].entries.map(\.date).sorted()
        XCTAssertEqual(dates, ["2026-10-01", "2026-10-02", "2026-10-03"])
    }

    func testNormalizeKeepsOneEntryPerDayWithHighestTotalAndNote() {
        var chapter = Chapter(name: "Intro", goal: 10_000)
        chapter.entries = [
            DailyEntry(date: "2026-10-02", totalCount: 1200, note: "matin"),
            DailyEntry(date: "2026-10-02", totalCount: 1500, note: nil),
        ]
        var project = Project(name: "Thèse")
        project.chapters = [chapter]
        var data = AppData()
        data.projects = [project]
        DataSync.normalize(&data)
        let entries = data.projects[0].chapters[0].entries
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.totalCount, 1500)
        XCTAssertEqual(entries.first?.note, "matin")
    }

    // MARK: - Décodage tolérant

    func testOneBrokenEntryDoesNotEraseTheOthers() throws {
        let raw: [String: Any] = [
            "projects": [[
                "id": UUID().uuidString,
                "name": "Thèse",
                "chapters": [[
                    "id": UUID().uuidString,
                    "name": "Intro",
                    "goal": 10_000,
                    "entries": [
                        ["id": UUID().uuidString, "date": "2026-10-01", "totalCount": 1000],
                        ["id": UUID().uuidString, "date": "2026-10-02", "totalCount": "pas un nombre"],
                        ["id": UUID().uuidString, "date": "2026-10-03", "totalCount": 1400],
                    ],
                ]],
            ]],
        ]
        let result = try DataStore.decodeAppData(json(raw))
        let dates = result.data.projects.first?.chapters.first?.entries.map(\.date) ?? []
        XCTAssertEqual(result.data.projects.count, 1)
        XCTAssertTrue(dates.contains("2026-10-01"))
        XCTAssertTrue(dates.contains("2026-10-03"))
        XCTAssertFalse(dates.contains("2026-10-02"))
        XCTAssertEqual(result.dropped, 1)
    }

    func testOldFileWithoutRecentFieldsStillDecodes() throws {
        let raw: [String: Any] = ["dailyGoal": 750, "projects": [] as [Any]]
        let result = try DataStore.decodeAppData(json(raw))
        XCTAssertEqual(result.data.dailyGoal, 750)
        XCTAssertEqual(result.dropped, 0)
    }

    // MARK: - Incréments

    func testIncrementIsDifferenceWithPreviousTotal() {
        var chapter = Chapter(name: "Intro", goal: 10_000)
        chapter.entries = [
            DailyEntry(date: "2026-10-01", totalCount: 1000, note: nil),
            DailyEntry(date: "2026-10-03", totalCount: 1600, note: nil),
        ]
        XCTAssertEqual(chapter.increment(for: "2026-10-03"), 600)
        XCTAssertEqual(chapter.increment(for: "2026-10-01"), 1000)
        XCTAssertEqual(chapter.increment(for: "2026-10-02"), 0)
    }
}
