import Foundation

enum DateRange {
    /// Returns the last `n` days (not including today) as Date values, most recent first.
    static func last(_ n: Int, from anchor: Date = Date()) -> [Date] {
        let cal = Calendar(identifier: .gregorian)
        return (1...max(1, n)).compactMap { cal.date(byAdding: .day, value: -$0, to: anchor) }
    }

    /// Returns the last `n` days as dateString → value pairs from a totals dict.
    static func values(for n: Int, in totals: [String: Int], from anchor: Date = Date()) -> [(date: Date, total: Int)] {
        last(n, from: anchor).map { date in
            (date, totals[DataStore.dateString(from: date)] ?? 0)
        }
    }
}
