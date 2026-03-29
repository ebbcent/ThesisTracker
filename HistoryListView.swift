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
                    withAnimation { store.deleteEntry(for: chapter.id, in: project.id, date: entry.date) }
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(showSidebar ? Color.accent.opacity(0.10) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                showSidebar ? Color.accent.opacity(0.30) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Historique")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedProjectId = project.id
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "folder.fill").font(.system(size: 10))
                                Text(project.name)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            }
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(isSelected ? Color.accent : Color.glassFill)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedChapterId = chapter.id
                            }
                        } label: {
                            Text(chapter.name)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : .secondary)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(isSelected ? Color.accentWarm : Color.glassFill)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(isSelected ? Color.accentWarm : Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
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
                    onDelete: { entryToDelete = entry }
                )
            }
        }
    }

    // MARK: - Empty states

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucune entrée pour ce chapitre")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private var noChapterState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "book.closed")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucun chapitre dans ce projet")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    private var noProjectState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucun projet créé")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
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
