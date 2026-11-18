import XCTest
@testable import Writing_Process

/// 5.30 — accomplissements à progression.
final class AchievementCatalogTests: XCTestCase {

    func testComebackNeedsMoreThanTwoWeeks() {
        // 1er → 10 janvier : 9 jours, pas une reprise. 10 janvier → 1er février : 22 jours, une reprise.
        XCTAssertEqual(AchievementCatalog.comebackCount(writtenDates: ["2026-01-01", "2026-01-10", "2026-02-01"]), 1)
        XCTAssertEqual(AchievementCatalog.comebackCount(writtenDates: ["2026-01-01", "2026-01-15"]), 0)
        XCTAssertEqual(AchievementCatalog.comebackCount(writtenDates: ["2026-01-01", "2026-01-16"]), 1)
        XCTAssertEqual(AchievementCatalog.comebackCount(writtenDates: []), 0)
    }

    func testProgressTextAndRatio() {
        let half = ProgressAchievement(id: "x", family: .goals, icon: "target", color: .accentWarm,
                                       name: "Test", detail: "", current: 5, target: 10, unit: "jours")
        XCTAssertFalse(half.isUnlocked)
        XCTAssertEqual(half.ratio, 0.5, accuracy: 0.0001)
        XCTAssertEqual(half.progressText, "5 / 10 jours")

        let over = ProgressAchievement(id: "y", family: .manuscript, icon: "target", color: .accentWarm,
                                       name: "Test", detail: "", current: 80, target: 75, unit: "%")
        XCTAssertTrue(over.isUnlocked)
        XCTAssertEqual(over.ratio, 1, accuracy: 0.0001)
        XCTAssertEqual(over.progressText, "75 % sur 75 %")
    }

    func testNearestIsTheClosestLockedOne() {
        func make(_ id: String, _ current: Int, _ target: Int) -> ProgressAchievement {
            ProgressAchievement(id: id, family: .goals, icon: "target", color: .accentWarm,
                                name: id, detail: "", current: current, target: target, unit: "jours")
        }
        let list = [make("gagné", 10, 10), make("loin", 1, 10), make("proche", 9, 10)]
        XCTAssertEqual(AchievementCatalog.nearest(list)?.id, "proche")
        XCTAssertNil(AchievementCatalog.nearest([make("gagné", 3, 3)]))
    }
}
