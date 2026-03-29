import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: DataStore
    @Binding var selectedNav: NavItem
    @Binding var showSidebar: Bool
    @EnvironmentObject private var pomodoroController: PomodoroAppController

    @State private var showAddProject = false
    @State private var editingProject: Project? = nil
    @State private var expandedProjects: Set<UUID> = []
    @State private var addChapterForProject: Project? = nil
    @State private var editingChapter: ChapterEditItem? = nil
    @State private var historyItem: ChapterEditItem? = nil
    @State private var notesItem: ChapterEditItem? = nil
    @State private var showImport = false
    @State private var showExport = false
    @State private var showAddFolder = false
    @State private var editingFolderName: String = ""
    @State private var renamingFolder: ProjectFolder? = nil
    @State private var dropTargetProjectId: UUID? = nil

    // MARK: - Sorted lists

    private var sortedProjects: [Project] { store.sortedProjects(store.data.projects) }
    private var folderProjectIds: Set<UUID> { Set(store.data.folders.flatMap { $0.projectIds }) }
    private var ungroupedProjects: [Project] { sortedProjects.filter { !folderProjectIds.contains($0.id) } }
    private func projects(in folder: ProjectFolder) -> [Project] {
        store.sortedProjects(folder.projectIds.compactMap { id in
            store.data.projects.first(where: { $0.id == id })
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Navigation section
                    sectionLabel("Navigation", icon: "square.grid.2x2")
                    navSection

                    sectionDivider

                    // Projets section
                    projectSection
                }
                .padding(.bottom, 12)
            }
            sidebarProjectProgress
            Divider()
            sidebarFooter
        }
        .background(Color.sidebarBg)
        .onAppear {
            if let id = store.data.activeProjectId { expandedProjects.insert(id) }
        }
        .sheet(isPresented: $showAddProject) { ProjectFormView(store: store, project: nil) }
        .sheet(item: $editingProject) { ProjectFormView(store: store, project: $0) }
        .sheet(item: $addChapterForProject) { ChapterFormView(store: store, chapter: nil, projectId: $0.id) }
        .sheet(item: $editingChapter) { ChapterFormView(store: store, chapter: $0.chapter, projectId: $0.projectId) }
        .sheet(item: $historyItem) { HistoryView(store: store, chapter: $0.chapter, projectId: $0.projectId) }
        .sheet(item: $notesItem) { ChapterNotesSheet(store: store, chapter: $0.chapter, projectId: $0.projectId) }
        .sheet(isPresented: $showImport) { ImportView(store: store) }
        .sheet(isPresented: $showExport) { ExportView(store: store) }
        .sheet(isPresented: $showAddFolder) {
            FolderFormView(name: $editingFolderName, title: "Nouveau dossier",
                onSave: { store.addFolder(name: editingFolderName); editingFolderName = ""; showAddFolder = false },
                onCancel: { editingFolderName = ""; showAddFolder = false })
        }
        .sheet(item: $renamingFolder) { folder in
            FolderFormView(name: $editingFolderName, title: "Renommer le dossier",
                onSave: {
                    var updated = folder; updated.name = editingFolderName
                    store.updateFolder(updated); editingFolderName = ""; renamingFolder = nil
                },
                onCancel: { editingFolderName = ""; renamingFolder = nil })
            .onAppear { editingFolderName = folder.name }
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.book.closed.fill")
                .foregroundColor(.accent)
                .font(.system(size: 13, weight: .semibold))
            Text("Writing Process")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Spacer()
            if store.currentStreak > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(store.currentStreak)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(Color(red: 0.961, green: 0.455, blue: 0.114))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(red: 0.961, green: 0.455, blue: 0.114).opacity(0.12))
                        .overlay(
                            Capsule().stroke(Color(red: 0.961, green: 0.455, blue: 0.114).opacity(0.20), lineWidth: 1)
                        )
                )
            }
            if store.showSaveIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accentGreen.opacity(0.85))
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            if store.isUsingICloud {
                Image(systemName: "icloud.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.accent.opacity(0.7))
                    .help("Synchronisé via iCloud")
            }
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { showSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.labelMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.glassFill)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .animation(.easeInOut(duration: 0.3), value: store.showSaveIndicator)
    }

    // MARK: - Section helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.labelMuted)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.0)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var sectionDivider: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
    }

    // MARK: - Navigation

    private var navSection: some View {
        VStack(spacing: 1) {
            ForEach(NavItem.allCases.filter { $0 != .history }) { item in
                NavItemRow(item: item, isSelected: selectedNav == item) {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedNav = item }
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Projects section

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
                Text("PROJETS")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.labelMuted).kerning(1.0)
                Spacer()
                Button {
                    withAnimation { store.data.sortProjectsAlphabetically.toggle(); store.save() }
                } label: {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(store.data.sortProjectsAlphabetically ? .accent : .labelMuted)
                        .frame(width: 22, height: 22)
                        .background(store.data.sortProjectsAlphabetically ? Color.accent.opacity(0.10) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(store.data.sortProjectsAlphabetically ? "Ordre alphabétique (actif)" : "Trier A → Z")
                Button { editingFolderName = ""; showAddFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.labelMuted)
                        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).help("Nouveau dossier")
                Button { showAddProject = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold)).foregroundColor(.accent)
                        .frame(width: 22, height: 22)
                        .background(Color.accent.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).help("Nouveau projet")
            }
            .padding(.horizontal, 18).padding(.bottom, 8)

            VStack(spacing: 4) {
                if store.data.projects.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder").font(.system(size: 26)).foregroundColor(.labelMuted)
                        Text("Aucun projet").font(.system(size: 12)).foregroundColor(.labelMuted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    // Dossiers
                    ForEach(store.data.folders) { folder in
                        FolderSidebarRow(
                            folder: folder, projects: projects(in: folder), store: store,
                            expandedProjects: $expandedProjects,
                            onRenameFolder: { editingFolderName = folder.name; renamingFolder = folder },
                            onDeleteFolder: { store.deleteFolder(id: folder.id, keepProjects: true) },
                            onEditProject: { editingProject = $0 },
                            onAddChapter: { addChapterForProject = $0 },
                            onSelectChapter: selectChapter,
                            onChapterHistory: { ch, pid in historyItem = ChapterEditItem(chapter: ch, projectId: pid) },
                            onEditChapter: { ch, pid in editingChapter = ChapterEditItem(chapter: ch, projectId: pid) },
                            onNotesChapter: { ch, pid in notesItem = ChapterEditItem(chapter: ch, projectId: pid) }
                        )
                    }

                    // Projets sans dossier
                    if !ungroupedProjects.isEmpty {
                        if !store.data.folders.isEmpty {
                            HStack {
                                Text("SANS DOSSIER")
                                    .font(.system(size: 9, weight: .bold)).foregroundColor(.labelMuted.opacity(0.6)).kerning(1.0)
                                Spacer()
                            }
                            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
                        }

                        ForEach(ungroupedProjects) { project in
                            ProjectSidebarRow(
                                store: store, project: project,
                                isExpanded: expandedProjects.contains(project.id),
                                dropTargetProjectId: $dropTargetProjectId,
                                onToggleExpand: { toggleExpand(project.id) },
                                onEdit: { editingProject = project },
                                onAddChapter: { addChapterForProject = project },
                                onSelectChapter: { selectChapter($0, in: project) },
                                onChapterHistory: { ch in historyItem = ChapterEditItem(chapter: ch, projectId: project.id) },
                                onEditChapter: { ch in editingChapter = ChapterEditItem(chapter: ch, projectId: project.id) },
                                onNotesChapter: { ch in notesItem = ChapterEditItem(chapter: ch, projectId: project.id) }
                            )
                        }

                        // Zone de drop « fin de liste » pour les projets
                        Color.clear.frame(height: 24)
                            .dropDestination(for: String.self) { items, _ in
                                guard let idStr = items.first, let id = UUID(uuidString: idStr) else { return false }
                                store.moveProjectToEnd(id)
                                return true
                            } isTargeted: { targeted in
                                withAnimation { dropTargetProjectId = targeted ? UUID() : nil }
                            }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Progression globale du projet

    @ViewBuilder
    private var sidebarProjectProgress: some View {
        if let project = store.activeProject {
            let totalGoal = project.chapters.reduce(0) { $0 + $1.goal }
            let totalWritten = project.chapters.reduce(0) { total, ch in
                total + (ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0)
            }
            if totalGoal > 0 {
                let ratio = min(1.0, Double(totalWritten) / Double(totalGoal))
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text(project.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(ratio >= 1.0 ? .accentGreen : .accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.cardBorder)
                                .frame(height: 3)
                            if ratio > 0 {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(ratio >= 1.0 ? Color.accentGreen : Color.accent)
                                    .frame(width: geo.size.width * CGFloat(ratio), height: 3)
                                    .animation(.spring(response: 0.6, dampingFraction: 0.85), value: ratio)
                            }
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    // MARK: - Footer

    private var sidebarFooter: some View {
        VStack(spacing: 6) {
            // Streak badges row
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 9))
                    .foregroundColor(store.currentStreak > 0 ? .accentWarm : .labelMuted)
                HStack(spacing: 4) {
                    ForEach(DataStore.badgeMilestones, id: \.self) { threshold in
                        let unlocked = store.longestStreak >= threshold
                        Circle()
                            .fill(unlocked ? badgeDotColor(threshold) : Color.labelMuted.opacity(0.18))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle().stroke(
                                    unlocked ? badgeDotColor(threshold).opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                            )
                            .help(badgeTooltip(threshold, unlocked: unlocked))
                    }
                }
                Spacer()
                if store.currentStreak > 0 {
                    Text("\(store.currentStreak) j")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.accentWarm)
                }
            }
            .padding(.horizontal, 12)

            // Mini Pomodoro session timeline
            let todaySessions = pomodoroController.timeline
            if !todaySessions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                        .foregroundColor(.labelMuted)
                    HStack(spacing: 3) {
                        ForEach(todaySessions.prefix(12)) { entry in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(sessionDotColor(for: entry))
                                .frame(width: 10, height: 10)
                                .help(entry.title)
                        }
                        if todaySessions.count > 12 {
                            Text("+\(todaySessions.count - 12)")
                                .font(.system(size: 9))
                                .foregroundColor(.labelMuted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                footerIconButton(systemImage: "square.and.arrow.down", color: .accentWarm, help: "Importer des donnees") {
                    showImport = true
                }
                footerIconButton(systemImage: "square.and.arrow.up", color: .accentGold, help: "Exporter des donnees") {
                    showExport = true
                }
                footerIconButton(systemImage: "plus", color: .accent, help: "Nouveau projet") {
                    showAddProject = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sessionDotColor(for entry: PomodoroTimelineEntry) -> Color {
        Color(hex: entry.colorHex)
    }

    private func badgeDotColor(_ threshold: Int) -> Color {
        switch threshold {
        case 3:   return .accent
        case 7:   return Color(red: 0.961, green: 0.620, blue: 0.043)
        case 14:  return Color(red: 0.961, green: 0.455, blue: 0.114)
        case 30:  return Color(red: 0.929, green: 0.329, blue: 0.329)
        case 60:  return Color(red: 0.749, green: 0.318, blue: 0.918)
        case 100: return .accentWarm
        default:  return .accent
        }
    }

    private func badgeTooltip(_ threshold: Int, unlocked: Bool) -> String {
        let names: [Int: String] = [3: "Étincelle", 7: "Régulier", 14: "Persévérant", 30: "Acharné", 60: "Légende", 100: "Immortel"]
        let name = names[threshold] ?? "\(threshold) jours"
        return unlocked ? "✓ \(name) — \(threshold) jours" : "\(name) — \(threshold) jours (verrouillé)"
    }

    // MARK: - Helpers

    private func toggleExpand(_ id: UUID) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expandedProjects.contains(id) { expandedProjects.remove(id) }
            else { expandedProjects.insert(id) }
        }
    }

    private func selectChapter(_ chapter: Chapter, in project: Project) {
        store.data.activeProjectId = project.id
        if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
            store.data.projects[idx].activeChapterId = chapter.id
        }
        store.save()
    }

    private func footerIconButton(systemImage: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Nav item row (avec hover)

private struct NavItemRow: View {
    let item: NavItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                // Left accent bar
                Capsule()
                    .fill(isSelected ? Color.accent : Color.clear)
                    .frame(width: 3, height: isSelected ? 20 : 0)
                    .padding(.leading, 2)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 18)
                        .foregroundColor(isSelected ? .accent : (isHovering ? .primary.opacity(0.8) : .labelMuted))
                    Text(item.rawValue)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : (isHovering ? .primary.opacity(0.8) : .secondary))
                    Spacer()
                }
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            isSelected
                                ? Color.accent.opacity(0.10)
                                : isHovering ? Color.glassFill : Color.clear
                        )
                )
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.10)) { isHovering = hovering }
        }
    }
}

