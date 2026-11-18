import SwiftUI

// MARK: - 5.29 Barre latérale de l'apparence Tuiles : rail d'icônes + chapitre épinglé
//
// Format validé par Clem sur maquette (mélange « chapitre épinglé » et « rail et liste ») :
// - à gauche, un rail d'icônes pour les pages (toujours visible, même barre latérale masquée) ;
// - dans le panneau, le chapitre actif épinglé en haut, puis les projets en lignes simples.
// Les affichages d'origine (VA, VD) gardent la barre latérale telle qu'elle était.

/// Rail de navigation : une icône par page, groupées comme la liste d'origine.
struct TilesNavRail: View {
    @Binding var selectedNav: NavItem

    private static let groups: [[NavItem]] = [
        [.dashboard, .professor, .overview, .tableOfContents, .deadlines, .kanban],
        [.analytics, .recaps, .widgets],
        [.timer, .search, .achievements]
    ]

    private func isSelected(_ item: NavItem) -> Bool {
        selectedNav == item || (item == .analytics && NavItem.statsGroup.contains(selectedNav))
    }

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    Rectangle().fill(Color.cardBorder).frame(width: 22, height: 1).padding(.vertical, 5)
                }
                ForEach(group) { item in
                    railButton(item)
                }
            }
            Spacer(minLength: 8)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.labelMuted)
                    .frame(width: 38, height: 38)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("Réglages (⌘,)")
            .accessibilityLabel("Réglages")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 7)
        .frame(width: 54)
        .frame(maxHeight: .infinity)
        .appGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), fallback: .sidebarBg)
    }

    private func railButton(_ item: NavItem) -> some View {
        let selected = isSelected(item)
        return Button {
            if item == .analytics && NavItem.statsGroup.contains(selectedNav) { return }   // déjà dans les statistiques
            withoutAnimation { selectedNav = item }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(selected ? AppLook.onAccent : .labelMuted)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Color.accentWarm : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(item.shortcutHint.map { "\(item.rawValue) (\($0))" } ?? item.rawValue)
        .accessibilityLabel(item.rawValue)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Chapitre actif, épinglé en haut du panneau : où j'en suis, sans chercher dans l'arbre.
struct TilesPinnedChapterCard: View {
    @ObservedObject var store: DataStore
    let onHistory: (Chapter, UUID) -> Void

    @State private var showStatusPicker = false

    private func num(_ value: Int) -> String {
        DataStore.formatNumber(store.data.useWordCount ? value / 5 : value)
    }

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        if let project = store.activeProject, let chapter = store.activeChapter {
            card(project: project, chapter: chapter)
        }
    }

    private func card(project: Project, chapter: Chapter) -> some View {
        let total = store.latestTotal(for: chapter.id, in: project.id)
        let ratio = chapter.goal > 0 ? min(1, Double(total) / Double(chapter.goal)) : 0
        let status = chapter.isCompleted ? "terminé" : (chapter.status?.label.lowercased() ?? "sans statut")
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Chapitre en cours · \(status)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentWarm)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if chapter.goal > 0 {
                    Text("\(Int((ratio * 100).rounded())) %")
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundColor(.accentWarm)
                        .fixedSize()
                }
            }
            Text(chapter.name)
                .font(.system(size: 16, design: .serif))
                .foregroundColor(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .help(chapter.name)
            if chapter.goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.trackBg)
                        Capsule().fill(Color.accentWarm).frame(width: ratio > 0 ? max(6, geo.size.width * ratio) : 0)
                    }
                }
                .frame(height: 6)
                .accessibilityElement()
                .accessibilityLabel("Progression du chapitre")
                .accessibilityValue("\(Int((ratio * 100).rounded())) %")
            }
            HStack(spacing: 8) {
                Text(chapter.goal > 0 ? "\(num(total)) / \(num(chapter.goal))" : num(total))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                if let deadline = deadlineText(chapter) {
                    Text(deadline)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.semRed)
                        .fixedSize()
                }
            }
            HStack(spacing: 8) {
                cardButton("Historique") { onHistory(chapter, project.id) }
                cardButton("Statut") { showStatusPicker = true }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.cardBg))
        .sheet(isPresented: $showStatusPicker) {
            ChapterStatusPickerView(store: store, chapterId: chapter.id, projectId: project.id, isPresented: $showStatusPicker)
        }
    }

    private func cardButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func deadlineText(_ chapter: Chapter) -> String? {
        guard !chapter.isCompleted, let date = chapter.deadline.flatMap(DataStore.parseDate) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        let day = Self.shortDate.string(from: date)
        if days > 0 { return "\(day) · \(days) j" }
        if days == 0 { return "\(day) · aujourd'hui" }
        return "\(day) · dépassée"
    }
}
