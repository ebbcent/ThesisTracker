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
    /// Mode deep work : lance les raccourcis (app Raccourcis) ci-dessous au début / à la fin d'une session.
    var deepWorkEnabled: Bool
    var focusShortcutOnName: String
    var focusShortcutOffName: String
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
        focusShortcutOnName: "",
        focusShortcutOffName: "",
        updatedAt: .now
    )

    // Bornes de validation (fichier modifié à la main ou par une autre version de l'app)
    static let sessionsBeforeLongBreakRange: ClosedRange<Int> = 1...12

    static func clampedDuration(_ value: TimeInterval, min lower: TimeInterval, max upper: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        guard value.isFinite, value > 0 else { return fallback }
        return Swift.min(Swift.max(value, lower), upper)
    }
}

extension PomodoroAppSettings {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PomodoroAppSettings.default
        let decodedFocus = try c.decode(TimeInterval.self, forKey: .focusDuration)
        let decodedShortBreak = try c.decode(TimeInterval.self, forKey: .shortBreakDuration)
        let decodedLongBreak = try c.decode(TimeInterval.self, forKey: .longBreakDuration)
        let decodedSessions = try c.decode(Int.self, forKey: .sessionsBeforeLongBreak)
        let decodedBlockGap = try c.decodeIfPresent(Int.self, forKey: .workBlockMaxBreakMinutes) ?? 90
        focusDuration = Self.clampedDuration(decodedFocus, min: 60, max: 4 * 3600, fallback: defaults.focusDuration)
        shortBreakDuration = Self.clampedDuration(decodedShortBreak, min: 60, max: 2 * 3600, fallback: defaults.shortBreakDuration)
        longBreakDuration = Self.clampedDuration(decodedLongBreak, min: 60, max: 4 * 3600, fallback: defaults.longBreakDuration)
        sessionsBeforeLongBreak = Swift.min(
            Swift.max(decodedSessions, Self.sessionsBeforeLongBreakRange.lowerBound),
            Self.sessionsBeforeLongBreakRange.upperBound
        )
        workBlockMaxBreakMinutes = Swift.min(Swift.max(decodedBlockGap, 1), 24 * 60)
        focusCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .focusCompletionSound) ?? .glass
        shortBreakCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .shortBreakCompletionSound) ?? .tink
        longBreakCompletionSound = try c.decodeIfPresent(PomodoroSound.self, forKey: .longBreakCompletionSound) ?? .hero
        let decodedVolume = try c.decodeIfPresent(Float.self, forKey: .soundVolume) ?? 0.8
        soundVolume = decodedVolume.isFinite ? Swift.min(Swift.max(decodedVolume, 0), 1) : 0.8
        let decodedWordsGoal = try c.decodeIfPresent(Int.self, forKey: .wordsPerSessionGoal) ?? 0
        wordsPerSessionGoal = Swift.max(0, decodedWordsGoal)
        let decodedReminder = try c.decodeIfPresent(Int.self, forKey: .pauseReminderMinutes) ?? 5
        pauseReminderMinutes = Swift.min(Swift.max(decodedReminder, 1), 120)
        deepWorkEnabled = try c.decodeIfPresent(Bool.self, forKey: .deepWorkEnabled) ?? false
        focusShortcutOnName = try c.decodeIfPresent(String.self, forKey: .focusShortcutOnName) ?? ""
        focusShortcutOffName = try c.decodeIfPresent(String.self, forKey: .focusShortcutOffName) ?? ""
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
    // Lien vers le chapitre DataStore (feature #6)
    var writingProjectId: UUID? = nil
    var writingChapterId: UUID? = nil
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
    /// Pierres tombales de suppression (uuidString → date de suppression), partagées entre les Mac
    /// pour que la fusion par union ne ressuscite pas les éléments supprimés.
    var deletedIDs: [String: Date] = [:]

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

        // Réglages par défaut datés de 1970 : fusionnés avec un fichier existant (autre Mac,
        // iCloud pas encore synchronisé), ce sont les vrais réglages qui l'emportent.
        var defaultSettings = PomodoroAppSettings.default
        defaultSettings.updatedAt = Date(timeIntervalSince1970: 0)

        return PomodoroAppData(
            schemaVersion: 1,
            settings: defaultSettings,
            globalStatistics: .empty,
            goals: defaultGoals,
            categories: PomodoroActivityCategory.default(),
            projects: [],
            sessions: [],
            workBlocks: [],
            updatedAt: now,
            deletedIDs: [:]
        )
    }
}

extension PomodoroAppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        settings = try c.decode(PomodoroAppSettings.self, forKey: .settings)
        globalStatistics = try c.decodeIfPresent(PomodoroGlobalStatisticsSnapshot.self, forKey: .globalStatistics) ?? .empty
        goals = try c.decodeIfPresent([PomodoroGoalDefinition].self, forKey: .goals) ?? []
        categories = try c.decodeIfPresent([PomodoroActivityCategory].self, forKey: .categories) ?? []
        projects = try c.decodeIfPresent([PomodoroProjectRecord].self, forKey: .projects) ?? []
        sessions = try c.decodeIfPresent([PomodoroSessionRecord].self, forKey: .sessions) ?? []
        workBlocks = try c.decodeIfPresent([PomodoroWorkBlockRecord].self, forKey: .workBlocks) ?? []
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        deletedIDs = try c.decodeIfPresent([String: Date].self, forKey: .deletedIDs) ?? [:]
    }
}

extension PomodoroWorkBlockRecord {
    /// Identifiant déterministe d'un bloc, dérivé de sa première session : reconstruire les blocs
    /// sur deux Mac produit les mêmes IDs (pas de doublons à la fusion). Les octets sont altérés pour
    /// ne jamais coïncider avec l'ID de la session (les pierres tombales sont communes à toutes les collections).
    static func deterministicID(firstSessionID: UUID) -> UUID {
        var bytes = firstSessionID.uuid
        bytes.0 ^= 0xB1
        bytes.1 ^= 0x0C
        bytes.2 ^= 0x4B
        bytes.3 ^= 0x1D
        return UUID(uuid: bytes)
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