// MARK: - Folder form sheet

struct FolderFormView: View {
    @Binding var name: String
    let title: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.primary)
                DarkFormField(label: "Nom du dossier", placeholder: "ex: Thèse, Articles…", text: $name, onSubmit: {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSave()
                })
                HStack(spacing: 12) {
                    Button("Annuler") { onCancel() }
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.plain).keyboardShortcut(.escape)
                    Spacer()
                    Button("Créer") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave()
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(!name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.accent : Color.cardBorder)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 380)
    }
}

// MARK: - ChapterEditItem

struct ChapterEditItem: Identifiable {
    let id = UUID()
    let chapter: Chapter
    let projectId: UUID
}

// MARK: - Folder sidebar row

struct FolderSidebarRow: View {
    let folder: ProjectFolder
    let projects: [Project]
    @ObservedObject var store: DataStore
    @Binding var expandedProjects: Set<UUID>
    let onRenameFolder: () -> Void
    let onDeleteFolder: () -> Void
    let onEditProject: (Project) -> Void
    let onAddChapter: (Project) -> Void
    let onSelectChapter: (Chapter, Project) -> Void
    let onChapterHistory: (Chapter, UUID) -> Void
    let onEditChapter: (Chapter, UUID) -> Void
    var onNotesChapter: ((Chapter, UUID) -> Void)? = nil

