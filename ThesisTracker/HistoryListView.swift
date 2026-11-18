import SwiftUI

struct HistoryListView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var selectedProjectId: UUID? = nil
    @State private var selectedChapterId: UUID? = nil
    @State private var entryToDelete: DailyEntry? = nil

    private var selectedProject: Project? {
        let id = selectedProjectId ?? store.data.activeProjectId
        return store.data.projects.first(where: { $0.id == id }) ?? store.data.projects.first
    }

    private var selectedChapter: Chapter? {
        guard let project = selectedProject else { return nil }
        let id = selectedChapterId ?? project.activeChapterId
        return project.chapters.first(where: { $0.id == id }) ?? project.chapters.first
    }

    private var sortedEntries: [DailyEntry] {
        selectedChapter?.entries.sorted { $0.date > $1.date } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView

                if store.data.projects.isEmpty {
                    noProjectState
                } else {
                    projectPicker
                    if let project = selectedProject {
                        if project.chapters.isEmpty {
                            noChapterState
                        } else {
                            chapterPicker(project: project)
                            if sortedEntries.isEmpty {
                                emptyState
                            } else {
                                entriesList
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            if selectedProjectId == nil {
                selectedProjectId = store.data.activeProjectId ?? store.data.projects.first?.id
            }
        }
        .onChange(of: selectedProjectId) { _, _ in
            selectedChapterId = nil
        }
        .alert("Supprimer cette entrée ?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Supprimer", role: .destructive) {
                if let entry = entryToDelete,
                   let chapter = selectedChapter,
                   let project = selectedProject {
                    withAppAnimation { store.deleteEntry(for: chapter.id, in: project.id, date: entry.date) }
                    entryToDelete = nil
                }
            }
            Button("Annuler", role: .cancel) { entryToDelete = nil }
        } message: {
            if let entry = entryToDelete {
                Text("L'entrée du \(formattedDate(entry.date)) sera supprimée définitivement.")
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                            .fill(showSidebar ? Color.accent.opacity(0.10) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(
                                showSidebar ? Color.accent.opacity(0.30) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 2) {
                Text("Historique")
                    .font(TypeScale.pageTitle)
                    .foregroundColor(.primary)
                if let project = selectedProject, let chapter = selectedChapter {
                    Text("\(project.name) · \(chapter.name)")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                }
            }

            Spacer()
        }
    }

    // MARK: - Project picker

    private var projectPicker: some View {
        GlassCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.data.projects) { project in
                        let isSelected = selectedProjectId == project.id
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.15)) {
                                selectedProjectId = project.id
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.fill").font(.system(size: AppLook.fs(10)))
                                Text(project.name)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(isSelected ? Color.accent : Color.glassFill)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.cardBorder, lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Chapter picker

    private func chapterPicker(project: Project) -> some View {
        GlassCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(project.chapters) { chapter in
                        let isSelected = selectedChapterId == chapter.id
                            || (selectedChapterId == nil && project.chapters.first?.id == chapter.id)
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.15)) {
                                selectedChapterId = chapter.id
                            }
                        } label: {
                            Text(chapter.name)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundColor(isSelected ? .white : .secondary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(isSelected ? Color.accentWarm : Color.glassFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.accentWarm : Color.cardBorder, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Entries list

    private var entriesList: some View {
        VStack(spacing: 8) {
            SectionHeader("Entrées (\(sortedEntries.count))")
            ForEach(sortedEntries) { entry in
                HistoryRow(
                    entry: entry,
                    chapter: selectedChapter,
                    onDelete: { entryToDelete = entry },
                    onToggleImport: { store.setEntryImport(!entry.isImport, entryId: entry.id) }
                )
            }
        }
    }

    // MARK: - Empty states (#23)

    private var emptyState: some View {
        GlassCard {   // 5.15 : état vide commun
            EmptyStateView(icon: "tray", title: "Aucune entrée pour ce chapitre",
                           message: "Saisie du tableau de bord ou via ⌃⌥N.")
        }
    }

    private var noChapterState: some View {
        GlassCard {   // 5.15 : état vide commun
            EmptyStateView(icon: "book.closed", title: "Aucun chapitre dans ce projet",
                           message: "Ajoute des chapitres depuis la barre latérale.", iconColor: .accent,
                           action: { withAppAnimation(Motion.quick) { showSidebar = true } }, actionLabel: "Ouvrir la barre latérale")
        }
    }

    private var noProjectState: some View {
        GlassCard {   // 5.15 : état vide commun
            EmptyStateView(icon: "folder.badge.plus", title: "Aucun projet créé",
                           message: "Crée ton premier projet depuis la barre latérale.", iconColor: .accent,
                           action: { withAppAnimation(Motion.quick) { showSidebar = true } }, actionLabel: "Créer un projet")
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "d MMMM yyyy"
        return out.string(from: date)
    }
}
