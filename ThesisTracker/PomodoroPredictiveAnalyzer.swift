import Foundation

struct PomodoroProductivityPrediction {
    var probableTodayMinutes: Int
    var probableWeekMinutes: Int
    var dailyGoalProbability: Double
    var weeklyGoalProbability: Double
    var minutesRemainingToday: Int
    var minutesRemainingThisWeek: Int
    var bestFocusHours: [Int]

    static let empty = PomodoroProductivityPrediction(
        probableTodayMinutes: 0,
        probableWeekMinutes: 0,
        dailyGoalProbability: 0,
        weeklyGoalProbability: 0,
        minutesRemainingToday: 0,
        minutesRemainingThisWeek: 0,
        bestFocusHours: []
    )
}

enum PomodoroPredictiveAnalyzer {
    static func buildPrediction(from data: PomodoroAppData, now: Date = .now) -> PomodoroProductivityPrediction {
        let calendar = Calendar.current
        let completedFocus = data.sessions.completedFocusOnly()
        guard !completedFocus.isEmpty else { return .empty }

        let recentDays = Dictionary(grouping: completedFocus) { calendar.startOfDay(for: $0.startedAt) }
        let recentDailyMinutes = recentDays.values.map { sessions in
            Int(sessions.reduce(0) { $0 + $1.duration } / 60)
        }
        let averageDailyMinutes = Int(Double(recentDailyMinutes.reduce(0, +)) / Double(max(1, recentDailyMinutes.count)))
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let currentWeekMinutes = completedFocus
            .filter { currentWeek?.contains($0.startedAt) ?? false }
            .reduce(0) { $0 + Int($1.duration / 60) }
        let probableWeekMinutes = max(currentWeekMinutes, averageDailyMinutes * 5)

        let hourHistogram = completedFocus.reduce(into: [Int: Double]()) { partialResult, session in
            partialResult[calendar.component(.hour, from: session.startedAt), default: 0] += session.duration / 60
        }
        let bestHours = hourHistogram
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)
            .sorted()

        let dailyGoalMinutes = data.goals
            .filter { $0.period == .daily && $0.metric == .minutes }
            .map(\.target)
            .max() ?? 0
        let weeklyGoalMinutes = data.goals
            .filter { $0.period == .weekly && $0.metric == .minutes }
            .map(\.target)
            .max() ?? 0

        return PomodoroProductivityPrediction(
            probableTodayMinutes: averageDailyMinutes,
            probableWeekMinutes: probableWeekMinutes,
            dailyGoalProbability: probability(predicted: averageDailyMinutes, target: dailyGoalMinutes),
            weeklyGoalProbability: probability(predicted: probableWeekMinutes, target: weeklyGoalMinutes),
            minutesRemainingToday: max(0, dailyGoalMinutes - completedMinutes(on: now, sessions: completedFocus)),
            minutesRemainingThisWeek: max(0, weeklyGoalMinutes - currentWeekMinutes),
            bestFocusHours: bestHours
        )
    }

    private static func completedMinutes(on date: Date, sessions: [PomodoroSessionRecord]) -> Int {
        let calendar = Calendar.current
        return sessions
            .filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
            .reduce(0) { $0 + Int($1.duration / 60) }
    }

    private static func probability(predicted: Int, target: Int) -> Double {
        guard target > 0 else { return 1 }
        return min(1, max(0, Double(predicted) / Double(target)))
    }
}
