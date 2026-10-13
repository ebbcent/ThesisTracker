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

/// Barre d'onglets en haut d'une section qui contient plusieurs vues
/// (style de l'app : pastilles, accent ambre).
struct SectionTabBar: View {
    let section: SidebarSection
    @Binding var selectedNav: NavItem

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(section.items) { item in
                    SectionTab(item: item, isSelected: selectedNav == item) {
                        withAnimation(.easeInOut(duration: 0.12)) { selectedNav = item }
                    }
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.cardBorder, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Vues de la section \(section.rawValue)")
    }
}

private struct SectionTab: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .medium))
                Text(item.tabTitle)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .accentWarm : (isHovering ? .primary : .labelMuted))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentWarm.opacity(0.12) : (isHovering ? Color.glassFill : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Color.accentWarm.opacity(0.30) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(item.tabTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
