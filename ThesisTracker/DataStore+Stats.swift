import Foundation
import SwiftUI

// MARK: - Stats extension
// Heavy computed statistics extracted from DataStore to limit the God Object surface.
// All methods here are read-only and rely on DataStore's caches (invalidated on save/load).

extension DataStore {

    // MARK: - V3.4 Enriched stats & projection

    var thesisRemainingChars: Int {
        if let c = _thesisRemainingCharsCache, c.version == dataVersion { return c.value }
        let value = data.projects.flatMap { $0.chapters }.reduce(0) { sum, ch in
            guard !ch.isCompleted, ch.goal > 0 else { return sum }
            let latest = ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            return sum + max(0, ch.goal - latest)
        }
        _thesisRemainingCharsCache = (dataVersion, value)
        return value
    }

    /// Meilleur jour hors aujourd'hui (record personnel).
    var allTimeBestDay: Int {
        if let c = _allTimeBestDayCache, c.version == dataVersion { return c.value }
        let today = DataStore.today
        let value = dailyTotals().filter { $0.key != today }.values.max() ?? 0
        _allTimeBestDayCache = (dataVersion, value)
        return value
    }

    /// Date du meilleur jour (pour l'affichage).
    var allTimeBestDayDate: String? {
        if let c = _allTimeBestDayDateCache, c.version == dataVersion { return c.value }
        let today = DataStore.today
        let totals = dailyTotals().filter { $0.key != today }
        var result: String? = nil
        if let maxVal = totals.values.max(), maxVal > 0,
           let entry = totals.first(where: { $0.value == maxVal }),
           let date  = DataStore.parseDate(entry.key) {
            result = DataStore.shortDayMonthFormatter.string(from: date)
        }
        _allTimeBestDayDateCache = (dataVersion, result)
        return result
    }

    /// Nombre de jours distincts avec au moins une entrée > 0 ce mois-ci.
    var daysWrittenThisMonth: Int {
        if let c = _daysWrittenThisMonthCache, c.version == dataVersion { return c.value }
        // Use string prefix comparison — "yyyy-MM-dd".prefix(7) == "yyyy-MM" — no DateFormatter alloc
        let currentMonthPrefix = String(DataStore.today.prefix(7)) // "yyyy-MM"
        let value = dailyTotals().filter { $0.value > 0 && $0.key.hasPrefix(currentMonthPrefix) }.count
        _daysWrittenThisMonthCache = (dataVersion, value)
        return value
    }

    /// Nombre total de jours dans le mois courant (pour afficher "X/30").
    var daysInCurrentMonth: Int {
        DataStore.gregorianCal.range(of: .day, in: .month, for: Date())?.count ?? 30
    }

    var velocity14Days: Int {
        if let c = _velocity14DaysCache, c.version == dataVersion { return c.value }
        let totals = dailyTotals()
        var increments: [Int] = []
        for offset in 1...14 {
            guard let date = DataStore.gregorianCal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let total = totals[DataStore.dateString(from: date)] ?? 0
            if total > 0 { increments.append(total) }
        }
        let value = increments.isEmpty ? 0 : increments.reduce(0, +) / increments.count
        _velocity14DaysCache = (dataVersion, value)
        return value
    }

    var thesisProjectedDays: Int? {
        let remaining = thesisRemainingChars
        let vel = velocity14Days
        guard vel > 0 else { return nil }
        if remaining <= 0 { return 0 }
        return Int(ceil(Double(remaining) / Double(vel)))
    }

    var allMonthlyStats: [(label: String, chars: Int)] {
        if let c = _allMonthlyStatsCache, c.version == dataVersion { return c.stats }
        let result = _computeAllMonthlyStats()
        _allMonthlyStatsCache = (dataVersion, result)
        return result
    }