    @State private var dropTargetProjectId: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            HStack(spacing: 8) {
                Button { store.toggleFolderExpanded(folder.id) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 12)
                        Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 12)).foregroundColor(.accent.opacity(0.8))
                        Text(folder.name)
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                        Spacer()
                        Text("\(projects.count)").font(.system(size: 10, weight: .medium)).foregroundColor(.labelMuted)
                    }
                }
                .buttonStyle(.plain)
                Menu {
                    Button("Renommer") { onRenameFolder() }
                    Divider()
                    Button("Supprimer le dossier", role: .destructive) { onDeleteFolder() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07)))
                }
                .menuStyle(.borderlessButton).fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 7)

            if folder.isExpanded {
                VStack(spacing: 4) {
                    if projects.isEmpty {
                        Text("Aucun projet dans ce dossier")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                            .padding(.leading, 28).padding(.vertical, 6)
                    } else {
                        ForEach(projects) { project in
                            ProjectSidebarRow(
                                store: store, project: project,
                                isExpanded: expandedProjects.contains(project.id),
                                dropTargetProjectId: $dropTargetProjectId,
                                onToggleExpand: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if expandedProjects.contains(project.id) { expandedProjects.remove(project.id) }
                                        else { expandedProjects.insert(project.id) }
                                    }
                                },
                                onEdit: { onEditProject(project) },
                                onAddChapter: { onAddChapter(project) },
                                onSelectChapter: { onSelectChapter($0, project) },
                                onChapterHistory: { onChapterHistory($0, project.id) },
                                onEditChapter: { onEditChapter($0, project.id) },
                                onNotesChapter: onNotesChapter.map { cb in { ch in cb(ch, project.id) } }
                            )
                            .padding(.leading, 16)
                        }
                    }
                }
                .padding(.top, 2).padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accent.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
    }
}

