import Foundation

// Pre-computed stats for DashboardView's insight section.
// Recomputed only when `store.dataVersion` changes, avoiding 10+ redundant
// recomputations per render cycle.
struct DashboardStatsCache {
    let dataVersion: Int
    let bestWeekday: (day: String, count: Int)?
    let goalDays30: Int
    let record: Int
    let activeDays30: Int
    let avg30: Int
    let hourlyProductivity: [Int]

    init(store: DataStore) {
        dataVersion = store.dataVersion
        let totals = store.dailyTotals()
        let cal = DataStore.gregorianCal
        let today = Date()

        // Last 30 days
        let last30: [(date: Date, total: Int)] = (1...30).compactMap { offset in
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let t = totals[DataStore.dateString(from: d)] ?? 0
            return (d, t)
        }

        let dailyGoal = store.data.dailyGoal
        goalDays30   = dailyGoal > 0 ? last30.filter { $0.total >= dailyGoal }.count : 0
        activeDays30 = last30.filter { $0.total > 0 }.count
        record       = totals.values.max() ?? 0
        avg30        = activeDays30 > 0
            ? last30.reduce(0) { $0 + $1.total } / max(1, activeDays30)
            : 0

        // Best weekday
        var byWeekday: [Int: [Int]] = [:]
        var cal2 = DataStore.gregorianCal; cal2.firstWeekday = 2
        for (dateStr, val) in totals where val > 0 {
            guard let d = DataStore.parseDate(dateStr) else { continue }
            let wd  = cal2.component(.weekday, from: d)
            let idx = (wd + 5) % 7
            byWeekday[idx, default: []].append(val)
        }
        let frenchDays = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        if let best = byWeekday.max(by: { ($0.value.reduce(0,+)/$0.value.count) < ($1.value.reduce(0,+)/$1.value.count) }) {
            let avg = best.value.reduce(0, +) / best.value.count
            bestWeekday = (frenchDays[best.key], avg)
        } else {
            bestWeekday = nil
        }

        hourlyProductivity = store.hourlyProductivity
    }

    // Returns true if the cache is still valid for the given store.
    func isValid(for store: DataStore) -> Bool {
        dataVersion == store.dataVersion
    }
}
