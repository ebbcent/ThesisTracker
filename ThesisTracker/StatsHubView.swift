import SwiftUI

// MARK: - 5.15 Statistiques : une seule entrée, des onglets
//
// Avant : Graphiques, Activité, Calendrier et Historique occupaient chacun une
// ligne de la barre latérale, et « Statistiques » n'y figurait pas. Désormais une
// seule entrée « Statistiques » ; les onglets mènent aux vues existantes,
// inchangées. Les raccourcis ⌘5 à ⌘8 ouvrent directement l'onglet voulu.

extension NavItem {
    /// Vues regroupées sous « Statistiques », dans l'ordre des onglets.
    static let statsGroup: [NavItem] = [.analytics, .charts, .activity, .calendar, .history]

    var statsTabTitle: String {
        switch self {
        case .analytics: return "Vue d'ensemble"
        case .charts:    return "Graphiques"
        case .activity:  return "Activité"
        case .calendar:  return "Calendrier"
        case .history:   return "Historique"
        default:         return rawValue
        }
    }
}

struct StatsHubView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool
    @Binding var selectedNav: NavItem

    var body: some View {
        VStack(spacing: 0) {
            Picker("Statistiques", selection: Binding(
                get: { NavItem.statsGroup.contains(selectedNav) ? selectedNav : .analytics },
                set: { new in withoutAnimation { selectedNav = new } }
            )) {
                ForEach(NavItem.statsGroup) { item in
                    Text(item.statsTabTitle).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityLabel("Onglets des statistiques")

            Group {
                switch selectedNav {
                case .charts:
                    ChartView(store: store, showSidebar: $showSidebar)
                case .activity:
                    UnifiedActivityView(store: store, showSidebar: $showSidebar, initialMode: .heatmap)
                case .calendar:
                    UnifiedActivityView(store: store, showSidebar: $showSidebar, initialMode: .calendar)
                        .id("calendar")   // mode initial différent : vue recréée
                case .history:
                    HistoryListView(store: store, showSidebar: $showSidebar)
                default:
                    StatsAnalyticsView(store: store, showSidebar: $showSidebar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