    private static let monthlyLabelFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM yy"; return f
    }()

    private func _computeAllMonthlyStats() -> [(label: String, chars: Int)] {
        let cal    = DataStore.gregorianCal
        let totals = dailyTotals()
        guard !totals.isEmpty else { return [] }

        var byMonth: [String: (start: Date, count: Int)] = [:]
        for (dateStr, val) in totals where val > 0 {
            guard let d = DataStore.parseDate(dateStr),
                  let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: d)) else { continue }
            let key = DataStore.monthYearKeyFormatter.string(from: monthStart)
            if byMonth[key] == nil { byMonth[key] = (monthStart, 0) }
            byMonth[key]!.count += val
        }
        guard let earliestKey = byMonth.keys.min(),
              let firstMonth = byMonth[earliestKey]?.start else { return [] }

        var results: [(String, Int)] = []
        var cursor = firstMonth
        let now = Date()
        while cursor <= now {
            let key   = DataStore.monthYearKeyFormatter.string(from: cursor)
            let chars = byMonth[key]?.count ?? 0
            results.append((DataStore.monthlyLabelFormatter.string(from: cursor).capitalized, chars))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    private static let shortMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "MMM"; return f
    }()

    var last6MonthsStats: [(label: String, chars: Int)] {
        let cal = DataStore.gregorianCal
        let now = Date()
        let slots: [(key: String, date: Date)] = (0..<6).reversed().compactMap { offset in
            guard let d = cal.date(byAdding: .month, value: -offset, to: now) else { return nil }
            return (DataStore.monthYearKeyFormatter.string(from: d), d)
        }
        var byMonth: [String: Int] = [:]
        for (dateStr, val) in dailyTotals() where val > 0 {
            guard let d = DataStore.parseDate(dateStr) else { continue }
            byMonth[DataStore.monthYearKeyFormatter.string(from: d), default: 0] += val
        }
        return slots.map { (DataStore.shortMonthFormatter.string(from: $0.date).capitalized, byMonth[$0.key] ?? 0) }
    }

    var weekdayAverages: [(day: String, avg: Int)] {
        if let c = _weekdayAveragesCache, c.version == dataVersion { return c.averages }
        let result = _computeWeekdayAverages()
        _weekdayAveragesCache = (dataVersion, result)
        return result
    }

    private func _computeWeekdayAverages() -> [(day: String, avg: Int)] {
        let frenchDays = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        var cal = DataStore.gregorianCal
        cal.firstWeekday = 2
        var byWeekday: [Int: [Int]] = [:]
        for (dateStr, val) in dailyTotals() where val > 0 {
            guard let date = DataStore.parseDate(dateStr) else { continue }
            let wd  = cal.component(.weekday, from: date)
            let idx = (wd + 5) % 7
            byWeekday[idx, default: []].append(val)
        }
        return (0..<7).map { idx in
            let values = byWeekday[idx] ?? []
            let avg = values.isEmpty ? 0 : values.reduce(0, +) / values.count
            return (frenchDays[idx], avg)
        }
    }

    var bestWeekStat: (label: String, chars: Int)? {
        if let c = _bestWeekStatCache, c.version == dataVersion { return c.stat }
        var byWeek: [String: Int] = [:]
        for (dateStr, val) in dailyTotals() where val > 0 {
            guard let date = DataStore.parseDate(dateStr),
                  let weekStart = DataStore.isoWeekCal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            byWeek[DataStore.dateString(from: weekStart), default: 0] += val
        }
        let result: (label: String, chars: Int)?
        if let best = byWeek.max(by: { $0.value < $1.value }),
           let startDate = DataStore.parseDate(best.key) {
            result = ("Sem. du \(DataStore.dayMonthYearFormatter.string(from: startDate))", best.value)
        } else {
            result = nil
        }
        _bestWeekStatCache = (dataVersion, result)
        return result
    }

    // MARK: - V5 Rolling velocity & Cumulative

    /// Vitesse glissante (moyenne sur `windowDays` jours actifs) pour chaque jour des `daysBack` derniers jours.
    func rollingVelocityData(windowDays: Int = 7, daysBack: Int = 90, projectId: UUID? = nil) -> [(date: Date, velocity: Int)] {
        let cal    = DataStore.gregorianCal
        let today  = cal.startOfDay(for: Date())
        let totals = dailyTotals(projectId: projectId)

        return (0..<daysBack).reversed().compactMap { offset -> (Date, Int)? in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return nil }
            var windowVals: [Int] = []
            for w in 1...windowDays {
                guard let wDay = cal.date(byAdding: .day, value: -w, to: day) else { continue }
                let val = totals[DataStore.dateString(from: wDay)] ?? 0
                if val > 0 { windowVals.append(val) }
            }
            let avg = windowVals.isEmpty ? 0 : windowVals.reduce(0, +) / windowVals.count
            return (day, avg)
        }
    }

    /// Progression cumulative depuis le premier jour d'écriture jusqu'à aujourd'hui.
    func cumulativeData(projectId: UUID? = nil, chapterId: UUID? = nil) -> [(date: Date, total: Int)] {
        let totals = dailyTotals(projectId: projectId, chapterId: chapterId)
        guard !totals.isEmpty else { return [] }
        let cal = DataStore.gregorianCal
        guard let firstDateStr = totals.keys.filter({ (totals[$0] ?? 0) > 0 }).sorted().first,
              let firstDate    = DataStore.parseDate(firstDateStr) else { return [] }
        let today  = cal.startOfDay(for: Date())
        var cumul  = 0
        var result: [(Date, Int)] = []
        var cursor = cal.startOfDay(for: firstDate)
        while cursor <= today {
            cumul += totals[DataStore.dateString(from: cursor)] ?? 0
            result.append((cursor, cumul))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    /// Total de tous les caractères jamais écrits (somme de tous les incréments quotidiens).
    var totalCharsEverWritten: Int {
        dailyTotals().values.reduce(0, +)
    }

    // MARK: - Hourly productivity

    var hourlyProductivity: [Int] {
        if let c = _hourlyProductivityCache, c.version == dataVersion { return c.counts }
        let result = _computeHourlyProductivity()
        _hourlyProductivityCache = (dataVersion, result)
        return result
    }

    // MARK: - Plateau detection (V5 — amélioration #6)

    struct PlateauChapter {
        let project: Project
        let chapter: Chapter
        let daysSinceLastEntry: Int   // 999 = aucune entrée
        let daysUntilDeadline: Int
    }

    /// Chapitres qui stagnent (≥ 5 jours sans écriture) avec une deadline ≤ 60 jours.
    var plateauChapters: [PlateauChapter] {
        if let c = _plateauChaptersCache, c.version == dataVersion { return c.chapters }
        let today = Date()
        let cal = DataStore.gregorianCal
        var result: [PlateauChapter] = []

        for project in data.projects {
            for chapter in project.chapters {
                // Exclure les chapitres terminés
                guard !chapter.isCompleted, chapter.status != .termine else { continue }
                // Requiert une deadline dans les 60 prochains jours
                guard let deadlineStr = chapter.deadline,
                      let deadlineDate = DataStore.parseDate(deadlineStr) else { continue }
                let daysUntil = cal.dateComponents([.day], from: today, to: deadlineDate).day ?? 0
                guard daysUntil > 0, daysUntil <= 60 else { continue }
                // Calcule le nombre de jours sans écriture
                let daysSince: Int
                if let lastEntry = chapter.entries.max(by: { $0.date < $1.date }),
                   let lastDate  = DataStore.parseDate(lastEntry.date) {
                    daysSince = max(0, cal.dateComponents([.day], from: lastDate, to: today).day ?? 0)
                } else {
                    daysSince = 999
                }
                guard daysSince >= 5 else { continue }
                result.append(PlateauChapter(project: project, chapter: chapter,
                                             daysSinceLastEntry: daysSince,
                                             daysUntilDeadline: daysUntil))
            }
        }
        let sorted = result.sorted { $0.daysUntilDeadline < $1.daysUntilDeadline }
        _plateauChaptersCache = (dataVersion, sorted)
        return sorted
    }

    // MARK: - Stats & Analyse (#8–#14)

    // #9 — Top 10 sessions (toutes données confondues)
    struct TopDayEntry {
        let date: String
        let total: Int
        let projectName: String?
    }

    var top10Days: [TopDayEntry] {
        if let c = _top10DaysCache, c.version == dataVersion { return c.entries }
        let global = dailyTotals()
        let perProject: [(String, [String: Int])] = data.projects.map { ($0.name, dailyTotals(projectId: $0.id)) }
        let entries = global
            .sorted { $0.value > $1.value }
            .prefix(10)
            .compactMap { (dateStr, total) -> TopDayEntry? in
                guard total > 0 else { return nil }
                let topProject = perProject.max { a, b in (a.1[dateStr] ?? 0) < (b.1[dateStr] ?? 0) }?.0
                return TopDayEntry(date: dateStr, total: total, projectName: topProject)
            }
        _top10DaysCache = (dataVersion, entries)
        return entries
    }

    // #12 — Plage de velocité (min/moy/max) sur les 14 derniers jours actifs
    var velocityStats14Days: (min: Int, max: Int, avg: Int) {
        let cal = DataStore.gregorianCal
        let totals = dailyTotals()
        var vals: [Int] = []
        for offset in 1...14 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let t = totals[DataStore.dateString(from: date)] ?? 0
            if t > 0 { vals.append(t) }
        }
        guard !vals.isEmpty else { return (0, 0, 0) }
        return (vals.min()!, vals.max()!, vals.reduce(0, +) / vals.count)
    }

    // #13 — Répartition par projet sur les 30 derniers jours
    struct ProjectShare {
        let name: String
        let total: Int
        let colorIndex: Int   // index dans la palette standard
    }

    var projectDistribution30Days: [ProjectShare] {
        if let c = _projectDistribution30Cache, c.version == dataVersion { return c.shares }
        let cal = DataStore.gregorianCal
        let now = Date()
        let shares = data.projects.enumerated().compactMap { (idx, project) -> ProjectShare? in
            let projectTotals = dailyTotals(projectId: project.id)
            var total = 0
            for offset in 0..<30 {
                guard let date = cal.date(byAdding: .day, value: -offset, to: now) else { continue }
                total += projectTotals[DataStore.dateString(from: date)] ?? 0
            }
            guard total > 0 else { return nil }
            return ProjectShare(name: project.name, total: total, colorIndex: idx)
        }.sorted { $0.total > $1.total }
        _projectDistribution30Cache = (dataVersion, shares)
        return shares
    }

    // #14 — Jours sans écriture ce mois-ci
    var daysWithoutWritingThisMonth: Int {
        let cal = DataStore.gregorianCal
        let dayOfMonth = cal.component(.day, from: Date())
        let writtenToday = (dailyTotals()[DataStore.today] ?? 0) > 0
        let daysElapsed = writtenToday ? dayOfMonth : max(0, dayOfMonth - 1)
        return max(0, daysElapsed - daysWrittenThisMonth)
    }

    private func _computeHourlyProductivity() -> [Int] {
        var counts = [Int](repeating: 0, count: 24)
        for project in data.projects {
            for chapter in project.chapters {
                // Single sorted pass — O(n log n) instead of O(n²)
                var previous = 0
                for entry in chapter.entries.sorted(by: { $0.date < $1.date }) {
                    let increment = max(0, entry.totalCount - previous)
                    if increment > 0, let hour = entry.savedAtHour, hour >= 0, hour < 24 {
                        counts[hour] += increment
                    }
                    previous = entry.totalCount
                }
            }
        }
        return counts
    }
}
