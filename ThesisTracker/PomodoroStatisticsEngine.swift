import Foundation

enum PomodoroStatisticsRange: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var frenchLabel: String {
        switch self {
        case .daily:   "Jour"
        case .weekly:  "Semaine"
        case .monthly: "Mois"
        case .yearly:  "Année"
        }
    }
}

struct PomodoroDashboardSummary {
    var completedFocusSessions: Int
    var interruptedFocusSessions: Int
    var focusMinutes: Int
    var completionRate: Double
    var averageBlockMinutes: Double

    static let empty = PomodoroDashboardSummary(
        completedFocusSessions: 0,
        interruptedFocusSessions: 0,
        focusMinutes: 0,
        completionRate: 0,
        averageBlockMinutes: 0
    )
}

struct PomodoroGoalProgress: Identifiable {
    let id: UUID
    let title: String
    let progress: Double
    let currentValue: Int
    let targetValue: Int
    let description: String
    let remainingText: String
}

struct PomodoroTimelineEntry: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let startedAt: Date
    let endedAt: Date
    let colorHex: String
}

struct PomodoroPeriodMetric: Identifiable {
    let id = UUID()
    let label: String
    let sessions: Int
    let minutes: Int
    let startDate: Date
}

struct PomodoroContributionCell: Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int
    let intensity: Double
}

struct PomodoroDistributionBucket: Identifiable {
    let id = UUID()
    let label: String
    let minutes: Double
}

struct PomodoroProjectInsight: Identifiable {
    let id: UUID
    let name: String
    let completedSessions: Int
    let focusMinutes: Int
    let blockCount: Int
    let noteCount: Int
    let progressText: String
}

struct PomodoroTodayOperationalSnapshot {
    let completedSessions: Int
    let interruptedSessions: Int
    let focusMinutes: Int
    let remainingDailyMinutesGoal: Int
    let remainingDailySessionsGoal: Int
    let nextMilestoneText: String
    let recentCompletedSessions: [PomodoroSessionRecord]

    static let empty = PomodoroTodayOperationalSnapshot(
        completedSessions: 0,
        interruptedSessions: 0,
        focusMinutes: 0,
        remainingDailyMinutesGoal: 0,
        remainingDailySessionsGoal: 0,
        nextMilestoneText: "",
        recentCompletedSessions: []
    )
}

struct PomodoroDailySummary {
    let headline: String
    let detail: String
    let highlights: [String]

    static let empty = PomodoroDailySummary(headline: "", detail: "", highlights: [])
}

struct PomodoroDailyTimelineSegment: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let startedAt: Date
    let endedAt: Date
    let startHourOffset: Double
    let durationHours: Double
    let colorHex: String
}

// MARK: - Statistics Engine

enum PomodoroStatisticsEngine {
    static func currentStreak(data: PomodoroAppData, now: Date = .now) -> Int {
        let calendar = Calendar.current
        let completedDays = Set(
            data.sessions.completedFocusOnly()
                .map { calendar.startOfDay(for: $0.startedAt) }
        )

        guard !completedDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: now)

