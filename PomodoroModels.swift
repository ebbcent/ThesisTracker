import Foundation

// MARK: - Sound

enum PomodoroSound: String, Codable, CaseIterable, Identifiable {
    case none
    case basso      = "Basso"
    case blow       = "Blow"
    case bottle     = "Bottle"
    case frog       = "Frog"
    case funk       = "Funk"
    case glass      = "Glass"
    case hero       = "Hero"
    case morse      = "Morse"
    case ping       = "Ping"
    case pop        = "Pop"
    case purr       = "Purr"
    case sosumi     = "Sosumi"
    case submarine  = "Submarine"
    case tink       = "Tink"

    var id: String { rawValue }
    var displayName: String { self == .none ? "Silence" : rawValue }
}

// MARK: - Session kind

enum SessionKind: String, Codable, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .focus: "Concentration"
        case .shortBreak: "Pause courte"
        case .longBreak: "Pause longue"
        }
    }
}

enum SessionCompletionState: String, Codable, CaseIterable {
    case completed
    case interrupted

    var displayName: String {
        switch self {
        case .completed: "Terminée"
        case .interrupted: "Interrompue"
        }
    }
}

enum GoalPeriod: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: "Quotidien"
        case .weekly: "Hebdomadaire"
        case .monthly: "Mensuel"
        }
    }
}

enum GoalMetric: String, Codable, CaseIterable, Identifiable {
    case sessions
    case minutes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sessions: "sessions"
        case .minutes: "minutes"
        }
    }
}

// MARK: - Settings

struct PomodoroAppSettings: Codable, Equatable {
    var focusDuration: TimeInterval
    var shortBreakDuration: TimeInterval
    var longBreakDuration: TimeInterval
    var sessionsBeforeLongBreak: Int
    var workBlockMaxBreakMinutes: Int
    var focusCompletionSound: PomodoroSound
    var shortBreakCompletionSound: PomodoroSound
    var longBreakCompletionSound: PomodoroSound
    var soundVolume: Float
    var wordsPerSessionGoal: Int
    var pauseReminderMinutes: Int
    var deepWorkEnabled: Bool
    var updatedAt: Date

    static let `default` = PomodoroAppSettings(
        focusDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        sessionsBeforeLongBreak: 4,
        workBlockMaxBreakMinutes: 90,
        focusCompletionSound: .glass,
        shortBreakCompletionSound: .tink,
        longBreakCompletionSound: .hero,
        soundVolume: 0.8,
        wordsPerSessionGoal: 0,
        pauseReminderMinutes: 5,
        deepWorkEnabled: false,
        updatedAt: .now
    )
}

extension PomodoroAppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        focusDuration = try c.decode(TimeInterval.self, forKey: .focusDuration)
        shortBreakDuration = try c.decode(TimeInterval.self, forKey: .shortBreakDuration)
        longBreakDuration = try c.decode(TimeInterval.self, forKey: .longBreakDuration)
        sessionsBeforeLongBreak = try c.decode(Int.self, forKey: .sessionsBeforeLongBreak)
        workBlockMaxBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .workBlockMaxBreakMinutes) ?? 90
        focusCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .focusCompletionSound) ?? .glass
        shortBreakCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .shortBreakCompletionSound) ?? .tink
        longBreakCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .longBreakCompletionSound) ?? .hero
        soundVolume = try c.decodeIfPresent(Float.self, forKey: .soundVolume) ?? 0.8
        wordsPerSessionGoal = try c.decodeIfPresent(Int.self, forKey: .wordsPerSessionGoal) ?? 0
        pauseReminderMinutes = try c.decodeIfPresent(Int.self, forKey: .pauseReminderMinutes) ?? 5
        deepWorkEnabled = try c.decodeIfPresent(Bool.self, forKey: .deepWorkEnabled) ?? false
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Entities

struct PomodoroActivityCategory: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date

    static func `default`() -> [PomodoroActivityCategory] {
        [
            PomodoroActivityCategory(id: UUID(), name: "Rédaction", colorHex: "#D97706", createdAt: .now, updatedAt: .now),
            PomodoroActivityCategory(id: UUID(), name: "Recherche", colorHex: "#0F766E", createdAt: .now, updatedAt: .now),
            PomodoroActivityCategory(id: UUID(), name: "Enseignement", colorHex: "#7C3AED", createdAt: .now, updatedAt: .now)
        ]
    }
}

struct PomodoroGoalDefinition: Codable, Identifiable, Hashable {
    var id: UUID
    var title: String
    var period: GoalPeriod
    var metric: GoalMetric
    var target: Int
    var categoryID: UUID?
    var projectID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct PomodoroProjectRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var detail: String
    var colorHex: String
    var targetSessionCount: Int?
    var targetMinutes: Int?
    var createdAt: Date
    var updatedAt: Date
}

struct PomodoroSessionRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    var plannedDuration: TimeInterval
    var kind: SessionKind
    var completionState: SessionCompletionState
    var categoryID: UUID?
    var projectID: UUID?
    var note: String
    var createdAt: Date
    var updatedAt: Date
}

struct PomodoroWorkBlockRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var sessionIDs: [UUID]
    var startedAt: Date
    var endedAt: Date
    var focusSessionCount: Int
    var totalFocusDuration: TimeInterval
    var createdAt: Date
    var updatedAt: Date
}

struct PomodoroGlobalStatisticsSnapshot: Codable, Equatable {
    var totalFocusMinutes: Int
    var totalCompletedSessions: Int
    var completionRate: Double
    var averageBlockMinutes: Double
    var generatedAt: Date

    static let empty = PomodoroGlobalStatisticsSnapshot(
        totalFocusMinutes: 0,
        totalCompletedSessions: 0,
        completionRate: 0,
        averageBlockMinutes: 0,
        generatedAt: .now
    )
}

struct PomodoroAppData: Codable, Equatable {
    var schemaVersion: Int
    var settings: PomodoroAppSettings
    var globalStatistics: PomodoroGlobalStatisticsSnapshot
    var goals: [PomodoroGoalDefinition]
    var categories: [PomodoroActivityCategory]
    var projects: [PomodoroProjectRecord]
    var sessions: [PomodoroSessionRecord]
    var workBlocks: [PomodoroWorkBlockRecord]
    var updatedAt: Date

    static func empty(now: Date = .now) -> PomodoroAppData {
        let defaultGoals = [
            PomodoroGoalDefinition(
                id: UUID(),
                title: "Concentration quotidienne",
                period: .daily,
                metric: .minutes,
                target: 120,
                categoryID: nil,
                projectID: nil,
                createdAt: now,
                updatedAt: now
            ),
            PomodoroGoalDefinition(
                id: UUID(),
                title: "Sessions hebdomadaires",
                period: .weekly,
                metric: .sessions,
                target: 20,
                categoryID: nil,
                projectID: nil,
                createdAt: now,
                updatedAt: now
            )
        ]

        return PomodoroAppData(
            schemaVersion: 1,
            settings: .default,
            globalStatistics: .empty,
            goals: defaultGoals,
            categories: PomodoroActivityCategory.default(),
            projects: [],
            sessions: [],
            workBlocks: [],
            updatedAt: now
        )
    }
}

// MARK: - Helpers

extension Array where Element == PomodoroSessionRecord {
    func focusOnly() -> [PomodoroSessionRecord] {
        filter { $0.kind == .focus }
    }

    func completedFocusOnly() -> [PomodoroSessionRecord] {
        filter { $0.kind == .focus && $0.completionState == .completed }
    }
}
