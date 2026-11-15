import XCTest
@testable import Writing_Process

@MainActor
final class HubWritingBridgeTests: XCTestCase {
    private func command(_ extra: [String: Any]) throws -> HubWritingCommand {
        let base: [String: Any] = ["id": UUID().uuidString, "project": UUID().uuidString, "chapter": UUID().uuidString]
        return try JSONDecoder().decode(HubWritingCommand.self, from: JSONSerialization.data(withJSONObject: base.merging(extra) { _, b in b }))
    }
    func testCumulativeCountAndCorrectionAreAccepted() throws {
        XCTAssertNil(try command(["type":"wp-total","date":"2026-01-02","total":1200,"baseTotal":1000]).validate())
        XCTAssertNil(try command(["type":"wp-total","date":"2026-01-02","total":900,"baseTotal":1000]).validate())
    }
    func testImpossibleDateAndNegativeCountAreRejected() throws {
        XCTAssertNotNil(try command(["type":"wp-total","date":"2026-02-30","total":1200,"baseTotal":1000]).validate())
        XCTAssertNotNil(try command(["type":"wp-total","date":"2026-01-02","total":-1,"baseTotal":1000]).validate())
    }
    func testPausedSessionAndImpossibleDuration() throws {
        var x: [String: Any] = ["type":"wp-session","debut":"2026-01-02T10:00:00.000Z","fin":"2026-01-02T10:30:00.000Z","seconds":1500,"planned":1500,"completed":true]
        XCTAssertNil(try command(x).validate())
        x["seconds"] = 2000
        XCTAssertNotNil(try command(x).validate())
    }
    @MainActor func testReceiptsSurviveEncodingAndTwoMacMerge() throws {
        var data = AppData(); data.hubReceipts = ["first":"2026-01-02"]
        let bytes = try JSONEncoder().encode(data)
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: bytes).hubReceipts?["first"], "2026-01-02")
        var other = data; other.hubReceipts?["second"] = "2026-01-03"
        let merged = try XCTUnwrap(DataSync.merge(base: nil, mine: bytes, theirs: JSONEncoder().encode(other)))
        XCTAssertEqual(try JSONDecoder().decode(AppData.self, from: merged).hubReceipts?.count, 2)
    }
}
