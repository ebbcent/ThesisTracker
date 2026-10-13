import SwiftUI

// MARK: - Sections de navigation (refonte 5.4)
//
// Les 15 vues (`NavItem`) sont regroupées en 5 sections dans la barre
// latérale ; à l'intérieur d'une section, une barre d'onglets donne accès à
// ses vues. Aucune vue n'est supprimée : `NavItem` reste la source de vérité
// (palette de commandes, notifications, raccourcis existants).

enum SidebarSection: String, CaseIterable, Identifiable {
    case today        = "Aujourd'hui"
    case thesis       = "Thèse"
    case analyses     = "Analyses"
    case timer        = "Minuteur"
    case achievements = "Accomplissements"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today:        return "sun.max"
        case .thesis:       return "books.vertical"
        case .analyses:     return "chart.xyaxis.line"
        case .timer:        return "timer"
        case .achievements: return "medal"
        }
    }

    /// Vues de la section, dans l'ordre des onglets ; la première est l'onglet par défaut.
    var items: [NavItem] {
        switch self {
        case .today:        return [.today, .dashboard, .widgets]
        case .thesis:       return [.overview, .deadlines, .kanban, .tableOfContents]
        case .analyses:     return [.charts, .analytics, .activity, .calendar, .history, .search]
        case .timer:        return [.timer]
        case .achievements: return [.achievements]
        }
    }

    /// ⌘1 … ⌘5
    var keyEquivalent: KeyEquivalent {
        let index = SidebarSection.allCases.firstIndex(of: self) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }

    var shortcutLabel: String {
        "⌘\((SidebarSection.allCases.firstIndex(of: self) ?? 0) + 1)"
    }
}

extension NavItem {
    var section: SidebarSection {
        SidebarSection.allCases.first { $0.items.contains(self) } ?? .today
    }

    /// Libellé court dans la barre d'onglets d'une section.
    var tabTitle: String {
        switch self {
        case .dashboard:       return "Tableau de bord complet"
        case .widgets:         return "Widgets"
        case .analytics:       return "Statistiques"
        default:               return rawValue
        }
    }
}

/// Barre d'onglets en haut d'une section qui contient plusieurs vues.
struct SectionTabBar: View {
    let section: SidebarSection
    @Binding var selectedNav: NavItem

    var body: some View {
        HStack {
            Picker(section.rawValue, selection: $selectedNav) {
                ForEach(section.items) { item in
                    Text(item.tabTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Vues de la section \(section.rawValue)")
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}
