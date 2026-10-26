import Foundation

// MARK: - Calendrier d'écriture (5.9)
//
// Réglages synchronisés dans data.json (`AppData.writingSchedule`), donc
// partagés entre les deux Mac et fusionnés clé par clé par `DataSync`.
// Chaque champ absent (nil) redonne le comportement de la 5.8.

enum StreakRule: String, Codable, CaseIterable {
    case consecutive   // série classique : chaque jour compte
    case scheduled     // jours non prévus, repos et pauses neutres

    var label: String {
        switch self {
        case .consecutive: return "Jours consécutifs"
        case .scheduled:   return "Selon mon calendrier"
        }
    }
}

/// Période pendant laquelle la série est gelée. `end == nil` : pause en cours.
struct StreakPause: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var start: String        // "yyyy-MM-dd"
    var end: String? = nil   // "yyyy-MM-dd", inclus

    func contains(_ date: String) -> Bool {
        start <= date && (end.map { date <= $0 } ?? true)
    }
}

struct WritingSchedule: Codable, Equatable {
    var workWeekdays: [Int]? = nil          // 1 = dim … 7 = sam ; nil ou vide = tous les jours
    var countDeadlineDay: Bool? = nil       // nil = le jour de l'échéance compte
    var streakRule: StreakRule? = nil       // nil = .consecutive
    var graceDay: Bool? = nil               // un jour prévu manqué toléré s'il est suivi d'un jour tenu
    var streakPauses: [StreakPause]? = nil
    var charsPerPage: Int? = nil            // équivalent en pages (nil = pas d'affichage)
    var weekdayGoals: [String: Int]? = nil  // objectifs par jour de semaine (clé = weekday)
    var deadlineBufferDays: Int? = nil      // marge de sécurité sur les échéances

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workWeekdays       = (try? c.decodeIfPresent(LossyArray<Int>.self, forKey: .workWeekdays))?.elements
        countDeadlineDay   = try? c.decodeIfPresent(Bool.self, forKey: .countDeadlineDay)
        streakRule         = try? c.decodeIfPresent(StreakRule.self, forKey: .streakRule)
        graceDay           = try? c.decodeIfPresent(Bool.self, forKey: .graceDay)
        streakPauses       = (try? c.decodeIfPresent(LossyArray<StreakPause>.self, forKey: .streakPauses))?.elements
        charsPerPage       = try? c.decodeIfPresent(Int.self, forKey: .charsPerPage)
        weekdayGoals       = try? c.decodeIfPresent([String: Int].self, forKey: .weekdayGoals)
        deadlineBufferDays = try? c.decodeIfPresent(Int.self, forKey: .deadlineBufferDays)
    }
}