// MARK: - Sparkline

private struct SparklineView: View {
    let values: [Int]  // 7 valeurs (du plus ancien au plus récent)

    private var maxVal: CGFloat { CGFloat(values.max() ?? 1) }
    private var hasData: Bool { values.contains(where: { $0 > 0 }) }

    var body: some View {
        if hasData {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let count = values.count
                let step = count > 1 ? w / CGFloat(count - 1) : w

                // Zone remplie sous la courbe
                Path { path in
                    for (i, val) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - (CGFloat(val) / maxVal) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    path.addLine(to: CGPoint(x: CGFloat(count - 1) * step, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(Color.accent.opacity(0.12))

                // Ligne principale
                Path { path in
                    for (i, val) in values.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - (CGFloat(val) / maxVal) * h
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.accent.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Point final (aujourd'hui)
                if let last = values.last, last > 0 {
                    let x = CGFloat(count - 1) * step
                    let y = h - (CGFloat(last) / maxVal) * h
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 3.5, height: 3.5)
                        .position(x: x, y: y)
                }
            }
            .frame(width: 38, height: 14)
        } else {
            Rectangle().fill(Color.clear).frame(width: 38, height: 14)
        }
    }
}

// MARK: - Project row

struct ProjectSidebarRow: View {
    @ObservedObject var store: DataStore
    let project: Project
    let isExpanded: Bool
    @Binding var dropTargetProjectId: UUID?
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onAddChapter: () -> Void
    let onSelectChapter: (Chapter) -> Void
    let onChapterHistory: (Chapter) -> Void
    let onEditChapter: (Chapter) -> Void
    var onNotesChapter: ((Chapter) -> Void)? = nil

    @State private var dropTargetChapterId: UUID? = nil
    @State private var showAddChapterFolder: Bool = false
    @State private var newChapterFolderName: String = ""

    private var isActive: Bool { store.data.activeProjectId == project.id }
    private var sortedChapters: [Chapter] { store.sortedChapters(project.chapters) }

    private var sparkValues: [Int] {
        let totals = store.dailyTotals(projectId: project.id)
        let cal = Calendar(identifier: .gregorian)
        return (0..<7).reversed().map { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return 0 }
            return totals[DataStore.dateString(from: date)] ?? 0
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Project row header
            HStack(spacing: 8) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 12)
                        if let tag = project.tag {
                            Circle().fill(tag.color).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        } else {
                            Image(systemName: isActive ? "books.vertical.fill" : "books.vertical")
                                .font(.system(size: 12))
                                .foregroundColor(isActive ? .accent : .labelMuted)
                        }
                        Text(project.name)
                            .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                            .foregroundColor(.primary).lineLimit(1)
                        SparklineView(values: sparkValues)
                            .opacity(0.75)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Button(action: onAddChapter) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundColor(.accent)
                            .frame(width: 20, height: 20).background(Color.accent.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("Renommer") { onEdit() }
                        Menu("Tag") {
                            ForEach(ProjectTag.allCases, id: \.self) { tag in
                                Button { store.setProjectTag(tag, for: project.id) } label: {
                                    Label {
                                        Text(tag.label)
                                    } icon: {
                                        Image(systemName: "circle.fill").foregroundColor(tag.color)
                                    }
                                }
                            }
                            if project.tag != nil {
                                Divider()
                                Button("Supprimer le tag") { store.setProjectTag(nil, for: project.id) }
                            }
                        }
                        if !store.data.folders.isEmpty {
                            Menu("Déplacer vers") {
                                if project.folderId != nil {
                                    Button("Sans dossier") { store.moveProject(project.id, toFolder: nil) }
                                    Divider()
                                }
                                ForEach(store.data.folders) { folder in
                                    Button(folder.name) { store.moveProject(project.id, toFolder: folder.id) }
                                        .disabled(project.folderId == folder.id)
                                }
                            }
                        }
                        Toggle(isOn: Binding(
                            get: { store.data.sortChaptersAlphabetically },
                            set: { store.data.sortChaptersAlphabetically = $0; store.save() }
                        )) { Label("Chapitres A → Z", systemImage: "textformat.abc") }
                        Button("Nouveau groupe de chapitres") {
                            newChapterFolderName = ""
                            showAddChapterFolder = true
                        }
                        Divider()
                        Button("Supprimer", role: .destructive) { store.deleteProject(id: project.id) }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(isActive ? Color.accent.opacity(0.06) : Color.clear))
            // Drag source pour le projet
            .draggable(project.id.uuidString) {
                HStack(spacing: 6) {
                    if let tag = project.tag { Circle().fill(tag.color).frame(width: 8, height: 8) }
                    Text(project.name).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.accent.opacity(0.85)).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            // Drop target pour réordonner les projets
            .dropDestination(for: String.self) { items, _ in
                guard let idStr = items.first, let srcId = UUID(uuidString: idStr),
                      srcId != project.id else { return false }
                store.moveProjectById(srcId, before: project.id)
                dropTargetProjectId = nil
                return true
            } isTargeted: { targeted in
                withAnimation { dropTargetProjectId = targeted ? project.id : nil }
            }
            .overlay(alignment: .top) {
                if dropTargetProjectId == project.id {
                    RoundedRectangle(cornerRadius: 1).fill(Color.accent).frame(height: 2)
                }
            }

            // Chapter list (expandable)
            if isExpanded {
                VStack(spacing: 3) {
                    let hasContent = !project.chapters.isEmpty || !project.chapterFolders.isEmpty
                    if !hasContent {
                        Button(action: onAddChapter) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle").font(.system(size: 11))
                                Text("Ajouter un chapitre").font(.system(size: 11))
                            }
                            .foregroundColor(.accent.opacity(0.7)).padding(.leading, 28).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Groupes de chapitres
                        ForEach(project.chapterFolders) { folder in
                            ChapterFolderSidebarRow(
                                store: store,
                                projectId: project.id,
                                folderId: folder.id,
                                onSelectChapter: onSelectChapter,
                                onChapterHistory: onChapterHistory,
                                onEditChapter: onEditChapter,
                                onNotesChapter: onNotesChapter
                            )
                            .padding(.leading, 8)
                        }

                        // Chapitres sans groupe
                        let ungrouped = sortedChapters.filter { $0.chapterFolderId == nil }
                        if !ungrouped.isEmpty {
                            if !project.chapterFolders.isEmpty {
                                HStack {
                                    Text("SANS GROUPE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.labelMuted.opacity(0.5))
                                        .kerning(0.8)
                                    Spacer()
                                }
                                .padding(.leading, 20).padding(.top, 4).padding(.bottom, 1)
                            }
                            ForEach(ungrouped) { chapter in
                                let isChapterActive = store.data.activeProjectId == project.id
                                    && (store.data.projects.first(where: { $0.id == project.id })?.activeChapterId == chapter.id)
                                ChapterSidebarRow(
                                    store: store, chapter: chapter, projectId: project.id, isActive: isChapterActive,
                                    onSelect: { onSelectChapter(chapter) },
                                    onHistory: { onChapterHistory(chapter) },
                                    onEdit: { onEditChapter(chapter) },
                                    onNotes: onNotesChapter.map { cb in { cb(chapter) } }
                                )
                                .padding(.leading, 20)
                                .draggable("ch:\(chapter.id.uuidString)") {
                                    HStack(spacing: 6) {
                                        if let tag = chapter.tag { Circle().fill(tag.color).frame(width: 7, height: 7) }
                                        Text(chapter.name).font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.accentWarm.opacity(0.85)).foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("ch:"),
                                          let srcId = UUID(uuidString: String(raw.dropFirst(3))),
                                          srcId != chapter.id else { return false }
                                    store.moveChapterById(srcId, before: chapter.id, in: project.id)
                                    dropTargetChapterId = nil
                                    return true
                                } isTargeted: { targeted in
                                    withAnimation { dropTargetChapterId = targeted ? chapter.id : nil }
                                }
                                .overlay(alignment: .top) {
                                    if dropTargetChapterId == chapter.id {
                                        RoundedRectangle(cornerRadius: 1).fill(Color.accentWarm).frame(height: 2)
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            Color.clear.frame(height: 16)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("ch:"),
                                          let srcId = UUID(uuidString: String(raw.dropFirst(3))) else { return false }
                                    store.moveChapterToEnd(srcId, in: project.id)
                                    return true
                                }
                        }
                    }
                }
                .padding(.top, 2).padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showAddChapterFolder) {
            FolderFormView(
                name: $newChapterFolderName,
                title: "Nouveau groupe de chapitres",
                onSave: {
                    store.addChapterFolder(name: newChapterFolderName, to: project.id)
                    newChapterFolderName = ""
                    showAddChapterFolder = false
                },
                onCancel: { newChapterFolderName = ""; showAddChapterFolder = false }
            )
        }
    }
}

// MARK: - Chapter folder sidebar row

private struct ChapterFolderSidebarRow: View {
    @ObservedObject var store: DataStore
    let projectId: UUID
    let folderId: UUID
    let onSelectChapter: (Chapter) -> Void
    let onChapterHistory: (Chapter) -> Void
    let onEditChapter: (Chapter) -> Void
    var onNotesChapter: ((Chapter) -> Void)? = nil

    @State private var showRenameSheet: Bool = false
    @State private var renameName: String = ""
    @State private var showAddChapter: Bool = false

    private var project: Project? { store.data.projects.first(where: { $0.id == projectId }) }
    private var folder: ChapterFolder? { project?.chapterFolders.first(where: { $0.id == folderId }) }
    private var chaptersInFolder: [Chapter] {
        (project?.chapters ?? []).filter { $0.chapterFolderId == folderId }
    }
    private var activeChapterId: UUID? { project?.activeChapterId }

    var body: some View {
        if let folder = folder {
            VStack(spacing: 0) {
                // Folder header
                HStack(spacing: 6) {
                    Button { store.toggleChapterFolderExpanded(folderId, in: projectId) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 10)
                            Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                            Text(folder.name)
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                            Spacer()
                            Text("\(chaptersInFolder.count)")
                                .font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                    }
                    .buttonStyle(.plain)

                    Button { showAddChapter = true } label: {
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).foregroundColor(.accent)
                            .frame(width: 18, height: 18).background(Color.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)

                    Menu {
                        Button("Renommer") { renameName = folder.name; showRenameSheet = true }
                        Divider()
                        Button("Supprimer le groupe", role: .destructive) {
                            store.deleteChapterFolder(id: folderId, in: projectId)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 9, weight: .medium)).foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.03)))

                if folder.isExpanded {
                    VStack(spacing: 3) {
                        if chaptersInFolder.isEmpty {
                            Button { showAddChapter = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle").font(.system(size: 10))
                                    Text("Ajouter un chapitre").font(.system(size: 10))
                                }
                                .foregroundColor(.accent.opacity(0.6)).padding(.leading, 24).padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(chaptersInFolder) { chapter in
                                let isActive = store.data.activeProjectId == projectId && activeChapterId == chapter.id
                                ChapterSidebarRow(
                                    store: store, chapter: chapter, projectId: projectId, isActive: isActive,
                                    onSelect: { onSelectChapter(chapter) },
                                    onHistory: { onChapterHistory(chapter) },
                                    onEdit: { onEditChapter(chapter) },
                                    onNotes: onNotesChapter.map { cb in { cb(chapter) } }
                                )
                                .padding(.leading, 12)
                            }
                        }
                    }
                    .padding(.top, 2).padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .sheet(isPresented: $showAddChapter) {
                ChapterFormView(store: store, chapter: nil, projectId: projectId, chapterFolderId: folderId)
            }
            .sheet(isPresented: $showRenameSheet) {
                FolderFormView(
                    name: $renameName,
                    title: "Renommer le groupe",
                    onSave: { store.renameChapterFolder(folderId, newName: renameName, in: projectId); showRenameSheet = false },
                    onCancel: { showRenameSheet = false }
                )
            }
        }
    }
}

// MARK: - Chapter row

struct ChapterSidebarRow: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let projectId: UUID
    let isActive: Bool
    let onSelect: () -> Void
    let onHistory: () -> Void
    let onEdit: () -> Void
    var onNotes: (() -> Void)? = nil
    @State private var showDeleteConfirm = false
    @State private var showStatusPicker = false   // V3.2

    private var latest: Int { store.latestTotal(for: chapter.id, in: projectId) }
    private var goal: Int { chapter.goal }
    private var chapterFolders: [ChapterFolder] {
        store.data.projects.first(where: { $0.id == projectId })?.chapterFolders ?? []
    }

    // Si le chapitre est marqué terminé → override à 100 %
    private var ratio: Double {
        if chapter.isCompleted { return 1.0 }
        return goal > 0 ? min(1.0, Double(latest) / Double(goal)) : 0
    }
    private var percentage: Int { Int(ratio * 100) }
    private var statusColor: Color {
        if chapter.isCompleted { return Color.accentGreen }
        return store.statusColor(for: chapter.id, in: projectId, goal: goal)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    // Tag du chapitre
                    if let tag = chapter.tag {
                        Circle().fill(tag.color).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    Text(chapter.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary).lineLimit(1)
                    if chapter.notes != nil {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                            .foregroundColor(.labelMuted.opacity(0.6))
                    }
                    if chapter.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10)).foregroundColor(.accentGreen)
                    }
                    // V3.2 — Badge statut
                    if let st = chapter.status, !chapter.isCompleted {
                        Text(st.label)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color(hex: st.color))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color(hex: st.color).opacity(0.15))
                            .clipShape(Capsule())
                    }
                    Spacer()
                    if goal > 0 {
                        Text("\(percentage)%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                }

                if goal > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(statusColor.opacity(0.15)).frame(height: 3)
                            RoundedRectangle(cornerRadius: 2).fill(statusColor)
                                .frame(width: geo.size.width * ratio, height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal > 0
                             ? store.formatCount(latest) + " / " + store.formatCount(goal)
                             : store.formatCount(latest))
                            .font(.system(size: 10)).foregroundColor(.labelMuted)
                        if let lastDate = chapter.entries.map(\.date).max(),
                           let parsed = DataStore.parseDate(lastDate) {
                            Text("Modifié " + relativeDate(parsed))
                                .font(.system(size: 9))
                                .foregroundColor(.labelMuted.opacity(0.6))
                        }
                        if let eta = store.estimatedCompletionDate(for: chapter.id, in: projectId) {
                            let label = projectionLabel(eta)
                            Text("⏱ " + label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                        if let deadline = chapter.deadline, let date = DataStore.parseDate(deadline) {
                            Text("Deadline: " + DataStore.formatDate(date))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.accentWarm.opacity(0.8))
                        }
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Hist.") { onHistory() }
                            .font(.system(size: 10)).foregroundColor(.accent).buttonStyle(.plain)
                        if let onNotes = onNotes {
                            Button { onNotes() } label: {
                                Image(systemName: "note.text")
                                    .font(.system(size: 10))
                                    .foregroundColor(chapter.noteTags.isEmpty && (chapter.notes == nil || chapter.notes?.isEmpty == true) ? .labelMuted : .accent)
                            }
                            .buttonStyle(.plain)
                            .help("Notes du chapitre")
                        }
                        Menu {
                            Button("Modifier") { onEdit() }
                            Button("Statut du chapitre…") { showStatusPicker = true }  // V3.2
                            Divider()
                            Button(chapter.isCompleted ? "Retirer « Terminé »" : "Marquer comme terminé") {
                                store.toggleChapterComplete(chapter.id, in: projectId)
                            }
                            Menu("Tag") {
                                ForEach(ProjectTag.allCases, id: \.self) { tag in
                                    Button { store.setChapterTag(tag, for: chapter.id, in: projectId) } label: {
                                        Label {
                                            Text(tag.label)
                                        } icon: {
                                            Image(systemName: "circle.fill").foregroundColor(tag.color)
                                        }
                                    }
                                }
                                if chapter.tag != nil {
                                    Divider()
                                    Button("Supprimer le tag") {
                                        store.setChapterTag(nil, for: chapter.id, in: projectId)
                                    }
                                }
                            }
                            if !chapterFolders.isEmpty || chapter.chapterFolderId != nil {
                                Menu("Déplacer vers") {
                                    if chapter.chapterFolderId != nil {
                                        Button("Sans groupe") {
                                            store.moveChapterToFolder(chapter.id, folderId: nil, in: projectId)
                                        }
                                        if !chapterFolders.isEmpty { Divider() }
                                    }
                                    ForEach(chapterFolders) { folder in
                                        Button(folder.name) {
                                            store.moveChapterToFolder(chapter.id, folderId: folder.id, in: projectId)
                                        }
                                        .disabled(chapter.chapterFolderId == folder.id)
                                    }
                                }
                            }
                            Divider()
                            Button("Supprimer le chapitre", role: .destructive) { showDeleteConfirm = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.07)))
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                    }
                    .confirmationDialog(
                        "Supprimer « \(chapter.name) » ?",
                        isPresented: $showDeleteConfirm, titleVisibility: .visible
                    ) {
                        Button("Supprimer le chapitre et toutes ses données", role: .destructive) {
                            store.deleteChapterById(chapter.id, in: projectId)
                        }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Cette action supprimera définitivement le chapitre et tous les caractères enregistrés. Elle est irréversible.")
                    }
                }
            }
            .padding(9)
            .background(isActive ? Color.accent.opacity(0.08) : Color.cardBg.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accent.opacity(0.25) : Color.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        // Clic droit — menu contextuel
        .contextMenu {
            Button("Modifier") { onEdit() }
            Button("Statut du chapitre…") { showStatusPicker = true }  // V3.2
            Divider()
            Button(chapter.isCompleted ? "Retirer « Terminé »" : "Marquer comme terminé") {
                store.toggleChapterComplete(chapter.id, in: projectId)
            }
            Menu("Tag") {
                ForEach(ProjectTag.allCases, id: \.self) { tag in
                    Button { store.setChapterTag(tag, for: chapter.id, in: projectId) } label: {
                        Label {
                            Text(tag.label)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundColor(tag.color)
                        }
                    }
                }
                if chapter.tag != nil {
                    Divider()
                    Button("Supprimer le tag") { store.setChapterTag(nil, for: chapter.id, in: projectId) }
                }
            }
            if !chapterFolders.isEmpty || chapter.chapterFolderId != nil {
                Menu("Déplacer vers") {
                    if chapter.chapterFolderId != nil {
                        Button("Sans groupe") {
                            store.moveChapterToFolder(chapter.id, folderId: nil, in: projectId)
                        }
                        if !chapterFolders.isEmpty { Divider() }
                    }
                    ForEach(chapterFolders) { folder in
                        Button(folder.name) {
                            store.moveChapterToFolder(chapter.id, folderId: folder.id, in: projectId)
                        }
                        .disabled(chapter.chapterFolderId == folder.id)
                    }
                }
            }
            Divider()
            Button("Supprimer le chapitre", role: .destructive) { showDeleteConfirm = true }
        }
        // V3.2 — Sheet statut du chapitre
        .sheet(isPresented: $showStatusPicker) {
            ChapterStatusPickerView(
                store: store,
                chapterId: chapter.id,
                projectId: projectId,
                isPresented: $showStatusPicker
            )
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days) j" }
        return DataStore.formatMonthYear(date)
    }

    private func projectionLabel(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date)).day ?? 0
        if days == 0 { return "Fin aujourd'hui" }
        if days == 1 { return "Fin demain" }
        if days < 30 { return "Fin dans \(days) j" }
        let months = cal.dateComponents([.month], from: Date(), to: date).month ?? 0
        if months < 12 { return "Fin dans \(months) mois" }
        return "Fin \(DataStore.formatMonthYear(date))"
    }
}