        if !completedDays.contains(cursor),
           let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor),
           completedDays.contains(previousDay) {
            cursor = previousDay
        }

        while completedDays.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previousDay
        }

        return streak
    }

    static func dashboardSummary(for date: Date, data: PomodoroAppData) -> PomodoroDashboardSummary {
        let focusSessions = sessions(for: .daily, anchor: date, data: data, categoryID: nil, projectID: nil).focusOnly()
        guard !focusSessions.isEmpty else { return .empty }
        let completed = focusSessions.filter { $0.completionState == .completed }
        let interrupted = focusSessions.filter { $0.completionState == .interrupted }
        let dayBlocks = data.workBlocks.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }

        return PomodoroDashboardSummary(
            completedFocusSessions: completed.count,
            interruptedFocusSessions: interrupted.count,
            focusMinutes: Int(completed.reduce(0) { $0 + $1.duration } / 60),
            completionRate: Double(completed.count) / Double(max(1, focusSessions.count)),
            averageBlockMinutes: dayBlocks.isEmpty ? 0 : dayBlocks.reduce(0) { $0 + $1.totalFocusDuration } / Double(dayBlocks.count * 60)
        )
    }

    static func operationalSnapshot(for date: Date, data: PomodoroAppData) -> PomodoroTodayOperationalSnapshot {
        let focusSessions = sessions(for: .daily, anchor: date, data: data, categoryID: nil, projectID: nil).focusOnly()
        let completed = focusSessions.filter { $0.completionState == .completed }
        let interrupted = focusSessions.filter { $0.completionState == .interrupted }
        let focusMinutes = Int(completed.reduce(0) { $0 + $1.duration } / 60)

        let dailyMinutesGoal = data.goals
            .filter { $0.period == .daily && $0.metric == .minutes }
            .map(\.target)
            .max() ?? 0
        let dailySessionsGoal = data.goals
            .filter { $0.period == .daily && $0.metric == .sessions }
            .map(\.target)
            .max() ?? 0

        let remainingMinutes = max(0, dailyMinutesGoal - focusMinutes)
        let remainingSessions = max(0, dailySessionsGoal - completed.count)
        let nextMilestoneText: String
        if remainingMinutes > 0 {
            nextMilestoneText = "Encore \(remainingMinutes) min pour l'objectif quotidien."
        } else if remainingSessions > 0 {
            nextMilestoneText = "Encore \(remainingSessions) session(s) pour l'objectif quotidien."
        } else {
            nextMilestoneText = "Objectif quotidien atteint."
        }

        return PomodoroTodayOperationalSnapshot(
            completedSessions: completed.count,
            interruptedSessions: interrupted.count,
            focusMinutes: focusMinutes,
            remainingDailyMinutesGoal: remainingMinutes,
            remainingDailySessionsGoal: remainingSessions,
            nextMilestoneText: nextMilestoneText,
            recentCompletedSessions: Array(completed.sorted { $0.endedAt > $1.endedAt }.prefix(5))
        )
    }

    static func journalSessions(data: PomodoroAppData, categoryID: UUID?, projectID: UUID?, searchText: String, selectedDay: Date?) -> [PomodoroSessionRecord] {
        data.sessions
            .filter {
                (categoryID == nil || $0.categoryID == categoryID) &&
                (projectID == nil || $0.projectID == projectID)
            }
            .filter {
                guard let selectedDay else { return true }
                return Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDay)
            }
            .filter {
                searchText.isEmpty || $0.note.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    static func globalSnapshot(for data: PomodoroAppData) -> PomodoroGlobalStatisticsSnapshot {
        let focusSessions = data.sessions.focusOnly()
        let completed = focusSessions.filter { $0.completionState == .completed }
        let averageBlockMinutes = data.workBlocks.isEmpty ? 0 : data.workBlocks.reduce(0) { $0 + $1.totalFocusDuration } / Double(data.workBlocks.count * 60)

        return PomodoroGlobalStatisticsSnapshot(
            totalFocusMinutes: Int(completed.reduce(0) { $0 + $1.duration } / 60),
            totalCompletedSessions: completed.count,
            completionRate: Double(completed.count) / Double(max(1, focusSessions.count)),
            averageBlockMinutes: averageBlockMinutes,
            generatedAt: .now
        )
    }

    static func goalProgress(for data: PomodoroAppData, now: Date = .now) -> [PomodoroGoalProgress] {
        data.goals.map { goal in
            let s = sessions(for: goal.period.statisticsRange, anchor: now, data: data, categoryID: goal.categoryID, projectID: goal.projectID)
            let focus = s.focusOnly()
            let currentValue: Int
            switch goal.metric {
            case .sessions:
                currentValue = focus.filter { $0.completionState == .completed }.count
            case .minutes:
                currentValue = Int(focus.filter { $0.completionState == .completed }.reduce(0) { $0 + $1.duration } / 60)
            }

            return PomodoroGoalProgress(
                id: goal.id,
                title: goal.title,
                progress: min(1, Double(currentValue) / Double(max(1, goal.target))),
                currentValue: currentValue,
                targetValue: goal.target,
                description: "\(currentValue) / \(goal.target) \(goal.metric.displayName)",
                remainingText: remainingText(for: goal, currentValue: currentValue)
            )
        }
    }

    static func timeline(for date: Date, data: PomodoroAppData) -> [PomodoroTimelineEntry] {
        let categoriesByID = Dictionary(data.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return data.sessions
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt < $1.startedAt }
            .map { session in
                let category = session.categoryID.flatMap { categoriesByID[$0] }
                return PomodoroTimelineEntry(
                    id: session.id,
                    title: session.kind.displayName,
                    subtitle: session.note.isEmpty ? session.completionState.displayName : session.note,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    colorHex: category?.colorHex ?? (session.kind == .focus ? "#1D4ED8" : "#6B7280")
                )
            }
    }

    static func dailyTimeline(for date: Date, data: PomodoroAppData) -> [PomodoroDailyTimelineSegment] {
        let categoriesByID = Dictionary(data.categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return data.sessions
            .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            .sorted { $0.startedAt < $1.startedAt }
            .map { session in
                let category = session.categoryID.flatMap { categoriesByID[$0] }
                let minutesFromMidnight = Double(Calendar.current.dateComponents([.minute], from: Calendar.current.startOfDay(for: session.startedAt), to: session.startedAt).minute ?? 0)
                return PomodoroDailyTimelineSegment(
                    id: session.id,
                    title: session.kind.displayName,
                    subtitle: session.note.isEmpty ? session.completionState.displayName : session.note,
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    startHourOffset: minutesFromMidnight / 60,
                    durationHours: max(session.duration / 3600, 0.15),
                    colorHex: category?.colorHex ?? (session.kind == .focus ? "#1D4ED8" : "#6B7280")
                )
            }
    }

    static func dailySummary(for date: Date, data: PomodoroAppData) -> PomodoroDailySummary {
        let snapshot = operationalSnapshot(for: date, data: data)
        let completionRate = dashboardSummary(for: date, data: data).completionRate
        let completedProjects = Set(
            data.sessions.completedFocusOnly()
                .filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
                .compactMap(\.projectID)
        ).count

        let headline: String
        if snapshot.completedSessions >= 6 {
            headline = "Très bonne journée de concentration"
        } else if snapshot.completedSessions >= 3 {
            headline = "Journée solide et régulière"
        } else if snapshot.completedSessions >= 1 {
            headline = "Journée bien engagée"
        } else {
            headline = "Aucune session terminée aujourd'hui"
        }

        let detail = "Taux de complétion \(Int(completionRate * 100))% • \(snapshot.focusMinutes) min concentrées • \(completedProjects) projet(s) actifs"
        var highlights: [String] = []
        highlights.append(snapshot.nextMilestoneText)
        if snapshot.interruptedSessions > 0 {
            highlights.append("\(snapshot.interruptedSessions) session(s) interrompue(s) à analyser")
        }
        if snapshot.completedSessions > 0 {
            highlights.append("Dernière session terminée : \(snapshot.recentCompletedSessions.first?.endedAt.formatted(date: .omitted, time: .shortened) ?? "n/a")")
        }

        return PomodoroDailySummary(headline: headline, detail: detail, highlights: highlights)
    }

    static func chartMetrics(for range: PomodoroStatisticsRange, anchor: Date, data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroPeriodMetric] {
        let calendar = Calendar.current
        let s = sessions(for: range, anchor: anchor, data: data, categoryID: categoryID, projectID: projectID).focusOnly()
        let grouped = Dictionary(grouping: s) { session in
            bucketStart(for: session.startedAt, range: range, calendar: calendar)
        }

        let keys = grouped.keys.sorted()
        return keys.map { key in
            let bucketSessions = grouped[key] ?? []
            return PomodoroPeriodMetric(
                label: label(for: key, range: range),
                sessions: bucketSessions.filter { $0.completionState == .completed }.count,
                minutes: Int(bucketSessions.filter { $0.completionState == .completed }.reduce(0) { $0 + $1.duration } / 60),
                startDate: key
            )
        }
    }

    static func contributionCalendar(for year: Int, data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroContributionCell] {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .now
        let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? .now
        let s = data.sessions.completedFocusOnly().filter {
            $0.startedAt >= start && $0.startedAt < end
                && (categoryID == nil || $0.categoryID == categoryID)
                && (projectID == nil || $0.projectID == projectID)
        }
        let perDay = Dictionary(grouping: s) { calendar.startOfDay(for: $0.startedAt) }
            .mapValues { Int($0.reduce(0) { $0 + $1.duration } / 60) }
        let maxMinutes = max(1, perDay.values.max() ?? 1)

        // Nombre de jours de l'année (365/366) — `ordinality` du 1er janvier suivant valait 1.
        let dayCount = calendar.dateComponents([.day], from: start, to: end).day ?? 365
        return stride(from: 0, to: max(1, dayCount), by: 1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start), date < end else { return nil }
            let minutes = perDay[calendar.startOfDay(for: date)] ?? 0
            return PomodoroContributionCell(date: date, minutes: minutes, intensity: Double(minutes) / Double(maxMinutes))
        }
    }

    static func weekdayDistribution(data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroDistributionBucket] {
        let calendar = Calendar.current
        let s = filteredCompletedFocus(data: data, categoryID: categoryID, projectID: projectID)
        let minutesByWeekday = s.reduce(into: [Int: Double]()) { partialResult, session in
            partialResult[calendar.component(.weekday, from: session.startedAt), default: 0] += session.duration / 60
        }

        return calendar.weekdaySymbols.enumerated().map { index, symbol in
            PomodoroDistributionBucket(label: symbol, minutes: minutesByWeekday[index + 1, default: 0])
        }
    }

    static func hourlyDistribution(data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroDistributionBucket] {
        let calendar = Calendar.current
        let s = filteredCompletedFocus(data: data, categoryID: categoryID, projectID: projectID)
        let minutesByHour = s.reduce(into: [Int: Double]()) { partialResult, session in
            partialResult[calendar.component(.hour, from: session.startedAt), default: 0] += session.duration / 60
        }

        return (0..<24).map { hour in
            PomodoroDistributionBucket(label: String(format: "%02d:00", hour), minutes: minutesByHour[hour, default: 0])
        }
    }

    static func projectInsights(data: PomodoroAppData) -> [PomodoroProjectInsight] {
        data.projects.map { project in
            let s = data.sessions.completedFocusOnly().filter { $0.projectID == project.id }
            let blocks = data.workBlocks.filter { block in
                s.contains { block.sessionIDs.contains($0.id) }
            }
            let progressText: String
            if let targetMinutes = project.targetMinutes {
                let minutes = Int(s.reduce(0) { $0 + $1.duration } / 60)
                progressText = "\(minutes) / \(targetMinutes) minutes"
            } else if let targetSessionCount = project.targetSessionCount {
                progressText = "\(s.count) / \(targetSessionCount) sessions"
            } else {
                progressText = "\(s.count) sessions"
            }

            return PomodoroProjectInsight(
                id: project.id,
                name: project.name,
                completedSessions: s.count,
                focusMinutes: Int(s.reduce(0) { $0 + $1.duration } / 60),
                blockCount: blocks.count,
                noteCount: s.filter { !$0.note.isEmpty }.count,
                progressText: progressText
            )
        }
    }

    static func sessions(for range: PomodoroStatisticsRange, anchor: Date, data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroSessionRecord] {
        let calendar = Calendar.current
        let interval: DateInterval?

        switch range {
        case .daily:   interval = calendar.dateInterval(of: .day, for: anchor)
        case .weekly:  interval = calendar.dateInterval(of: .weekOfYear, for: anchor)
        case .monthly: interval = calendar.dateInterval(of: .month, for: anchor)
        case .yearly:  interval = calendar.dateInterval(of: .year, for: anchor)
        }

        return data.sessions.filter { session in
            guard interval?.contains(session.startedAt) ?? false else { return false }
            if let categoryID, session.categoryID != categoryID, session.kind == .focus { return false }
            if let projectID, session.projectID != projectID, session.kind == .focus { return false }
            return true
        }
    }

    private static func filteredCompletedFocus(data: PomodoroAppData, categoryID: UUID?, projectID: UUID?) -> [PomodoroSessionRecord] {
        data.sessions.completedFocusOnly().filter {
            (categoryID == nil || $0.categoryID == categoryID) &&
            (projectID == nil || $0.projectID == projectID)
        }
    }

    private static func remainingText(for goal: PomodoroGoalDefinition, currentValue: Int) -> String {
        let remaining = max(0, goal.target - currentValue)
        guard remaining > 0 else { return "Objectif atteint" }

        switch goal.metric {
        case .sessions:
            return "Encore \(remaining) session(s) à valider"
        case .minutes:
            let estimatedSessions = max(1, Int(ceil(Double(remaining) / 25)))
            return "Encore \(remaining) min, soit env. \(estimatedSessions) session(s)"
        }
    }

    private static func bucketStart(for date: Date, range: PomodoroStatisticsRange, calendar: Calendar) -> Date {
        switch range {
        case .daily:
            return calendar.dateInterval(of: .hour, for: date)?.start ?? date
        case .weekly, .monthly:
            return calendar.startOfDay(for: date)
        case .yearly:
            return calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private static func label(for date: Date, range: PomodoroStatisticsRange) -> String {
        let formatter = DateFormatter()
        switch range {
        case .daily:           formatter.dateFormat = "HH:mm"
        case .weekly, .monthly: formatter.dateFormat = "MMM d"
        case .yearly:          formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}

private extension GoalPeriod {
    var statisticsRange: PomodoroStatisticsRange {
        switch self {
        case .daily:   .daily
        case .weekly:  .weekly
        case .monthly: .monthly
        }
    }
}
