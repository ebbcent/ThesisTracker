import XCTest
@testable import Writing_Process

/// 5.26 — lecture d'un calendrier .ics pour les créneaux d'écriture.
final class WritingCalendarTests: XCTestCase {

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, zone: String = "Europe/Paris") -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: zone)!
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return cal.date(from: c)!
    }

    private let ics = """
    BEGIN:VCALENDAR
    VERSION:2.0
    BEGIN:VEVENT
    UID:a1
    SUMMARY:Écriture ch. 4
    DTSTART;TZID=Europe/Paris:20261118T090000
    DTEND;TZID=Europe/Paris:20261118T103000
    END:VEVENT
    BEGIN:VEVENT
    UID:a2
    SUMMARY:Séminaire
    DTSTART;TZID=Europe/Paris:20261118T140000
    DTEND;TZID=Europe/Paris:20261118T160000
    END:VEVENT
    BEGIN:VEVENT
    UID:a3
    SUMMARY:Bloc ecriture
    DTSTART:20261116T080000Z
    DTEND:20261116T090000Z
    RRULE:FREQ=WEEKLY;BYDAY=MO,TH
    END:VEVENT
    END:VCALENDAR
    """.replacingOccurrences(of: "    ", with: "")

    func testKeepsOnlyWritingEvents() {
        let events = ICSParser.events(from: ics, matching: "écriture",
                                      from: date(2026, 11, 18), to: date(2026, 11, 18, 23, 59))
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.title, "Écriture ch. 4")
        XCTAssertEqual(events.first?.start, date(2026, 11, 18, 9, 0))
        XCTAssertEqual(events.first?.end, date(2026, 11, 18, 10, 30))
    }

    func testKeywordIgnoresAccentsAndCase() {
        let events = ICSParser.events(from: ics, matching: "ECRITURE",
                                      from: date(2026, 11, 16), to: date(2026, 11, 16, 23, 59))
        XCTAssertEqual(events.map(\.title), ["Bloc ecriture"])
    }

    func testWeeklyRepetitionOnListedDays() {
        // Lundi 16, jeudi 19, lundi 23, jeudi 26 novembre 2026.
        let events = ICSParser.events(from: ics, matching: "bloc",
                                      from: date(2026, 11, 16), to: date(2026, 11, 27))
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first?.start, date(2026, 11, 16, 8, 0, zone: "UTC"))
        XCTAssertEqual(events.last?.start, date(2026, 11, 26, 8, 0, zone: "UTC"))
    }

    func testFoldedLinesAreJoined() {
        let folded = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:f1\r\nSUMMARY:Écri\r\n ture du soir\r\nDTSTART:20261118T190000Z\r\nDTEND:20261118T200000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        let events = ICSParser.events(from: folded, matching: "écriture",
                                      from: date(2026, 11, 18), to: date(2026, 11, 19))
        XCTAssertEqual(events.first?.title, "Écriture du soir")
    }

    func testAddressAcceptsWebcal() {
        XCTAssertEqual(WritingCalendarService.url(from: " webcal://exemple.org/cal.ics ")?.absoluteString, "https://exemple.org/cal.ics")
        XCTAssertNotNil(WritingCalendarService.url(from: "https://exemple.org/cal.ics"))
        XCTAssertNil(WritingCalendarService.url(from: "file:///etc/passwd"))
        XCTAssertNil(WritingCalendarService.url(from: "pas une adresse"))
    }
}
