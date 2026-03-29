import Foundation
import SwiftUI

// MARK: - Note tags pour les chapitres

struct NoteTag: Codable, Identifiable {
    var id: UUID = UUID()
    var kind: NoteTagKind
    var text: String

    enum NoteTagKind: String, Codable, CaseIterable {
        case todo     = "TODO"
        case idea     = "IDÉE"
        case blocker  = "BLOCAGE"
        case ref      = "RÉF."

        var icon: String {
            switch self {
            case .todo:    return "checkmark.square"
            case .idea:    return "lightbulb"
            case .blocker: return "exclamationmark.triangle.fill"
            case .ref:     return "book.closed"
            }
        }

        var color: Color {
            switch self {
            case .todo:    return .accent
            case .idea:    return Color(red: 0.961, green: 0.620, blue: 0.043)
            case .blocker: return Color(red: 0.929, green: 0.329, blue: 0.329)
            case .ref:     return Color(red: 0.506, green: 0.353, blue: 0.937)
            }
        }
    }
}

// MARK: - Tag couleur (style macOS)

enum ProjectTag: String, Codable, CaseIterable {
    case red, orange, yellow, green, blue, purple, gray

    var label: String {
        switch self {
        case .red:    return "Rouge"
        case .orange: return "Orange"
        case .yellow: return "Jaune"
        case .green:  return "Vert"
        case .blue:   return "Bleu"
        case .purple: return "Violet"
        case .gray:   return "Gris"
        }
    }
}

// MARK: - Dossier de projets

struct ProjectFolder: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var projectIds: [UUID] = []
    var isExpanded: Bool = true
}

// MARK: - Groupe de chapitres (dans un projet)

struct ChapterFolder: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var isExpanded: Bool = true
}

// MARK: - Données quotidiennes

struct DailyEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String        // "yyyy-MM-dd"
    var totalCount: Int
    var note: String? = nil
    var savedAtHour: Int? = nil   // 0–23, recorded when the entry is saved
}

// MARK: - Statut de chapitre (V3.2)

enum ChapterStatus: String, Codable, CaseIterable {
    case plan       = "plan"
    case redaction  = "redaction"
    case revision   = "revision"
    case termine    = "termine"

    var label: String {
        switch self {
        case .plan:      return "Plan"
        case .redaction: return "Rédaction"
        case .revision:  return "Révision"
        case .termine:   return "Terminé"
        }
    }

    var icon: String {
        switch self {
        case .plan:      return "list.bullet.rectangle"
        case .redaction: return "pencil.line"
        case .revision:  return "eye"
        case .termine:   return "checkmark.seal.fill"
        }
    }

    var color: String {
        switch self {
        case .plan:      return "#8E8E93"
        case .redaction: return "#FF9500"
        case .revision:  return "#007AFF"
        case .termine:   return "#34C759"
        }
    }
}

// MARK: - Chapitre

struct Chapter: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var goal: Int
    var entries: [DailyEntry] = []
    var tag: ProjectTag? = nil
    var isCompleted: Bool = false
    var deadline: String? = nil
    var notes: String? = nil
    var noteTags: [NoteTag] = []
    var chapterFolderId: UUID? = nil
    var status: ChapterStatus? = nil   // V3.2 — nil = non défini
    var zoteroKeys: [String] = []      // Clés d'items Zotero associés (8 car. alphanumériques)

    func entryForDate(_ date: String) -> DailyEntry? {
        entries.first(where: { $0.date == date })
    }

    func previousTotal(before date: String) -> Int {
        let sorted = entries
            .filter { $0.date < date }
            .sorted { $0.date > $1.date }
        return sorted.first?.totalCount ?? 0
    }

    func increment(for date: String) -> Int {
        guard let entry = entryForDate(date) else { return 0 }
        let prev = previousTotal(before: date)
        return max(0, entry.totalCount - prev)
    }
}

// MARK: - Item Zotero

struct ZoteroItem: Identifiable {
    let id: String       // itemKey (8 car. alphanumériques)
    let title: String
    let authors: String
    let year: String
    let itemType: String
}

// MARK: - Projet

struct Project: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var activeChapterId: UUID? = nil
    var chapters: [Chapter] = []
    var tag: ProjectTag? = nil
    var folderId: UUID? = nil   // nil = sans dossier
    var chapterFolders: [ChapterFolder] = []
}

// MARK: - Dates épinglées (Calendrier)

struct PinnedDate: Codable, Identifiable {
    var id: UUID = UUID()
    var date: String       // "yyyy-MM-dd"
    var label: String = ""
}

// MARK: - Défi hebdomadaire

struct WeeklyChallenge: Codable, Identifiable {
    var id: UUID = UUID()
    var weekKey: String      // "yyyy-Www" e.g. "2026-W12"
    var kind: ChallengeKind
    var target: Int
    var completedAt: String? = nil  // date string when completed

    enum ChallengeKind: String, Codable {
        case words          // write N words/chars this week
        case streak         // maintain streak of N days
        case sessions       // complete N Pomodoro sessions
        case daysWritten    // write on N distinct days this week

        var displayName: String {
            switch self {
            case .words:       return "Mots écrits"
            case .streak:      return "Série d'écriture"
            case .sessions:    return "Sessions Pomodoro"
            case .daysWritten: return "Jours d'écriture"
            }
        }

        var icon: String {
            switch self {
            case .words:       return "text.cursor"
            case .streak:      return "flame.fill"
            case .sessions:    return "timer"
            case .daysWritten: return "calendar"
            }
        }

        var unit: String {
            switch self {
            case .words:       return "car."
            case .streak:      return "jours"
            case .sessions:    return "sessions"
            case .daysWritten: return "jours"
            }
        }
    }

    var isCompleted: Bool { completedAt != nil }
}

// MARK: - Données globales

struct AppData: Codable {
    var dailyGoal: Int = 500
    var weeklyGoal: Int = 3000
    var monthlyGoal: Int = 15000
    var projects: [Project] = []
    var activeProjectId: UUID? = nil
    var folders: [ProjectFolder] = []
    var sortProjectsAlphabetically: Bool = false
    var sortChaptersAlphabetically: Bool = false
    var useWordCount: Bool = false
    var pinnedDates: [PinnedDate] = []
    var weeklyChallenges: [WeeklyChallenge] = []

    // Legacy migration fields (old format had chapters at top level)
    var legacyChapters: [Chapter]?
    var legacyActiveChapterId: UUID?

    enum CodingKeys: String, CodingKey {
        case dailyGoal, weeklyGoal, monthlyGoal, projects, activeProjectId
        case folders, sortProjectsAlphabetically, sortChaptersAlphabetically, useWordCount
        case pinnedDates, weeklyChallenges
        case legacyChapters = "chapters"
        case legacyActiveChapterId = "activeChapterId"
    }
}
