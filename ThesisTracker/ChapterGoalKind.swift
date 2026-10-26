import Foundation

// MARK: - Type d'objectif de chapitre et périmètre du total (5.10)

/// Plancher (comportement d'origine), plafond, ou cible approximative (±10 %).
enum ChapterGoalKind: String, Codable, CaseIterable {
    case atLeast
    case atMost
    case around

    var label: String {
        switch self {
        case .atLeast: return "Au moins"
        case .atMost:  return "Au plus"
        case .around:  return "Environ"
        }
    }

    var help: String {
        switch self {
        case .atLeast: return "Objectif minimum : on peut le dépasser"
        case .atMost:  return "Plafond à ne pas dépasser (consigne de longueur)"
        case .around:  return "Cible à ±10 %"
        }
    }
}

enum ChapterGoalState: Equatable {
    case noGoal
    case inProgress
    case reached        // plancher atteint, ou dans la fourchette ±10 %
    case overCeiling    // au-delà du plafond, ou au-dessus de la fourchette
}

extension Chapter {
    static let aroundTolerance = 0.10

    var effectiveGoalKind: ChapterGoalKind { goalKind ?? .atLeast }

    /// Compte dans le total, le reste à écrire et la projection de la thèse.
    var countsInThesisTotal: Bool { !(excludedFromThesisTotal ?? false) }

    func goalState(total: Int) -> ChapterGoalState {
        guard goal > 0 else { return .noGoal }
        let ratio = Double(total) / Double(goal)
        switch effectiveGoalKind {
        case .atLeast:
            return total >= goal ? .reached : .inProgress
        case .atMost:
            return total > goal ? .overCeiling : .inProgress
        case .around:
            if ratio > 1 + Chapter.aroundTolerance { return .overCeiling }
            if ratio >= 1 - Chapter.aroundTolerance { return .reached }
            return .inProgress
        }
    }

    /// Part au-delà de l'objectif (0 si en dessous).
    func overflow(total: Int) -> Int {
        guard goal > 0 else { return 0 }
        return max(0, total - goal)
    }
}
