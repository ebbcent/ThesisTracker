import XCTest
@testable import Writing_Process

/// 5.11 — intention et bilan de concentration des sessions, créneaux d'écriture.
@MainActor
final class FocusAndSlotsTests: XCTestCase {

    private func date(_ s: String, hour: Int = 10) -> Date {
        Calendar(identifier: .gregorian).date(bySettingHour: hour, minute: 0, second: 0, of: DataStore.parseDate(s)!)!
    }

    private func session(_ day: String, quality: Int? = nil, intention: String? = nil,
                         kind: SessionKind = .focus) -> PomodoroSessionRecord {
        let start = date(day)
        return PomodoroSessionRecord(
            id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(1_500),
            duration: 1_500, plannedDuration: 1_500, kind: kind, completionState: .completed,
            categoryID: nil, projectID: nil, note: "", createdAt: start, updatedAt: start,
            intention: intention, focusQuality: quality
        )
    }

    // MARK: Sessions

    func testOldSessionWithoutNewFieldsDecodes() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(session("2026-10-20", quality: 3, intention: "Plan ch. 4"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "intention")
        object.removeValue(forKey: "focusQuality")
        let old = try decoder.decode(PomodoroSessionRecord.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.intention)
        XCTAssertNil(old.focusQuality)

        let roundTrip = try decoder.decode(PomodoroSessionRecord.self, from: data)
        XCTAssertEqual(roundTrip.intention, "Plan ch. 4")
        XCTAssertEqual(roundTrip.focusQuality, 3)
    }

    func testWeeklyQualityDistribution() {
        let sessions = [
            session("2026-10-19", quality: 3),              // lundi, semaine courante
            session("2026-10-21", quality: 1),
            session("2026-10-21", quality: 3),
            session("2026-10-14", quality: 2),              // semaine précédente
            session("2026-10-21"),                          // sans bilan : ignorée
            session("2026-10-21", quality: 3, kind: .shortBreak) // pause : ignorée
        ]
        let weeks = FocusQualityStats.weekly(sessions: sessions, weeks: 4, now: date("2026-10-21"))
        XCTAssertEqual(weeks.count, 4)
        XCTAssertEqual(weeks[3].focused, 2)
        XCTAssertEqual(weeks[3].distracted, 1)
        XCTAssertEqual(weeks[2].neutral, 1)
        XCTAssertEqual(weeks[0].total + weeks[1].total, 0)
    }

    func testRecentIntentionsAreDistinctAndNewestFirst() {
        let sessions = [
            session("2026-10-18", intention: "Notes Bourdieu"),
            session("2026-10-19", intention: "Plan ch. 4"),
            session("2026-10-20", intention: "plan ch. 4"),
            session("2026-10-21", intention: "  "),
            session("2026-10-21", intention: "Relire intro")
        ]
        XCTAssertEqual(FocusQualityStats.recentIntentions(sessions: sessions),
                       ["Relire intro", "plan ch. 4", "Notes Bourdieu"])
        XCTAssertEqual(FocusQualityStats.recentIntentions(sessions: sessions, limit: 1), ["Relire intro"])
    }

    // MARK: Créneaux

    func testSlotTriggersOnePerCheckedDay() {
        var slot = WritingSlot()
        slot.weekdays = [4, 2, 2, 9]
        slot.start = "09:30"
        let triggers = slot.triggerComponents
        XCTAssertEqual(triggers.map(\.weekday), [2, 4])
        XCTAssertEqual(triggers.first?.hour, 9)
        XCTAssertEqual(triggers.first?.minute, 30)
    }

    func testInvalidStartSchedulesNothing() {
        var slot = WritingSlot()
        slot.start = "25:99"
        XCTAssertTrue(slot.triggerComponents.isEmpty)
        XCTAssertNil(slot.startTime)
    }

    func testSlotEndAndLabel() {
        var slot = WritingSlot()
        slot.start = "09:30"
        slot.durationMinutes = 90
        XCTAssertEqual(slot.endText, "11:00")
        XCTAssertEqual(slot.displayLabel, "Créneau d'écriture")
        slot.label = "Chapitre 4"
        XCTAssertEqual(slot.displayLabel, "Chapitre 4")
    }

    func testNotificationIdentifierLeadsBackToSlot() {
        let slot = WritingSlot()
        let identifier = WritingSlotScheduler.identifier(slot: slot, weekday: 3)
        XCTAssertEqual(WritingSlotScheduler.slotID(fromNotificationIdentifier: identifier), slot.id)
        XCTAssertNil(WritingSlotScheduler.slotID(fromNotificationIdentifier: "pomodoro.session-end"))
    }

    func testBrokenSlotIsDroppedAlone() throws {
        let json = """
        {"projects":[],"writingSlots":[
          {"id":"\(UUID().uuidString)","weekdays":[2,3],"start":"08:00","durationMinutes":60},
          {"id":"\(UUID().uuidString)","weekdays":[4]}
        ]}
        """.data(using: .utf8)!
        let result = try DataStore.decodeAppData(json)
        XCTAssertEqual(result.data.writingSlots?.count, 1)
        XCTAssertEqual(result.dropped, 1)
    }

    func testOldDataHasNoSlots() throws {
        let json = #"{"projects":[]}"#.data(using: .utf8)!
        XCTAssertNil(try DataStore.decodeAppData(json).data.writingSlots)
    }
}
