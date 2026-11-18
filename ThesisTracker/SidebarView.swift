import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

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
    @State private var showImport = false
    @State private var showExport = false
    @State private var showAddFolder = false
    @State private var editingFolderName: String = ""
    @State private var dropTargetProjectId: UUID? = nil
    @AppStorage("navGroupEcritureCollapsed") private var navEcritureCollapsed: Bool = false
    @AppStorage("navGroupAnalyseCollapsed") private var navAnalyseCollapsed: Bool = false
    @AppStorage("navGroupOutilsCollapsed") private var navOutilsCollapsed: Bool = false
    @State private var sidebarFilter: String = ""
    @State private var archiveDropActive: Bool = false
    @State private var showArchivedChaptersPopover: Bool = false
    @StateObject private var chapterSelection = ChapterSelectionModel()
    @StateObject private var navHistory = ChapterNavigationHistory()
    @AppStorage("sidebarCompactMode") private var compactMode: Bool = false
    @AppStorage("sidebarReviewFocus") private var reviewFocusMode: Bool = false

    // MARK: - Sorted lists

    /// Active (non-archived) projects only
    private var sortedProjects: [Project] {
        store.sortedProjects(store.data.projects.filter { !$0.isArchived && projectMatchesFilter($0) })
    }
    private var archivedProjects: [Project] { store.data.projects.filter { $0.isArchived } }
    private var folderProjectIds: Set<UUID> { Set(store.data.folders.flatMap { $0.projectIds }) }
    private var ungroupedProjects: [Project] { sortedProjects.filter { !folderProjectIds.contains($0.id) } }
    private func projects(in folder: ProjectFolder) -> [Project] {
        store.sortedProjects(folder.projectIds.compactMap { id in
            store.data.projects.first(where: { $0.id == id && !$0.isArchived && projectMatchesFilter($0) })
        })
    }

    // Filtre live de la sidebar
    private var normalizedFilter: String { sidebarFilter.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
    private var filterActive: Bool { !normalizedFilter.isEmpty }
    private func textMatches(_ text: String) -> Bool {
        guard filterActive else { return true }
        return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter)
    }
    private func projectMatchesFilter(_ project: Project) -> Bool {
        guard filterActive else { return true }
        if textMatches(project.name) { return true }
        if project.chapters.contains(where: { textMatches($0.name) }) { return true }
        if project.chapterFolders.contains(where: { textMatches($0.name) }) { return true }
        return false
    }
    private func folderMatchesFilter(_ folder: ProjectFolder) -> Bool {
        guard filterActive else { return true }
        if textMatches(folder.name) { return true }
        if projects(in: folder).isEmpty == false { return true }
        // Récurse dans les sous-dossiers
        return store.childProjectFolders(of: folder.id).contains { folderMatchesFilter($0) }
    }
    private var visibleProjectFolders: [ProjectFolder] {
        // Seuls les dossiers racine apparaissent au top-level ; les sous-dossiers
        // sont rendus récursivement par FolderSidebarRow.
        store.data.folders.filter { $0.parentId == nil && folderMatchesFilter($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarHeader
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 1).id("__sidebar_top__")
                        // Navigation section
                        sidebarTopSection

                        // Projets section
                        projectSection

                        // Archives section (#17)
                        if !archivedProjects.isEmpty {
                            archivesSection
                        }
                        Color.clear.frame(height: 1).id("__sidebar_bottom__")
                    }
                    .padding(.bottom, 12)
                }
                .overlay(alignment: .top) {
                    Color.clear.frame(height: 18)
                        .dropDestination(for: String.self) { _, _ in false } isTargeted: { hovering in
                            if hovering {
                                withAppAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("__sidebar_top__", anchor: .top)
                                }
                            }
                        }
                }
                .overlay(alignment: .bottom) {
                    Color.clear.frame(height: 18)
                        .dropDestination(for: String.self) { _, _ in false } isTargeted: { hovering in
                            if hovering {
                                withAppAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo("__sidebar_bottom__", anchor: .bottom)
                                }
                            }
                        }
                }
            }
            sidebarProjectProgress
            Divider()
            sidebarFooter
        }
        // 5.25 — en Tuiles : panneau de verre flottant, arrondi, détaché des bords
        .clipShape(AppLook.panelShape(24))
        .appGlass(in: AppLook.panelShape(24), fallback: .sidebarBg)   // 5.16 : verre d'Apple (5.15 : matériau de barre latérale)
        .padding(.vertical, AppLook.tiles ? 10 : 0)
        .padding(.trailing, AppLook.tiles ? 10 : 0)
        .padding(.leading, AppLook.tiles ? 8 : 0)
        .background(navigationShortcuts)
        .onAppear {
            if let id = store.data.activeProjectId { expandedProjects.insert(id) }
        }
        .sheet(isPresented: $showAddProject) { ProjectFormView(store: store, project: nil) }
        .sheet(item: $editingProject) { ProjectFormView(store: store, project: $0) }
        .sheet(item: $addChapterForProject) { ChapterFormView(store: store, chapter: nil, projectId: $0.id) }
        .sheet(item: $editingChapter) { ChapterFormView(store: store, chapter: $0.chapter, projectId: $0.projectId) }
        .sheet(item: $historyItem) { HistoryView(store: store, chapter: $0.chapter, projectId: $0.projectId) }
        .sheet(isPresented: $showImport) { ImportView(store: store) }
        .sheet(isPresented: $showExport) { ExportView(store: store) }
        .sheet(isPresented: $showAddFolder) {
            FolderFormView(name: $editingFolderName, title: "Nouveau dossier",
                onSave: { store.addFolder(name: editingFolderName); editingFolderName = ""; showAddFolder = false },
                onCancel: { editingFolderName = ""; showAddFolder = false })
        }
    }

    /// Haut du panneau : la liste des pages (affichages d'origine), ou le chapitre épinglé (Tuiles, 5.29).
    @ViewBuilder private var sidebarTopSection: some View {
        if AppLook.tiles {
            TilesPinnedChapterCard(store: store) { chapter, projectId in
                historyItem = ChapterEditItem(chapter: chapter, projectId: projectId)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
        } else {
            navSection
            sectionDivider
        }
    }

    // MARK: - Header

    private var sidebarHeader: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: AppLook.r(7, 9), style: .continuous)
                    .fill(LinearGradient(colors: [.accent, .accentWarm], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                Image(systemName: "text.book.closed.fill")
                    .foregroundColor(.white)
                    .font(.system(size: AppLook.fs(11), weight: .semibold))
            }
            Text("Writing Process")
                .font(.system(size: AppLook.tiles ? 15 : 13, weight: AppLook.tiles ? .bold : .semibold))
                .foregroundColor(.primary)
            Spacer()
            // 5.18 : série retirée ici (affichée une seule fois, dans la barre du haut)
            if let saveError = store.saveErrorMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: AppLook.fs(11), weight: .semibold))
                    .foregroundColor(.red)
                    .help("Sauvegarde échouée — \(saveError). Vos modifications ne sont pas encore sur le disque.")
                    .accessibilityLabel("Sauvegarde échouée")
                    .accessibilityHint(saveError)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if store.showSaveIndicator {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.accentGreen.opacity(0.85))
                    .help("Sauvegardé")
                    .accessibilityLabel("Sauvegardé")
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            if store.isUsingICloud {
                Image(systemName: "icloud.fill")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.accent.opacity(0.6))
                    .help("Synchronisé via iCloud Drive · ⌘⇧E pour exporter")
                    .accessibilityLabel("iCloud Drive activé")
            }
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar = false }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.labelMuted)
                    .frame(width: 26, height: 26)
                    .background(Color.glassFill)
                    .clipShape(AppLook.buttonShape(6))
                    .overlay(AppLook.buttonShape(6).stroke(AppLook.hairline, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .help("Masquer la barre latérale")
            .accessibilityLabel("Masquer la barre latérale")
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .appAnimation(Motion.quick, value: store.showSaveIndicator)
        .appAnimation(Motion.quick, value: store.saveErrorMessage != nil)
    }

    // MARK: - Section helpers

    private func sectionLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: AppLook.fs(10), weight: .semibold))
                .foregroundColor(.labelMuted)
            Text(text.uppercased())
                .font(.system(size: AppLook.fs(10), weight: .bold))
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
        VStack(spacing: 0) {
            navGroup(
                label: "Écriture",
                items: [.dashboard, .professor, .overview, .tableOfContents, .deadlines, .kanban],   // 5.18 : professeur à portée ; 5.25 : table des matières
                collapsed: $navEcritureCollapsed
            )
            navGroupDivider
            navGroup(
                label: "Analyse",
                items: [.analytics, .recaps, .widgets],   // 5.15 : Graphiques, Activité, Calendrier, Historique → onglets de « Statistiques »
                collapsed: $navAnalyseCollapsed
            )
            navGroupDivider
            navGroup(
                label: "Outils",
                items: [.timer, .search, .achievements],
                collapsed: $navOutilsCollapsed
            )
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
    }

    private func navGroup(label: String, items: [NavItem], collapsed: Binding<Bool>) -> some View {
        VStack(spacing: 0) {
            Button {
                withAppAnimation(.easeInOut(duration: 0.15)) { collapsed.wrappedValue.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.labelMuted.opacity(0.45))
                    Text(label.capitalized(with: Locale(identifier: "fr_FR")))   // 5.18 : en-tête discret, comme le Finder
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(.labelMuted.opacity(0.75))
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 2)
            }
            .buttonStyle(.pressable)
            .help(collapsed.wrappedValue ? "Déplier \(label)" : "Replier \(label)")

            if !collapsed.wrappedValue {
                VStack(spacing: 1) {
                    ForEach(items) { item in
                        NavItemRow(item: item, isSelected: selectedNav == item || (item == .analytics && NavItem.statsGroup.contains(selectedNav))) {
                            if item == .analytics && NavItem.statsGroup.contains(selectedNav) { return }   // déjà dans les statistiques : on garde l'onglet
                            withAppAnimation(.easeInOut(duration: 0.12)) { selectedNav = item }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var navGroupDivider: some View {
        Divider()
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 0)
    }

    // MARK: - Projects section

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "folder.fill")
                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                    .foregroundColor(.labelMuted)
                Text("PROJETS")
                    .font(.system(size: AppLook.fs(10), weight: .bold)).foregroundColor(.labelMuted).kerning(1.0)
                Spacer()
                // 5.18 : un seul menu « Affichage » au lieu de quatre icônes sans libellé
                Menu {
                    Toggle("Vue compacte", isOn: Binding(get: { compactMode }, set: { v in withAppAnimation { compactMode = v } }))
                    Toggle("Mode revues du directeur", isOn: Binding(get: { reviewFocusMode }, set: { v in withAppAnimation { reviewFocusMode = v } }))
                    Toggle("Trier les projets de A à Z", isOn: Binding(get: { store.data.sortProjectsAlphabetically },
                                                                    set: { v in withAppAnimation { store.data.sortProjectsAlphabetically = v; store.save() } }))
                    Divider()
                    Button(expandedProjects.count >= sortedProjects.count ? "Tout replier" : "Tout déplier") {
                        withAppAnimation {
                            if expandedProjects.count >= sortedProjects.count { expandedProjects.removeAll() }
                            else { expandedProjects = Set(sortedProjects.map(\.id)) }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(compactMode || reviewFocusMode || store.data.sortProjectsAlphabetically ? .accent : .labelMuted)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Affichage de la liste")
                .accessibilityLabel("Affichage de la liste des projets")
                Button { editingFolderName = ""; showAddFolder = true } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: AppLook.fs(11), weight: .semibold)).foregroundColor(.labelMuted)
                        .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                }
                .buttonStyle(.pressable).help("Nouveau dossier")
                .accessibilityLabel("Nouveau dossier")
                Button { showAddProject = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: AppLook.fs(11), weight: .semibold)).foregroundColor(.accent)
                        .frame(width: 22, height: 22)
                        .background(Color.accent.opacity(0.10)).clipShape(AppLook.buttonShape(6))
                }
                .buttonStyle(.pressable).help("Nouveau projet")
                .accessibilityLabel("Nouveau projet")
            }
            .padding(.horizontal, 18).padding(.bottom, 8)

            // Champ de filtre live
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppLook.fs(10), weight: .medium))
                    .foregroundColor(.labelMuted.opacity(0.7))
                TextField("Filtrer projets, dossiers, chapitres…", text: $sidebarFilter)
                    .textFieldStyle(.plain)
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.primary)
                if !sidebarFilter.isEmpty {
                    Button { sidebarFilter = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted.opacity(0.7))
                    }
                    .buttonStyle(.pressable)
                    .help("Effacer le filtre")
                    .accessibilityLabel("Effacer le filtre")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, AppLook.tiles ? 8 : 6)
            .background(Color.fieldBg)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 17), style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 17), style: .continuous).stroke(AppLook.hairline, lineWidth: 1))
            .padding(.horizontal, 14).padding(.bottom, 8)

            VStack(spacing: 4) {
                if store.data.projects.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(.labelMuted.opacity(0.7))
                        Text("Aucun projet")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.labelMuted)
                        Text("Crée ton premier projet pour suivre l'écriture chapitre par chapitre.")
                            .font(.system(size: 10.5))
                            .foregroundColor(.labelMuted.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 18)
                        Button { showAddProject = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus.circle.fill").font(.system(size: AppLook.fs(11)))
                                Text("Nouveau projet").font(.system(size: AppLook.fs(11), weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.accent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Créer un premier projet")
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                    .accessibilityElement(children: .contain)
                } else if reviewFocusMode {
                    reviewFocusView
                } else {
                    // Épinglés (projets + chapitres) — section compacte au-dessus de tout
                    pinnedSection
                    // Dossiers racine — chaque FolderSidebarRow rend récursivement ses sous-dossiers.
                    ForEach(visibleProjectFolders) { folder in
                        FolderSidebarRow(
                            folder: folder, store: store,
                            expandedProjects: $expandedProjects,
                            sidebarFilter: sidebarFilter,
                            chapterSelection: chapterSelection,
                            onEditProject: { editingProject = $0 },
                            onAddChapter: { addChapterForProject = $0 },
                            onSelectChapter: selectChapter,
                            onChapterHistory: { ch, pid in historyItem = ChapterEditItem(chapter: ch, projectId: pid) },
                            onEditChapter: { ch, pid in editingChapter = ChapterEditItem(chapter: ch, projectId: pid) }
                        )
                    }
                    // Zone de drop : pousser un dossier (pf:) tout à la fin (racine)
                    if !store.data.folders.isEmpty && !filterActive {
                        Color.clear.frame(height: 12)
                            .dropDestination(for: String.self) { items, _ in
                                guard let raw = items.first, raw.hasPrefix("pf:"),
                                      let srcId = UUID(uuidString: String(raw.dropFirst(3))) else { return false }
                                store.moveProjectFolderToEnd(srcId)
                                return true
                            }
                    }

                    // Projets non rangés dans un dossier — affichés en vrac, sans en-tête
                    if !ungroupedProjects.isEmpty {
                        ForEach(ungroupedProjects) { project in
                            ProjectSidebarRow(
                                store: store, project: project,
                                isExpanded: expandedProjects.contains(project.id) || filterActive,
                                dropTargetProjectId: $dropTargetProjectId,
                                sidebarFilter: sidebarFilter,
                                chapterSelection: chapterSelection,
                                onToggleExpand: { toggleExpand(project.id) },
                                onEdit: { editingProject = project },
                                onAddChapter: { addChapterForProject = project },
                                onSelectChapter: { selectChapter($0, in: project) },
                                onChapterHistory: { ch in historyItem = ChapterEditItem(chapter: ch, projectId: project.id) },
                                onEditChapter: { ch in editingChapter = ChapterEditItem(chapter: ch, projectId: project.id) }
                            )
                        }

                        // Zone de drop « fin de liste » pour les projets
                        Color.clear.frame(height: 24)
                            .dropDestination(for: String.self) { items, _ in
                                guard let idStr = items.first, let id = UUID(uuidString: idStr) else { return false }
                                store.moveProjectToEnd(id)
                                return true
                            } isTargeted: { targeted in
                                withAppAnimation { dropTargetProjectId = targeted ? UUID() : nil }
                            }
                    }
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Raccourcis navigation (Cmd+[ / Cmd+])

    @ViewBuilder
    private var navigationShortcuts: some View {
        Group {
            Button("") {
                navHistory.goBack(apply: applyHistoryVisit)
            }
            .keyboardShortcut("[", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0)
            .disabled(!navHistory.canGoBack)

            Button("") {
                navHistory.goForward(apply: applyHistoryVisit)
            }
            .keyboardShortcut("]", modifiers: .command)
            .opacity(0).frame(width: 0, height: 0)
            .disabled(!navHistory.canGoForward)
        }
    }

    // MARK: - Mode revues directeur

    @ViewBuilder
    private var reviewFocusView: some View {
        let all = store.data.projects.flatMap { proj in
            proj.chapters.filter { !$0.isArchived && ($0.reviewState == .sent || $0.reviewState == .received) }
                .map { (proj, $0) }
        }
        let sent = all.filter { $0.1.reviewState == .sent }
        let received = all.filter { $0.1.reviewState == .received }

        VStack(alignment: .leading, spacing: 8) {
            if all.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal").font(.system(size: 22)).foregroundColor(.accentGreen.opacity(0.7))
                    Text("Aucun cycle de relecture en cours.").font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else {
                if !received.isEmpty {
                    reviewGroupHeader(label: "Retour reçu — à intégrer", tint: .accentWarm, count: received.count)
                    ForEach(received, id: \.1.id) { item in reviewRow(project: item.0, chapter: item.1) }
                }
                if !sent.isEmpty {
                    reviewGroupHeader(label: "Envoyé — en attente", tint: Color(hex: "#7C3AED"), count: sent.count)
                    ForEach(sent, id: \.1.id) { item in reviewRow(project: item.0, chapter: item.1) }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func reviewGroupHeader(label: String, tint: Color, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(label.uppercased()).font(.system(size: AppLook.fs(10), weight: .bold)).foregroundColor(.labelMuted).kerning(0.8)
            Spacer()
            Text("\(count)").font(.system(size: AppLook.fs(10), weight: .medium)).foregroundColor(.labelMuted)
        }
        .padding(.horizontal, 8).padding(.top, 6)
    }

    private func reviewRow(project: Project, chapter: Chapter) -> some View {
        Button {
            store.data.activeProjectId = project.id
            if let pIdx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                store.data.projects[pIdx].activeChapterId = chapter.id
            }
            store.save()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: chapter.reviewState.icon)
                    .font(.system(size: AppLook.fs(10))).foregroundColor(chapter.reviewState.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chapter.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(project.name).font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                        if let days = chapter.daysSinceSent(), chapter.reviewState == .sent {
                            Text("· envoyé il y a \(days) j")
                                .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: AppLook.r(7, 10)).fill(Color.cardBg.opacity(0.7)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Pinned section (épinglés)

    @ViewBuilder
    private var pinnedSection: some View {
        let pinnedProjects = store.allPinnedProjects()
        let pinnedChapters = store.allPinnedChapters()
        if !pinnedProjects.isEmpty || !pinnedChapters.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: AppLook.fs(10)))
                        .foregroundColor(.accentWarm)
                    Text("ÉPINGLÉS")
                        .font(.system(size: AppLook.fs(10), weight: .bold))
                        .foregroundColor(.labelMuted.opacity(0.7))
                        .kerning(0.8)
                    Spacer()
                }
                .padding(.leading, 8).padding(.top, 2).padding(.bottom, 2)

                ForEach(pinnedProjects) { project in
                    Button {
                        store.data.activeProjectId = project.id
                        store.save()
                    } label: {
                        HStack(spacing: 6) {
                            if let tag = project.tag {
                                Circle().fill(tag.color).frame(width: 7, height: 7)
                            } else {
                                Image(systemName: "books.vertical").font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                            }
                            Text(project.name).font(.system(size: AppLook.fs(11), weight: .medium)).lineLimit(1)
                            Spacer()
                            Button {
                                store.toggleProjectPinned(project.id)
                            } label: {
                                Image(systemName: "pin.slash.fill")
                                    .font(.system(size: AppLook.fs(10)))
                                    .foregroundColor(.labelMuted.opacity(0.6))
                            }
                            .buttonStyle(.pressable).help("Désépingler")
                            .accessibilityLabel("Désépingler")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppLook.buttonShape(6).fill(Color.accentWarm.opacity(0.06)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }

                ForEach(pinnedChapters, id: \.chapter.id) { item in
                    Button {
                        store.data.activeProjectId = item.project.id
                        if let pIdx = store.data.projects.firstIndex(where: { $0.id == item.project.id }) {
                            store.data.projects[pIdx].activeChapterId = item.chapter.id
                        }
                        store.save()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.chapter.name).font(.system(size: AppLook.fs(11), weight: .medium)).lineLimit(1)
                                Text(item.project.name).font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted.opacity(0.7)).lineLimit(1)
                            }
                            Spacer()
                            Button {
                                store.toggleChapterPinned(item.chapter.id, in: item.project.id)
                            } label: {
                                Image(systemName: "pin.slash.fill")
                                    .font(.system(size: AppLook.fs(10)))
                                    .foregroundColor(.labelMuted.opacity(0.6))
                            }
                            .buttonStyle(.pressable).help("Désépingler")
                            .accessibilityLabel("Désépingler")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppLook.buttonShape(6).fill(Color.accentWarm.opacity(0.04)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 2).padding(.bottom, 6)
        }
    }

    // MARK: - Archives section (#17)

    @State private var showArchivedSection: Bool = false

    private var archivesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Separator
            Divider().padding(.horizontal, 12).padding(.vertical, 6)

            // Header
            Button {
                withAppAnimation(.easeInOut(duration: 0.2)) { showArchivedSection.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showArchivedSection ? "archivebox.fill" : "archivebox")
                        .font(.system(size: AppLook.fs(10), weight: .medium))
                        .foregroundColor(.labelMuted)
                    Text("Archives (\(archivedProjects.count))")
                        .font(.system(size: AppLook.fs(11), weight: .medium))
                        .foregroundColor(.labelMuted)
                    Spacer()
                    Image(systemName: showArchivedSection ? "chevron.up" : "chevron.down")
                        .font(.system(size: AppLook.fs(10), weight: .medium))
                        .foregroundColor(.labelMuted.opacity(0.6))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .buttonStyle(.pressable)

            if showArchivedSection {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(archivedProjects) { project in
                        HStack(spacing: 8) {
                            if let tag = project.tag { Circle().fill(tag.color).frame(width: 6, height: 6) }
                            Image(systemName: "archivebox").font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted.opacity(0.6))
                            Text(project.name)
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                store.unarchiveProject(project.id)
                            } label: {
                                Text("Restaurer")
                                    .font(.system(size: AppLook.fs(10), weight: .medium))
                                    .foregroundColor(.accent)
                            }
                            .buttonStyle(.pressable)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 5)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Progression globale du projet

    @ViewBuilder
    private var sidebarProjectProgress: some View {
        if let project = store.activeProject {
            let totalGoal = project.chapters.reduce(0) { $0 + $1.goal }
            if totalGoal > 0 {
                let ratio = store.projectRatiosAll[project.id] ?? 0
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        Text(project.name)
                            .font(.system(size: AppLook.fs(10), weight: .medium))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: AppLook.fs(10), weight: .bold))
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
                                    .appAnimation(Motion.progress, value: ratio)
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
            // 5.18 : rangée de série retirée (doublon de la barre du haut)

            // Mini Pomodoro session timeline
            let todaySessions = pomodoroController.timeline
            if !todaySessions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: AppLook.fs(10)))
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
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.labelMuted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 8) {
                footerIconButton(systemImage: "square.and.arrow.down", color: .accentWarm, help: "Importer des données") {
                    showImport = true
                }
                footerIconButton(systemImage: "square.and.arrow.up", color: .accentGold, help: "Exporter des données") {
                    showExport = true
                }
                archiveFooterIcon
                footerIconButton(systemImage: "plus", color: .accent, help: "Nouveau projet") {
                    showAddProject = true
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var totalArchivedChaptersCount: Int {
        store.data.projects.reduce(0) { $0 + $1.chapters.filter(\.isArchived).count }
    }

    @ViewBuilder
    private var archiveFooterIcon: some View {
        let count = totalArchivedChaptersCount
        let tint: Color = archiveDropActive ? .accentWarm : .labelMuted
        Button { showArchivedChaptersPopover.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: archiveDropActive ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(Color.glassFill)
                    .clipShape(AppLook.buttonShape(8))
                    .overlay(
                        AppLook.buttonShape(8)
                            .stroke(archiveDropActive ? Color.accentWarm : Color.cardBorder,
                                    lineWidth: archiveDropActive ? 1.5 : 1)
                    )
                    .contentShape(Rectangle())
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: AppLook.fs(10), weight: .bold, design: AppLook.fontDesign))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentWarm))
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.pressable)
        .help(count == 0 ? "Glisse un chapitre ici pour l'archiver"
                          : "\(count) chapitre\(count > 1 ? "s" : "") archivé\(count > 1 ? "s" : "") · clique pour restaurer")
        .accessibilityLabel("Archive")
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, raw.hasPrefix("ch:") || raw.hasPrefix("chs:") else { return false }
            let srcIds = chapterIdsFromDragPayload(raw)
            guard !srcIds.isEmpty else { return false }
            for srcId in srcIds {
                guard let srcProjectId = store.projectId(containingChapter: srcId) else { continue }
                store.setChapterArchived(true, chapterId: srcId, in: srcProjectId)
            }
            archiveDropActive = false
            chapterSelection.clear()
            return true
        } isTargeted: { targeted in
            withAppAnimation { archiveDropActive = targeted }
        }
        .popover(isPresented: $showArchivedChaptersPopover, arrowEdge: .top) {
            ArchivedChaptersPopover(store: store, isPresented: $showArchivedChaptersPopover)
        }
    }

    private func sessionDotColor(for entry: PomodoroTimelineEntry) -> Color {
        Color(hex: entry.colorHex)
    }

    private func badgeDotColor(_ threshold: Int) -> Color {
        switch threshold {
        case 3:   return .accent
        case 7:   return Color.semAmber
        case 14:  return Color.semOrange
        case 30:  return Color.semRed
        case 60:  return Color.semViolet
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
        withAppAnimation(Motion.panel) {
            if expandedProjects.contains(id) { expandedProjects.remove(id) }
            else { expandedProjects.insert(id) }
        }
    }

    private func selectChapter(_ chapter: Chapter, in project: Project) {
        store.data.activeProjectId = project.id
        if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
            store.data.projects[idx].activeChapterId = chapter.id
        }
        navHistory.visit(.init(projectId: project.id, chapterId: chapter.id))
        store.save()
    }

    private func applyHistoryVisit(_ v: ChapterNavigationHistory.Visit) {
        store.data.activeProjectId = v.projectId
        if let idx = store.data.projects.firstIndex(where: { $0.id == v.projectId }) {
            store.data.projects[idx].activeChapterId = v.chapterId
        }
        store.save()
    }

    private func footerIconButton(systemImage: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.glassFill)
                .clipShape(AppLook.buttonShape(8))
                .overlay(
                    AppLook.buttonShape(8)
                        .stroke(AppLook.hairline, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(help)
        .accessibilityLabel(help)
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
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isSelected && !AppLook.tiles   // 5.24 : en Tuiles, la ligne choisie est une pastille pleine
                          ? LinearGradient(colors: [.accentWarm, .accentGold], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color.clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 16)
                    .padding(.leading, 2)
                    .appAnimation(.easeInOut(duration: 0.12), value: isSelected)

                HStack(spacing: 8) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 16)
                        .foregroundColor(isSelected ? (AppLook.tiles ? TilesTheme.onBlue : .accentWarm) : (isHovering ? .primary.opacity(0.7) : .labelMuted.opacity(0.7)))
                    Text(item.rawValue)
                        .font(.system(size: AppLook.tiles ? 13 : 12.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? (AppLook.tiles ? TilesTheme.onBlue : .primary) : (isHovering ? .primary.opacity(0.85) : .secondary.opacity(0.75)))
                    Spacer()
                    if isHovering, let hint = item.shortcutHint {
                        Text(hint)
                            .font(.system(size: AppLook.fs(10), weight: .medium, design: .monospaced))
                            .foregroundColor(.labelMuted.opacity(0.7))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.fieldBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .trailing)))
                    }
                }
                .padding(.horizontal, 9).padding(.vertical, AppLook.tiles ? 8 : 7)
                .background(
                    RoundedRectangle(cornerRadius: AppLook.tiles ? 12 : 7, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentWarm.opacity(AppLook.tiles ? 1 : 0.08)
                                : isHovering ? Color.glassFill : Color.clear
                        )
                )
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hovering in
            withAppAnimation(.easeInOut(duration: 0.08)) { isHovering = hovering }
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
            AppBackdrop().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                Text(title)
                    .font(.system(size: 20, weight: .bold, design: AppLook.fontDesign)).foregroundColor(.primary)
                DarkFormField(label: "Nom du dossier", placeholder: "ex: Thèse, Articles…", text: $name, onSubmit: {
                    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    onSave()
                })
                HStack(spacing: 12) {
                    Button("Annuler") { onCancel() }
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable).keyboardShortcut(.escape)
                    Spacer()
                    Button("Créer") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        onSave()
                    }
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(!name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.accent : Color.cardBorder)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                    .buttonStyle(.pressable).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 380)
    }
}

// MARK: - Popover : chapitres archivés

private struct ArchivedChaptersPopover: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool

    private struct ArchivedItem: Identifiable {
        let project: Project
        let chapter: Chapter
        var id: UUID { chapter.id }
    }

    private var items: [ArchivedItem] {
        store.data.projects.flatMap { proj in
            proj.chapters.filter { $0.isArchived }.map { ArchivedItem(project: proj, chapter: $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: AppLook.fs(11))).foregroundColor(.accentWarm)
                Text("Chapitres archivés").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: AppLook.fs(10), weight: .medium)).foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            Divider()
            if items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 18)).foregroundColor(.labelMuted.opacity(0.5))
                    Text("Aucun chapitre archivé.")
                        .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                    Text("Glisse un chapitre sur l'icône 🗄 pour le mettre de côté.")
                        .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(items) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "archivebox")
                                    .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.chapter.name)
                                        .font(.system(size: AppLook.fs(11), weight: .medium))
                                        .lineLimit(1)
                                    Text(item.project.name)
                                        .font(.system(size: AppLook.fs(10)))
                                        .foregroundColor(.labelMuted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button {
                                    store.setChapterArchived(false, chapterId: item.chapter.id, in: item.project.id)
                                } label: {
                                    Text("Restaurer")
                                        .font(.system(size: AppLook.fs(10), weight: .medium))
                                        .foregroundColor(.accent)
                                }
                                .buttonStyle(.pressable)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: AppLook.r(6, 10)).fill(Color.cardBg.opacity(0.7)))
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 280)
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
    @ObservedObject var store: DataStore
    @Binding var expandedProjects: Set<UUID>
    var sidebarFilter: String = ""
    var chapterSelection: ChapterSelectionModel? = nil
    let onEditProject: (Project) -> Void
    let onAddChapter: (Project) -> Void
    let onSelectChapter: (Chapter, Project) -> Void
    let onChapterHistory: (Chapter, UUID) -> Void
    let onEditChapter: (Chapter, UUID) -> Void

    @State private var dropTargetProjectId: UUID? = nil
    @State private var isDropTarget: Bool = false
    @State private var renameDraft: String? = nil
    @State private var showAddSubfolder: Bool = false
    @State private var newSubfolderName: String = ""

    private var normalizedFilter: String { sidebarFilter.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
    private var filterActive: Bool { !normalizedFilter.isEmpty }
    private func textMatches(_ text: String) -> Bool {
        guard filterActive else { return true }
        return text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter)
    }
    private func projectMatchesFilter(_ p: Project) -> Bool {
        guard filterActive else { return true }
        if textMatches(p.name) { return true }
        if p.chapters.contains(where: { textMatches($0.name) }) { return true }
        if p.chapterFolders.contains(where: { textMatches($0.name) }) { return true }
        return false
    }
    private var directProjects: [Project] {
        store.sortedProjects(folder.projectIds.compactMap { id in
            store.data.projects.first(where: { $0.id == id && !$0.isArchived && projectMatchesFilter($0) })
        })
    }
    private var visibleSubfolders: [ProjectFolder] {
        store.childProjectFolders(of: folder.id).filter { subfolderMatchesFilter($0) }
    }
    private func subfolderMatchesFilter(_ f: ProjectFolder) -> Bool {
        guard filterActive else { return true }
        if textMatches(f.name) { return true }
        let hasProjects = f.projectIds.contains { pid in
            guard let p = store.data.projects.first(where: { $0.id == pid }) else { return false }
            return !p.isArchived && projectMatchesFilter(p)
        }
        if hasProjects { return true }
        return store.childProjectFolders(of: f.id).contains { subfolderMatchesFilter($0) }
    }
    /// Compte récursif des projets contenus dans ce dossier et ses descendants.
    private var totalProjectCount: Int { recursiveProjectCount(folder) }
    private func recursiveProjectCount(_ f: ProjectFolder) -> Int {
        let direct = f.projectIds.compactMap { id in
            store.data.projects.first(where: { $0.id == id && !$0.isArchived })
        }.count
        let sub = store.childProjectFolders(of: f.id).reduce(0) { $0 + recursiveProjectCount($1) }
        return direct + sub
    }
    /// Tous les dossiers où l'on peut déplacer celui-ci (exclut soi-même et ses descendants).
    private var moveDestinationOptions: [ProjectFolder] {
        store.data.folders.filter { candidate in
            candidate.id != folder.id && !isAncestor(folder, of: candidate)
        }
    }
    /// Vrai si `ancestor` est un ancêtre (parent direct ou indirect) de `node`.
    private func isAncestor(_ ancestor: ProjectFolder, of node: ProjectFolder) -> Bool {
        var current: UUID? = node.parentId
        while let c = current {
            if c == ancestor.id { return true }
            current = store.data.folders.first(where: { $0.id == c })?.parentId
        }
        return false
    }

    var body: some View { rowBody.modifier(RowHoverScope()) }   // 5.18 : actions de ligne au survol

    @ViewBuilder private var rowBody: some View {
        VStack(spacing: 0) {
            folderHeader
            if folder.isExpanded || filterActive {
                VStack(spacing: 4) {
                    // Sous-dossiers en premier (récursif)
                    ForEach(visibleSubfolders) { sub in
                        FolderSidebarRow(
                            folder: sub, store: store,
                            expandedProjects: $expandedProjects,
                            sidebarFilter: sidebarFilter,
                            chapterSelection: chapterSelection,
                            onEditProject: onEditProject,
                            onAddChapter: onAddChapter,
                            onSelectChapter: onSelectChapter,
                            onChapterHistory: onChapterHistory,
                            onEditChapter: onEditChapter
                        )
                        .padding(.leading, 16)
                    }
                    // Projets directs
                    if directProjects.isEmpty && visibleSubfolders.isEmpty {
                        Text("Aucun projet dans ce dossier")
                            .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                            .padding(.leading, 28).padding(.vertical, 6)
                    } else {
                        ForEach(directProjects) { project in
                            ProjectSidebarRow(
                                store: store, project: project,
                                isExpanded: expandedProjects.contains(project.id) || filterActive,
                                dropTargetProjectId: $dropTargetProjectId,
                                sidebarFilter: sidebarFilter,
                                chapterSelection: chapterSelection,
                                onToggleExpand: {
                                    withAppAnimation(Motion.panel) {
                                        if expandedProjects.contains(project.id) { expandedProjects.remove(project.id) }
                                        else { expandedProjects.insert(project.id) }
                                    }
                                },
                                onEdit: { onEditProject(project) },
                                onAddChapter: { onAddChapter(project) },
                                onSelectChapter: { onSelectChapter($0, project) },
                                onChapterHistory: { onChapterHistory($0, project.id) },
                                onEditChapter: { onEditChapter($0, project.id) }
                            )
                            .padding(.leading, 16)
                        }
                    }
                }
                .padding(.top, 2).padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppLook.buttonShape(8).fill(Color.accent.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
        .sheet(isPresented: $showAddSubfolder) {
            FolderFormView(
                name: $newSubfolderName,
                title: "Nouveau sous-dossier dans « \(folder.name) »",
                onSave: {
                    store.addFolder(name: newSubfolderName, parentId: folder.id)
                    if !folder.isExpanded { store.toggleFolderExpanded(folder.id) }
                    newSubfolderName = ""
                    showAddSubfolder = false
                },
                onCancel: { newSubfolderName = ""; showAddSubfolder = false }
            )
        }
    }

    private var folderHeader: some View {
        HStack(spacing: 8) {
            Button { store.toggleFolderExpanded(folder.id) } label: {
                HStack(spacing: 8) {
                    Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: AppLook.fs(10), weight: .semibold)).foregroundColor(.labelMuted).frame(width: 12)
                    Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                        .font(.system(size: 12)).foregroundColor(.accent.opacity(0.8))
                    if renameDraft != nil {
                        InlineRenameField(
                            text: Binding(get: { renameDraft ?? "" }, set: { renameDraft = $0 }),
                            font: .system(size: 13, weight: .medium),
                            onCommit: { store.renameProjectFolder(folder.id, newName: $0) },
                            onCancel: { renameDraft = nil }
                        )
                    } else {
                        Text(folder.name)
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                            .highPriorityGesture(TapGesture(count: 2).onEnded { renameDraft = folder.name })
                    }
                    Spacer()
                    Text("\(totalProjectCount)").font(.system(size: AppLook.fs(10), weight: .medium)).foregroundColor(.labelMuted)
                }
            }
            .buttonStyle(.pressable)
            Menu {
                Button("Renommer") { renameDraft = folder.name }
                Button("Nouveau sous-dossier…") {
                    newSubfolderName = ""
                    showAddSubfolder = true
                }
                if !moveDestinationOptions.isEmpty || folder.parentId != nil {
                    Menu("Déplacer vers") {
                        if folder.parentId != nil {
                            Button("Racine") { store.moveProjectFolder(folder.id, toParent: nil) }
                            Divider()
                        }
                        ForEach(moveDestinationOptions) { dest in
                            Button(dest.name) { store.moveProjectFolder(folder.id, toParent: dest.id) }
                                .disabled(dest.id == folder.parentId)
                        }
                    }
                }
                Divider()
                Button("Supprimer le dossier", role: .destructive) {
                    store.deleteFolder(id: folder.id, keepProjects: true)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: AppLook.fs(10), weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                        .fill(Color.primary.opacity(0.07)))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .help("Options du dossier").modifier(RevealOnRowHover())
            .accessibilityLabel("Options du dossier")
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: AppLook.r(7, 10))
                .fill(isDropTarget ? Color.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(7, 10))
                .stroke(isDropTarget ? Color.accent : Color.clear, lineWidth: 1)
        )
        .draggable("pf:\(folder.id.uuidString)") {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").font(.system(size: AppLook.fs(11))).foregroundColor(.white)
                Text(folder.name).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.accent.opacity(0.85)).foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first else { return false }
            // pf: → réordonnancement (au même niveau que la cible, via moveProjectFolderById)
            if raw.hasPrefix("pf:") {
                guard let srcId = UUID(uuidString: String(raw.dropFirst(3))),
                      srcId != folder.id else { return false }
                store.moveProjectFolderById(srcId, before: folder.id)
                isDropTarget = false
                return true
            }
            // Projet → ranger dans ce dossier
            guard let srcId = UUID(uuidString: raw),
                  store.data.projects.contains(where: { $0.id == srcId }) else { return false }
            store.moveProject(srcId, toFolder: folder.id)
            isDropTarget = false
            return true
        } isTargeted: { targeted in
            withAppAnimation { isDropTarget = targeted }
        }
    }
}

// MARK: - Export / import de sous-arbre (panels macOS)

enum SubtreeIO {
    static func exportAndSave(_ data: Data, suggestedName: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName + ".wpbranch.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    /// Ouvre un panel pour choisir un fichier .json à importer. Retourne les Data ou nil.
    static func openForImport() -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url) else { return nil }
        return data
    }
}

// MARK: - Historique de navigation chapitres

final class ChapterNavigationHistory: ObservableObject {
    struct Visit: Equatable {
        let projectId: UUID
        let chapterId: UUID
    }
    @Published private(set) var back: [Visit] = []
    @Published private(set) var forward: [Visit] = []
    @Published private(set) var current: Visit?

    func visit(_ v: Visit) {
        guard v != current else { return }
        if let c = current { back.append(c) }
        current = v
        forward.removeAll()
        if back.count > 50 { back.removeFirst(back.count - 50) }
    }

    func goBack(apply: (Visit) -> Void) {
        guard let prev = back.popLast() else { return }
        if let c = current { forward.append(c) }
        current = prev
        apply(prev)
    }

    func goForward(apply: (Visit) -> Void) {
        guard let next = forward.popLast() else { return }
        if let c = current { back.append(c) }
        current = next
        apply(next)
    }

    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
}

// MARK: - Multi-sélection de chapitres

/// Modèle partagé pour la sélection multi-chapitres (Cmd+clic, Maj+clic).
final class ChapterSelectionModel: ObservableObject {
    @Published var selected: Set<UUID> = []
    @Published var anchorChapterId: UUID? = nil
    @Published var anchorProjectId: UUID? = nil

    func isSelected(_ id: UUID) -> Bool { selected.contains(id) }
    var count: Int { selected.count }

    func clear() {
        selected.removeAll()
        anchorChapterId = nil
        anchorProjectId = nil
    }

    func selectOnly(_ id: UUID, in projectId: UUID) {
        selected = [id]
        anchorChapterId = id
        anchorProjectId = projectId
    }

    func toggle(_ id: UUID, in projectId: UUID) {
        if selected.contains(id) {
            selected.remove(id)
            if anchorChapterId == id { anchorChapterId = selected.first }
        } else {
            selected.insert(id)
            anchorChapterId = id
            anchorProjectId = projectId
        }
    }

    /// Étend la sélection depuis l'ancre jusqu'au chapitre cible — uniquement valide
    /// si l'ancre est dans le même projet que la cible.
    func selectRange(to targetId: UUID, in projectId: UUID, allChapterIds: [UUID]) {
        guard anchorProjectId == projectId,
              let anchor = anchorChapterId,
              let anchorIdx = allChapterIds.firstIndex(of: anchor),
              let targetIdx = allChapterIds.firstIndex(of: targetId) else {
            selectOnly(targetId, in: projectId)
            return
        }
        let lo = min(anchorIdx, targetIdx)
        let hi = max(anchorIdx, targetIdx)
        selected = Set(allChapterIds[lo...hi])
    }

    /// Renvoie la liste ordonnée d'IDs à utiliser comme payload de drag.
    /// Si le chapitre déclencheur n'est pas dans la sélection, on ne drag que lui.
    func dragIds(triggeredBy chapterId: UUID) -> [UUID] {
        if selected.contains(chapterId), selected.count > 1 {
            return Array(selected)
        }
        return [chapterId]
    }
}

/// Parse un payload de drag chapitre — supporte "ch:UUID" (1 chapitre) et "chs:UUID,UUID,..." (multi).
func chapterIdsFromDragPayload(_ payload: String) -> [UUID] {
    if payload.hasPrefix("chs:") {
        return String(payload.dropFirst(4))
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
    }
    if payload.hasPrefix("ch:") {
        return [UUID(uuidString: String(payload.dropFirst(3)))].compactMap { $0 }
    }
    return []
}

func chapterDragPayload(_ ids: [UUID]) -> String {
    if ids.count == 1 { return "ch:\(ids[0].uuidString)" }
    return "chs:" + ids.map(\.uuidString).joined(separator: ",")
}

/// Déplace une liste de chapitres vers un projet/dossier cible.
/// - Si `beforeChapter` est fourni : insère juste avant ce chapitre, en préservant l'ordre des sources.
/// - Sinon : append à la fin (et change de folder si demandé).
/// Filtre les sources auto-référentielles (on n'insère pas un chapitre avant lui-même).
func applyChapterMove(_ srcIds: [UUID],
                      beforeChapter: UUID?,
                      in targetProjectId: UUID,
                      folderId: UUID? = nil,
                      store: DataStore) {
    // Filtrer le chapitre cible lui-même (sinon on essaie de l'insérer avant lui)
    let ids = srcIds.filter { $0 != beforeChapter }
    // Insérer dans l'ordre fourni — pour préserver l'ordre, on insère du dernier au premier
    // si on insère avant un point fixe (sinon ils s'inverseraient).
    let ordered = beforeChapter != nil ? Array(ids.reversed()) : ids
    for srcId in ordered {
        guard let srcProjectId = store.projectId(containingChapter: srcId) else { continue }
        if srcProjectId == targetProjectId {
            if let target = beforeChapter {
                store.moveChapterById(srcId, before: target, in: targetProjectId)
            } else {
                if folderId != nil { store.moveChapterToFolder(srcId, folderId: folderId, in: targetProjectId) }
                store.moveChapterToEnd(srcId, in: targetProjectId)
            }
        } else {
            store.moveChapterToProject(srcId, from: srcProjectId, to: targetProjectId,
                                       folderId: folderId, beforeChapterId: beforeChapter)
        }
    }
}

// MARK: - Inline rename helper

/// Petit champ texte inline auto-focus pour le renommage rapide.
/// Enter valide, Esc annule (les deux passent par onCancel pour fermer la cellule).
private struct InlineRenameField: View {
    @Binding var text: String
    var font: Font = .system(size: 13, weight: .medium)
    var foreground: Color = .primary
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundColor(foreground)
            .padding(.vertical, 1).padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.fieldBg))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.accent.opacity(0.6), lineWidth: 1))
            .focused($focused)
            .onAppear { focused = true }
            .onSubmit {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { onCommit(trimmed) }
                onCancel()
            }
            .onExitCommand { onCancel() }
    }
}

// MARK: - Mini Progress Ring (replaces Sparkline)

private struct MiniProgressRing: View {
    let ratio: Double   // 0.0 → 1.0
    let color: Color

    private let size: CGFloat = 22
    private let lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(ratio, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .appAnimation(Motion.progress, value: ratio)
            // 5.18 : plus de pourcentage en 5,5 pt dans l'anneau (illisible) ; valeur au survol et pour VoiceOver
        }
        .frame(width: size, height: size)
        .help("\(Int(min(ratio, 1) * 100)) %")
        .accessibilityElement()
        .accessibilityLabel("Avancement")
        .accessibilityValue("\(Int(min(ratio, 1) * 100)) pour cent")
    }
}

// MARK: - Project row

struct ProjectSidebarRow: View {
    @ObservedObject var store: DataStore
    let project: Project
    let isExpanded: Bool
    @Binding var dropTargetProjectId: UUID?
    var sidebarFilter: String = ""
    var chapterSelection: ChapterSelectionModel? = nil
    let onToggleExpand: () -> Void
    let onEdit: () -> Void
    let onAddChapter: () -> Void
    let onSelectChapter: (Chapter) -> Void
    let onChapterHistory: (Chapter) -> Void
    let onEditChapter: (Chapter) -> Void

    @State private var showDeleteProjectConfirm = false
    @State private var dropTargetChapterId: UUID? = nil
    @State private var showAddChapterFolder: Bool = false
    @State private var newChapterFolderName: String = ""
    @State private var renameDraft: String? = nil

    private var isActive: Bool { store.data.activeProjectId == project.id }
    private var normalizedFilter: String { sidebarFilter.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
    private var filterActive: Bool { !normalizedFilter.isEmpty }
    private func chapterMatchesFilter(_ chapter: Chapter) -> Bool {
        guard filterActive else { return true }
        if chapter.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) { return true }
        if let folderId = chapter.chapterFolderId,
           let folder = project.chapterFolders.first(where: { $0.id == folderId }),
           folder.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) { return true }
        return false
    }
    private func chapterFolderMatchesFilter(_ folder: ChapterFolder) -> Bool {
        guard filterActive else { return true }
        if folder.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) { return true }
        if project.chapters.contains(where: { $0.chapterFolderId == folder.id && $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) }) {
            return true
        }
        // Récurse dans les sous-dossiers
        return store.childChapterFolders(of: folder.id, in: project.id).contains { chapterFolderMatchesFilter($0) }
    }
    private var sortedChapters: [Chapter] {
        store.sortedChapters(project.chapters)
            .filter { !$0.isArchived && chapterMatchesFilter($0) }
    }
    private var visibleChapterFolders: [ChapterFolder] {
        // Seuls les dossiers racine ici ; les sous-dossiers sont rendus récursivement
        // par ChapterFolderSidebarRow.
        project.chapterFolders.filter { $0.parentId == nil && chapterFolderMatchesFilter($0) }
    }

    private var projectRatio: Double {
        store.projectRatiosAll[project.id] ?? 0
    }

    private var projectRingColor: Color {
        if let tag = project.tag { return tag.color }
        return .accent
    }

    private var chapterCountSummary: String? {
        let active = project.chapters.filter { !$0.isArchived }
        let total = active.count
        guard total > 0 else { return nil }
        let done = active.filter { $0.isCompleted }.count
        if done == 0 { return total == 1 ? "1 chapitre" : "\(total) chapitres" }
        return "\(total) chapitre\(total > 1 ? "s" : "") · \(done) terminé\(done > 1 ? "s" : "")"
    }

    var body: some View { rowBody.modifier(RowHoverScope()) }   // 5.18 : actions de ligne au survol

    @ViewBuilder private var rowBody: some View {
        VStack(spacing: 0) {
            // Project row header
            HStack(spacing: 8) {
                Button(action: onToggleExpand) {
                    HStack(spacing: 8) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: AppLook.fs(10), weight: .semibold)).foregroundColor(.labelMuted).frame(width: 12)
                        if let tag = project.tag {
                            Circle().fill(tag.color).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        } else if !AppLook.tiles {   // 5.33 : en Tuiles, lignes simples, sans icône
                            Image(systemName: isActive ? "books.vertical.fill" : "books.vertical")
                                .font(.system(size: 12))
                                .foregroundColor(isActive ? .accent : .labelMuted)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            if renameDraft != nil {
                                InlineRenameField(
                                    text: Binding(get: { renameDraft ?? "" }, set: { renameDraft = $0 }),
                                    font: .system(size: 13, weight: isActive ? .semibold : .medium),
                                    onCommit: { store.renameProject(project.id, newName: $0) },
                                    onCancel: { renameDraft = nil }
                                )
                            } else {
                                Text(project.name)
                                    .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                                    .foregroundColor(.primary).lineLimit(1)
                                    .layoutPriority(1)
                                    .highPriorityGesture(TapGesture(count: 2).onEnded { renameDraft = project.name })
                            }
                            if let summary = chapterCountSummary, !AppLook.tiles {   // 5.33 : au survol en Tuiles
                                Text(summary)
                                    .font(.system(size: AppLook.fs(10), weight: .medium))
                                    .foregroundColor(.labelMuted.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if AppLook.tiles {
                            // 5.33 — pourcentage aligné à droite, à la place de l'anneau
                            Text("\(Int(min(projectRatio, 1) * 100)) %")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundColor(.labelMuted)
                                .fixedSize()
                                .accessibilityLabel("Avancement \(Int(min(projectRatio, 1) * 100)) pour cent")
                        } else {
                            MiniProgressRing(ratio: projectRatio, color: projectRingColor)
                                .opacity(0.85)
                        }
                    }
                }
                .buttonStyle(.pressable)
                .help(AppLook.tiles ? (chapterCountSummary ?? project.name) : "")

                HStack(spacing: 4) {
                    Button {
                        newChapterFolderName = ""
                        showAddChapterFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: AppLook.fs(10), weight: .semibold))
                            .foregroundColor(.accent.opacity(0.75))
                            .frame(width: 20, height: 20)
                            .background(Color.accent.opacity(0.08))
                            .clipShape(AppLook.buttonShape(5))
                    }
                    .buttonStyle(.pressable)
                    .help("Nouveau dossier dans \(project.name)").modifier(RevealOnRowHover())
                    .accessibilityLabel("Nouveau dossier")

                    Button(action: onAddChapter) {
                        Image(systemName: "plus").font(.system(size: AppLook.fs(10), weight: .semibold)).foregroundColor(.accent)
                            .frame(width: 20, height: 20).background(Color.accent.opacity(0.10)).clipShape(AppLook.buttonShape(5))
                    }
                    .buttonStyle(.pressable)
                    .help("Nouveau chapitre dans \(project.name)").modifier(RevealOnRowHover())
                    .accessibilityLabel("Nouveau chapitre")

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
                                    Button("Retirer du dossier") { store.moveProject(project.id, toFolder: nil) }
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
                            set: { store.data.sortChaptersAlphabetically = $0
                                   store.sortChaptersByProgress = false
                                   store.save() }
                        )) { Label("Chapitres A → Z", systemImage: "textformat.abc") }
                        Toggle(isOn: Binding(
                            get: { store.sortChaptersByProgress },
                            set: { store.sortChaptersByProgress = $0
                                   if $0 { store.data.sortChaptersAlphabetically = false }
                                   store.save() }
                        )) { Label("Par progression ↑", systemImage: "chart.line.uptrend.xyaxis") }
                        Button("Nouveau dossier") {
                            newChapterFolderName = ""
                            showAddChapterFolder = true
                        }
                        if !project.chapterFolders.isEmpty {
                            let allExpanded = project.chapterFolders.allSatisfy { $0.isExpanded }
                            Button(allExpanded ? "Replier tous les dossiers" : "Déplier tous les dossiers") {
                                store.setAllChapterFoldersExpanded(!allExpanded, in: project.id)
                            }
                        }
                        Divider()
                        Button(project.isPinned ? "Désépingler" : "Épingler en haut") {
                            store.toggleProjectPinned(project.id)
                        }
                        Divider()
                        Button("Exporter cette branche…") {
                            if let data = try? store.exportProjectPayload(project.id) {
                                SubtreeIO.exportAndSave(data, suggestedName: project.name)
                            }
                        }
                        Button("Importer ici…") {
                            if let data = SubtreeIO.openForImport() {
                                _ = try? store.importSubtreePayload(data, intoProjectId: project.id)
                            }
                        }
                        Divider()
                        Button("Archiver") { store.archiveProject(project.id) }
                        Divider()
                        Button("Supprimer…", role: .destructive) { showDeleteProjectConfirm = true }   // 5.23 — confirmation
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: AppLook.fs(10), weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                .fill(Color.primary.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Options du projet").modifier(RevealOnRowHover())
                    .accessibilityLabel("Options du projet")
                    .confirmationDialog(
                        "Supprimer « \(project.name) » ?",
                        isPresented: $showDeleteProjectConfirm, titleVisibility: .visible
                    ) {
                        Button("Supprimer le projet et ses \(project.chapters.count) chapitres", role: .destructive) {
                            store.deleteProject(id: project.id)
                        }
                        Button("Annuler", role: .cancel) {}
                    } message: {
                        Text("Le projet, ses chapitres et toutes leurs saisies seront supprimés. ⌘Z permet de revenir en arrière tant que l'app reste ouverte.")
                    }
                }
                .modifier(CollapseOffRowHover())   // 5.28 : hors survol, ces boutons ne prennent plus de place (le nom n'est plus tronqué)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: AppLook.r(8, 12), style: .continuous).fill(isActive && !AppLook.tiles ? Color.accent.opacity(0.06) : Color.clear))   // 5.33 : en Tuiles, seul le chapitre actif est marqué
            // Drag source pour le projet
            .draggable(project.id.uuidString) {
                HStack(spacing: 6) {
                    if let tag = project.tag { Circle().fill(tag.color).frame(width: 8, height: 8) }
                    Text(project.name).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.accent.opacity(0.85)).foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
            }
            // Drop target : (a) réordonner les projets, (b) déplacer un (ou plusieurs) chapitres vers ce projet
            .dropDestination(for: String.self) { items, _ in
                guard let raw = items.first else { return false }
                // Chapitre(s) → migration vers ce projet
                if raw.hasPrefix("ch:") || raw.hasPrefix("chs:") {
                    let srcIds = chapterIdsFromDragPayload(raw)
                    guard !srcIds.isEmpty else { return false }
                    applyChapterMove(srcIds, beforeChapter: nil, in: project.id, folderId: nil, store: store)
                    dropTargetProjectId = nil
                    chapterSelection?.clear()
                    return true
                }
                // Sinon : réordonnancement de projet
                guard let srcId = UUID(uuidString: raw), srcId != project.id else { return false }
                store.moveProjectById(srcId, before: project.id)
                dropTargetProjectId = nil
                return true
            } isTargeted: { targeted in
                withAppAnimation { dropTargetProjectId = targeted ? project.id : nil }
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
                                Image(systemName: "plus.circle").font(.system(size: AppLook.fs(11)))
                                Text("Ajouter un chapitre")
                                    .font(.system(size: AppLook.fs(11)))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accent.opacity(0.7)).padding(.leading, 28).padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                    } else {
                        // Chapitres non rangés — affichés EN PREMIER
                        let ungrouped = sortedChapters.filter { $0.chapterFolderId == nil }
                        if !ungrouped.isEmpty {
                            let ungroupedIds = ungrouped.map(\.id)
                            ForEach(ungrouped) { chapter in
                                let isChapterActive = store.data.activeProjectId == project.id
                                    && (store.data.projects.first(where: { $0.id == project.id })?.activeChapterId == chapter.id)
                                let dragIds = chapterSelection?.dragIds(triggeredBy: chapter.id) ?? [chapter.id]
                                ChapterSidebarRow(
                                    store: store, chapter: chapter, projectId: project.id, isActive: isChapterActive,
                                    selection: chapterSelection,
                                    siblingChapterIds: ungroupedIds,
                                    onSelect: { onSelectChapter(chapter) },
                                    onHistory: { onChapterHistory(chapter) },
                                    onEdit: { onEditChapter(chapter) }
                                )
                                .padding(.leading, 20)
                                .draggable(chapterDragPayload(dragIds)) {
                                    HStack(spacing: 6) {
                                        if let tag = chapter.tag { Circle().fill(tag.color).frame(width: 7, height: 7) }
                                        Text(dragIds.count > 1 ? "\(dragIds.count) chapitres" : chapter.name)
                                            .font(.system(size: AppLook.fs(11), weight: .medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.accentWarm.opacity(0.85)).foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first else { return false }
                                    let srcIds = chapterIdsFromDragPayload(raw)
                                    guard !srcIds.isEmpty else { return false }
                                    applyChapterMove(srcIds, beforeChapter: chapter.id, in: project.id, store: store)
                                    dropTargetChapterId = nil
                                    return true
                                } isTargeted: { targeted in
                                    withAppAnimation { dropTargetChapterId = targeted ? chapter.id : nil }
                                }
                                .overlay(alignment: .top) {
                                    if dropTargetChapterId == chapter.id {
                                        RoundedRectangle(cornerRadius: 1).fill(Color.accentWarm).frame(height: 2)
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            // Zone de drop : fin des chapitres non rangés
                            Color.clear.frame(height: 8)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first else { return false }
                                    let srcIds = chapterIdsFromDragPayload(raw)
                                    guard !srcIds.isEmpty else { return false }
                                    applyChapterMove(srcIds, beforeChapter: nil, in: project.id, folderId: nil, store: store)
                                    return true
                                }
                        }

                        // Dossiers — affichés EN SECOND (un nouveau dossier apparaît donc à la fin)
                        ForEach(visibleChapterFolders) { folder in
                            ChapterFolderSidebarRow(
                                store: store,
                                projectId: project.id,
                                folderId: folder.id,
                                sidebarFilter: sidebarFilter,
                                chapterSelection: chapterSelection,
                                onSelectChapter: onSelectChapter,
                                onChapterHistory: onChapterHistory,
                                onEditChapter: onEditChapter
                            )
                            .padding(.leading, 8)
                            .draggable("cf:\(folder.id.uuidString)") {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: AppLook.fs(11)))
                                        .foregroundColor(.white)
                                    Text(folder.name).font(.system(size: AppLook.fs(11), weight: .medium))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.accent.opacity(0.85)).foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                            }
                        }
                        // Zone de drop : déplacer un dossier tout à la fin
                        if !project.chapterFolders.isEmpty {
                            Color.clear.frame(height: 16)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let raw = items.first, raw.hasPrefix("cf:"),
                                          let srcId = UUID(uuidString: String(raw.dropFirst(3))) else { return false }
                                    store.moveChapterFolderToEnd(srcId, in: project.id)
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
                title: "Nouveau dossier dans « \(project.name) »",
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
    var sidebarFilter: String = ""
    var chapterSelection: ChapterSelectionModel? = nil
    let onSelectChapter: (Chapter) -> Void
    let onChapterHistory: (Chapter) -> Void
    let onEditChapter: (Chapter) -> Void

    @State private var showRenameSheet: Bool = false
    @State private var renameName: String = ""
    @State private var showAddChapter: Bool = false
    @State private var isDropTarget: Bool = false
    @State private var renameDraft: String? = nil
    @State private var showAddSubfolder: Bool = false
    @State private var newSubfolderName: String = ""

    private var normalizedFilter: String { sidebarFilter.trimmingCharacters(in: .whitespaces).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
    private var filterActive: Bool { !normalizedFilter.isEmpty }
    private var project: Project? { store.data.projects.first(where: { $0.id == projectId }) }
    private var folder: ChapterFolder? { project?.chapterFolders.first(where: { $0.id == folderId }) }
    private var chaptersInFolder: [Chapter] {
        let all = (project?.chapters ?? []).filter { $0.chapterFolderId == folderId && !$0.isArchived }
        guard filterActive else { return all }
        // Si le nom du dossier matche, montrer tous ses chapitres ; sinon filtrer par nom de chapitre
        if folder?.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) == true { return all }
        return all.filter { $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) }
    }
    private var visibleSubfolders: [ChapterFolder] {
        store.childChapterFolders(of: folderId, in: projectId).filter { subfolderMatchesFilter($0) }
    }
    private func subfolderMatchesFilter(_ f: ChapterFolder) -> Bool {
        guard filterActive else { return true }
        if f.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter) { return true }
        let hasChapter = (project?.chapters ?? []).contains {
            $0.chapterFolderId == f.id && !$0.isArchived && $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(normalizedFilter)
        }
        if hasChapter { return true }
        return store.childChapterFolders(of: f.id, in: projectId).contains { subfolderMatchesFilter($0) }
    }
    private var activeChapterId: UUID? { project?.activeChapterId }

    /// Chapitres descendants (récursif) — utilisé pour l'agrégation de progression et le tooltip.
    private var allDescendantChapters: [Chapter] {
        guard let proj = project, let folder = folder else { return [] }
        var collected: [Chapter] = []
        var stack: [UUID] = [folder.id]
        while let id = stack.popLast() {
            collected.append(contentsOf: proj.chapters.filter { $0.chapterFolderId == id && !$0.isArchived })
            for sub in proj.chapterFolders where sub.parentId == id {
                stack.append(sub.id)
            }
        }
        return collected
    }

    /// Progression agrégée du dossier (chapitres directs + descendants).
    private var folderRatio: Double {
        let chapters = allDescendantChapters
        let totalGoal = chapters.reduce(0) { $0 + $1.goal }
        guard totalGoal > 0 else { return 0 }
        let totalLatest = chapters.reduce(0) { acc, ch in
            let raw = ch.isCompleted ? ch.goal : store.latestTotal(for: ch.id, in: projectId)
            return acc + max(0, min(ch.goal, raw))
        }
        return min(1.0, Double(totalLatest) / Double(totalGoal))
    }

    private var folderRingColor: Color {
        folderRatio >= 1.0 ? .accentGreen : .accent
    }

    /// Cibles de déplacement pour ce dossier (autres dossiers du même projet, hors descendants).
    private var moveDestinationOptions: [ChapterFolder] {
        guard let proj = project else { return [] }
        return proj.chapterFolders.filter { candidate in
            candidate.id != folderId && !isAncestorChapterFolder(of: candidate)
        }
    }
    private func isAncestorChapterFolder(of node: ChapterFolder) -> Bool {
        guard let proj = project else { return false }
        var current: UUID? = node.parentId
        while let c = current {
            if c == folderId { return true }
            current = proj.chapterFolders.first(where: { $0.id == c })?.parentId
        }
        return false
    }

    /// Tooltip riche : compteurs et dernière saisie agrégés sur le dossier (incluant descendants).
    private var folderTooltip: String {
        guard let folder = folder else { return "" }
        let chapters = allDescendantChapters
        let count = chapters.count
        let completed = chapters.filter(\.isCompleted).count
        let inProgress = chapters.filter { !$0.isCompleted && (store.latestTotal(for: $0.id, in: projectId) > 0) }.count
        let totalGoal = chapters.reduce(0) { $0 + $1.goal }
        let totalLatest = chapters.reduce(0) { acc, ch in
            let raw = ch.isCompleted ? ch.goal : store.latestTotal(for: ch.id, in: projectId)
            return acc + max(0, min(ch.goal, raw))
        }
        let lastEntry = chapters.compactMap { ch in
            ch.entries.map(\.date).max().flatMap(DataStore.parseDate(_:))
        }.max()
        var lines: [String] = ["📁 \(folder.name)"]
        lines.append("\(count) chapitre\(count > 1 ? "s" : "")")
        if totalGoal > 0 {
            let pct = Int(folderRatio * 100)
            lines.append("\(store.formatCount(totalLatest)) / \(store.formatCount(totalGoal)) (\(pct) %)")
        }
        if completed > 0 || inProgress > 0 {
            var parts: [String] = []
            if inProgress > 0 { parts.append("\(inProgress) en cours") }
            if completed > 0 { parts.append("\(completed) terminé\(completed > 1 ? "s" : "")") }
            lines.append(parts.joined(separator: " · "))
        }
        if let last = lastEntry {
            let cal = Calendar(identifier: .gregorian)
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: Date())).day ?? 0
            let rel: String
            if days == 0 { rel = "aujourd'hui" }
            else if days == 1 { rel = "hier" }
            else if days < 30 { rel = "il y a \(days) j" }
            else { rel = DataStore.formatMonthYear(last) }
            lines.append("Dernière saisie : \(rel)")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View { rowBody.modifier(RowHoverScope()) }   // 5.18 : actions de ligne au survol

    @ViewBuilder private var rowBody: some View {
        if let folder = folder {
            VStack(spacing: 0) {
                // Folder header
                HStack(spacing: 6) {
                    Button { store.toggleChapterFolderExpanded(folderId, in: projectId) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: folder.isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: AppLook.fs(10), weight: .semibold)).foregroundColor(.labelMuted).frame(width: 10)
                            if !AppLook.tiles {   // 5.33
                                Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                                    .font(.system(size: AppLook.fs(11)))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            if renameDraft != nil {
                                InlineRenameField(
                                    text: Binding(get: { renameDraft ?? "" }, set: { renameDraft = $0 }),
                                    font: .system(size: 12, weight: .medium),
                                    onCommit: { store.renameChapterFolder(folderId, newName: $0, in: projectId) },
                                    onCancel: { renameDraft = nil }
                                )
                            } else {
                                Text(folder.name)
                                    .font(.system(size: 12, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                                    .highPriorityGesture(TapGesture(count: 2).onEnded {
                                        renameDraft = folder.name
                                    })
                            }
                            Spacer()
                            if folderRatio > 0 && !AppLook.tiles {
                                MiniProgressRing(ratio: folderRatio, color: folderRingColor)
                                    .opacity(0.85)
                                    .help("\(Int(folderRatio * 100)) %")
                            }
                            Text("\(allDescendantChapters.count)")
                                .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                        }
                    }
                    .buttonStyle(.pressable)

                    Button { showAddChapter = true } label: {
                        Image(systemName: "plus").font(.system(size: AppLook.fs(10), weight: .semibold)).foregroundColor(.accent)
                            .frame(width: 18, height: 18).background(Color.accent.opacity(0.08))
                            .clipShape(AppLook.buttonShape(4))
                    }
                    .buttonStyle(.pressable)
                    .help("Nouveau chapitre")
                    .accessibilityLabel("Nouveau chapitre")

                    Menu {
                        Button("Renommer") { renameDraft = folder.name }
                        Button("Nouveau sous-dossier…") {
                            newSubfolderName = ""
                            showAddSubfolder = true
                        }
                        if !moveDestinationOptions.isEmpty || folder.parentId != nil {
                            Menu("Déplacer vers") {
                                if folder.parentId != nil {
                                    Button("Racine du projet") {
                                        store.moveChapterFolder(folderId, toParent: nil, in: projectId)
                                    }
                                    Divider()
                                }
                                ForEach(moveDestinationOptions) { dest in
                                    Button(dest.name) {
                                        store.moveChapterFolder(folderId, toParent: dest.id, in: projectId)
                                    }
                                    .disabled(dest.id == folder.parentId)
                                }
                            }
                        }
                        Button("Exporter cette branche…") {
                            if let data = try? store.exportChapterFolderPayload(folderId, in: projectId) {
                                SubtreeIO.exportAndSave(data, suggestedName: folder.name)
                            }
                        }
                        Divider()
                        Button("Supprimer le dossier", role: .destructive) {
                            store.deleteChapterFolder(id: folderId, in: projectId)
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: AppLook.fs(10), weight: .medium)).foregroundColor(.secondary)
                            .frame(width: 18, height: 18)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .help("Options du dossier").modifier(RevealOnRowHover())
                    .accessibilityLabel("Options du dossier")
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: AppLook.r(7, 10))
                        .fill(isDropTarget ? Color.accent.opacity(0.18) : (AppLook.tiles ? Color.clear : Color.primary.opacity(0.03)))   // 5.36
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppLook.r(7, 10))
                        .stroke(isDropTarget ? Color.accent : Color.clear, lineWidth: 1)
                )
                .help(folderTooltip)
                .dropDestination(for: String.self) { items, _ in
                    guard let raw = items.first else { return false }
                    // Réordonnancement de dossiers
                    if raw.hasPrefix("cf:") {
                        guard let srcId = UUID(uuidString: String(raw.dropFirst(3))),
                              srcId != folderId else { return false }
                        store.moveChapterFolderById(srcId, before: folderId, in: projectId)
                        isDropTarget = false
                        return true
                    }
                    // Chapitre(s) déposé(s) dans ce dossier
                    if raw.hasPrefix("ch:") || raw.hasPrefix("chs:") {
                        let srcIds = chapterIdsFromDragPayload(raw)
                        guard !srcIds.isEmpty else { return false }
                        for srcId in srcIds {
                            guard let srcProjectId = store.projectId(containingChapter: srcId) else { continue }
                            if srcProjectId == projectId {
                                store.moveChapterToFolder(srcId, folderId: folderId, in: projectId)
                            } else {
                                store.moveChapterToProject(srcId, from: srcProjectId, to: projectId, folderId: folderId)
                            }
                        }
                        isDropTarget = false
                        return true
                    }
                    return false
                } isTargeted: { targeted in
                    withAppAnimation { isDropTarget = targeted }
                }

                if folder.isExpanded || filterActive {
                    VStack(spacing: 3) {
                        // Sous-dossiers d'abord (récursif)
                        ForEach(visibleSubfolders) { sub in
                            ChapterFolderSidebarRow(
                                store: store,
                                projectId: projectId,
                                folderId: sub.id,
                                sidebarFilter: sidebarFilter,
                                chapterSelection: chapterSelection,
                                onSelectChapter: onSelectChapter,
                                onChapterHistory: onChapterHistory,
                                onEditChapter: onEditChapter
                            )
                            .padding(.leading, 8)
                            .draggable("cf:\(sub.id.uuidString)") {
                                HStack(spacing: 6) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: AppLook.fs(11)))
                                        .foregroundColor(.white)
                                    Text(sub.name).font(.system(size: AppLook.fs(11), weight: .medium))
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.accent.opacity(0.85)).foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                            }
                        }
                        // Chapitres directs
                        if chaptersInFolder.isEmpty && visibleSubfolders.isEmpty {
                            Button { showAddChapter = true } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle").font(.system(size: AppLook.fs(10)))
                                    Text("Ajouter un chapitre")
                                        .font(.system(size: AppLook.fs(10)))
                                        .lineLimit(1)
                                }
                                .foregroundColor(.accent.opacity(0.6)).padding(.leading, 24).padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.pressable)
                        } else {
                            let folderChapterIds = chaptersInFolder.map(\.id)
                            ForEach(chaptersInFolder) { chapter in
                                let isActive = store.data.activeProjectId == projectId && activeChapterId == chapter.id
                                let dragIds = chapterSelection?.dragIds(triggeredBy: chapter.id) ?? [chapter.id]
                                ChapterSidebarRow(
                                    store: store, chapter: chapter, projectId: projectId, isActive: isActive,
                                    selection: chapterSelection,
                                    siblingChapterIds: folderChapterIds,
                                    onSelect: { onSelectChapter(chapter) },
                                    onHistory: { onChapterHistory(chapter) },
                                    onEdit: { onEditChapter(chapter) }
                                )
                                .padding(.leading, 12)
                                .draggable(chapterDragPayload(dragIds)) {
                                    HStack(spacing: 6) {
                                        if let tag = chapter.tag { Circle().fill(tag.color).frame(width: 7, height: 7) }
                                        Text(dragIds.count > 1 ? "\(dragIds.count) chapitres" : chapter.name)
                                            .font(.system(size: AppLook.fs(11), weight: .medium))
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.accentWarm.opacity(0.85)).foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                }
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
            .sheet(isPresented: $showAddSubfolder) {
                FolderFormView(
                    name: $newSubfolderName,
                    title: "Nouveau sous-dossier dans « \(folder.name) »",
                    onSave: {
                        store.addChapterFolder(name: newSubfolderName, to: projectId, parentId: folderId)
                        if !folder.isExpanded { store.toggleChapterFolderExpanded(folderId, in: projectId) }
                        newSubfolderName = ""
                        showAddSubfolder = false
                    },
                    onCancel: { newSubfolderName = ""; showAddSubfolder = false }
                )
            }
            .sheet(isPresented: $showRenameSheet) {
                FolderFormView(
                    name: $renameName,
                    title: "Renommer le dossier",
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
    var selection: ChapterSelectionModel? = nil
    var siblingChapterIds: [UUID] = []
    let onSelect: () -> Void
    let onHistory: () -> Void
    let onEdit: () -> Void
    @State private var showDeleteConfirm = false
    @State private var showStatusPicker = false   // V3.2
    @State private var renameDraft: String? = nil
    @AppStorage("sidebarCompactMode") private var compactStored: Bool = false
    /// 5.29 — en apparence Tuiles, les lignes de chapitre sont toujours compactes.
    private var compactMode: Bool { compactStored || AppLook.tiles }

    private var isMultiSelected: Bool { selection?.isSelected(chapter.id) ?? false }

    private func handleTap() {
        let flags = NSEvent.modifierFlags
        if let sel = selection {
            if flags.contains(.command) {
                sel.toggle(chapter.id, in: projectId)
                return
            }
            if flags.contains(.shift) {
                sel.selectRange(to: chapter.id, in: projectId, allChapterIds: siblingChapterIds)
                return
            }
            sel.selectOnly(chapter.id, in: projectId)
        }
        onSelect()
    }

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
        if chapter.isCompleted || chapter.status == .termine { return Color.accentGreen }
        if let status = chapter.status {
            return Color(hex: status.color)
        }
        return store.statusColor(for: chapter.id, in: projectId, goal: goal)
    }

    private var reviewTooltip: String {
        switch chapter.reviewState {
        case .sent:
            if let d = chapter.daysSinceSent() { return "En relecture · envoyé il y a \(d) j" }
            return "En relecture"
        case .received:  return "Retour reçu — à intégrer"
        default:         return ""
        }
    }

    var body: some View { rowBody.modifier(RowHoverScope()) }   // 5.18 : actions de ligne au survol

    @ViewBuilder private var rowBody: some View {
        Button(action: handleTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if !AppLook.tiles { Circle().fill(statusColor).frame(width: 6, height: 6) }   // 5.33 : statut dans la carte épinglée et au survol
                    // Tag du chapitre
                    if let tag = chapter.tag {
                        Circle().fill(tag.color).frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    // #35 — Priorité haute uniquement (pas polluer pour normale/basse)
                    if chapter.priority == .high && !chapter.isCompleted {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: AppLook.fs(10), weight: .bold))
                            .foregroundColor(Color(hex: "#DC2626"))
                            .help("Priorité haute")
                            .accessibilityLabel("Priorité haute")
                    }
                    if renameDraft != nil {
                        InlineRenameField(
                            text: Binding(get: { renameDraft ?? "" }, set: { renameDraft = $0 }),
                            font: .system(size: 12, weight: isActive ? .semibold : .regular),
                            onCommit: { store.renameChapter(chapter.id, in: projectId, newName: $0) },
                            onCancel: { renameDraft = nil }
                        )
                    } else {
                        Text(chapter.name)
                            .font(.system(size: AppLook.tiles ? 13 : 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(AppLook.tiles && isActive ? .accentWarm : .primary).lineLimit(compactMode ? 1 : 2)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .layoutPriority(1)
                            .truncationMode(.tail)
                            .help(chapter.name)   // 5.19 : titre complet au survol
                            .highPriorityGesture(TapGesture(count: 2).onEnded { renameDraft = chapter.name })
                    }
                    if compactMode && !AppLook.tiles { chapterBadges }   // 5.28 : en vue normale, les badges ont leur propre ligne ; 5.31 : aucun en Tuiles (ils écrasaient le titre)
                    Spacer()
                    if goal > 0 {
                        HStack(spacing: 3) {
                            if !AppLook.tiles { milestoneDots }
                            Text(AppLook.tiles ? "\(percentage) %" : "\(percentage)%")
                                .font(.system(size: AppLook.fs(11), weight: .medium).monospacedDigit())
                                .foregroundColor(AppLook.tiles ? (isActive ? Color.accentWarm : Color.labelMuted) : statusColor)
                                .lineLimit(1)
                        }
                        .fixedSize()   // 5.29 : le pourcentage ne peut plus être écrasé à un chiffre par ligne
                    }
                }

                if !compactMode && hasChapterBadges {
                    HStack(spacing: 5) {
                        chapterBadges
                        Spacer(minLength: 0)
                    }
                }

                if goal > 0 && !compactMode {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(statusColor.opacity(0.15)).frame(height: 3)
                            RoundedRectangle(cornerRadius: 2).fill(statusColor)
                                .frame(width: geo.size.width * ratio, height: 3)
                        }
                    }
                    .frame(height: 3)
                }

                if !compactMode {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(goal > 0
                             ? store.formatCount(latest) + " / " + store.formatCount(goal)
                             : store.formatCount(latest))
                            .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                        if let lastDate = chapter.entries.map(\.date).max(),
                           let parsed = DataStore.parseDate(lastDate) {
                            Text("Modifié " + relativeDate(parsed))
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.labelMuted.opacity(0.6))
                        }
                        if let eta = store.estimatedCompletionDate(for: chapter.id, in: projectId) {
                            let label = projectionLabel(eta)
                            Text("⏱ " + label)
                                .font(.system(size: AppLook.fs(10), weight: .medium))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                        if !chapter.isCompleted, let deadline = chapter.deadline, let date = DataStore.parseDate(deadline) {
                            Text("Échéance : " + DataStore.formatDate(date))
                                .font(.system(size: AppLook.fs(10), weight: .medium))
                                .foregroundColor(.accentWarm.opacity(0.8))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button("Hist.") { onHistory() }
                            .font(.system(size: AppLook.fs(10))).foregroundColor(.accent).buttonStyle(.pressable)
                            .fixedSize()   // 5.29 : idem pour « Hist. »
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
                                        Button("Retirer du dossier") {
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
                            Button(chapter.isArchived ? "Restaurer (sortir de l'archive)" : "Archiver") {
                                store.setChapterArchived(!chapter.isArchived, chapterId: chapter.id, in: projectId)
                            }
                            Button("Supprimer le chapitre", role: .destructive) { showDeleteConfirm = true }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: AppLook.fs(10), weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: AppLook.r(6, 10), style: .continuous)
                                    .fill(Color.primary.opacity(0.07)))
                        }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("Options du chapitre").modifier(RevealOnRowHover())
                        .accessibilityLabel("Options du chapitre")
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
                } // fin if !compactMode
            }
            .padding(compactMode ? 6 : 9)
            .background(
                isMultiSelected ? Color.accentWarm.opacity(0.12)
                : (AppLook.tiles ? (isActive ? Color.primary.opacity(0.07) : Color.clear)
                   : (isActive ? Color.accent.opacity(0.08) : Color.cardBg.opacity(0.7)))
            )
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                .stroke(
                    isMultiSelected ? Color.accentWarm.opacity(0.55)
                    : (AppLook.tiles ? Color.clear : (isActive ? Color.accent.opacity(0.25) : Color.cardBorder)),
                    lineWidth: isMultiSelected ? 1.5 : 1
                ))
        }
        .buttonStyle(.pressable)
        .help(rowTooltip)
        // Clic droit — menu contextuel
        .contextMenu {
            Button("Modifier") { onEdit() }
            // #8 — Duplication : même projet ou autre projet
            Menu("Dupliquer vers…") {
                Button("Ce projet (copie)") {
                    store.duplicateChapter(chapter.id, in: projectId)
                }
                let otherProjects = store.data.projects.filter { !$0.isArchived && $0.id != projectId }
                if !otherProjects.isEmpty {
                    Divider()
                    ForEach(otherProjects) { proj in
                        Button(proj.name) {
                            store.duplicateChapter(chapter.id, from: projectId, to: proj.id)
                        }
                    }
                }
            }
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
                        Button("Retirer du dossier") {
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
            Button(chapter.isPinned ? "Désépingler" : "Épingler en haut") {
                store.toggleChapterPinned(chapter.id, in: projectId)
            }
            Button("Exporter ce chapitre…") {
                if let data = try? store.exportChapterPayload(chapter.id, in: projectId) {
                    SubtreeIO.exportAndSave(data, suggestedName: chapter.name)
                }
            }
            Button(chapter.isArchived ? "Restaurer (sortir de l'archive)" : "Archiver") {
                store.setChapterArchived(!chapter.isArchived, chapterId: chapter.id, in: projectId)
            }
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

    // MARK: - Milestone dots (feature #69)

    /// 5.28 — note, tags, hors total, terminé, relecture, statut : regroupés pour tenir sur une ligne à eux.
    private var hasChapterBadges: Bool {
        chapter.notes != nil || !chapter.customTags.isEmpty || !chapter.countsInThesisTotal || chapter.isCompleted
            || (chapter.reviewState != .notSent && chapter.reviewState != .addressed)
            || (chapter.status != nil && !chapter.isCompleted)
    }

    @ViewBuilder private var chapterBadges: some View {
        if chapter.notes != nil {
            Image(systemName: "note.text")
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted.opacity(0.6))
        }
        // #36 — Tags libres (premiers 2 tags)
        ForEach(chapter.customTags.prefix(2), id: \.self) { tag in
            Text(tag)
                .font(.system(size: AppLook.fs(10), weight: .medium))
                .foregroundColor(.accent)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.accent.opacity(0.1))
                .clipShape(Capsule())
        }
        if !chapter.countsInThesisTotal {
            Image(systemName: "tray.full")
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted.opacity(0.7))
                .help("Hors total de la thèse")
        }
        if chapter.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: AppLook.fs(10))).foregroundColor(.accentGreen)
        }
        // Badge relecture directeur (#1) — visible si un cycle est ouvert
        if chapter.reviewState != .notSent && chapter.reviewState != .addressed {
            Image(systemName: chapter.reviewState.icon)
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(chapter.reviewState.color)
                .help(reviewTooltip)
        }
        // V3.2 — Badge statut
        if let st = chapter.status, !chapter.isCompleted {
            Text(st.label)
                .font(.system(size: AppLook.fs(10), weight: .semibold))
                .foregroundColor(Color(hex: st.color))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color(hex: st.color).opacity(0.15))
                .clipShape(Capsule())
        }
    }

    /// Trois petits ronds (25 % / 50 % / 75 %) remplis en bronze / argent / or selon la progression
    @ViewBuilder
    private var milestoneDots: some View {
        if !chapter.isCompleted && goal > 0 && percentage >= 25 {
            HStack(spacing: 2) {
                ForEach([25, 50, 75], id: \.self) { threshold in
                    Circle()
                        .fill(percentage >= threshold
                              ? milestoneColor(threshold)
                              : Color.labelMuted.opacity(0.18))
                        .frame(width: 4, height: 4)
                }
            }
            .help(milestoneHelp)
        }
    }

    private func milestoneColor(_ threshold: Int) -> Color {
        switch threshold {
        case 25: return Color(hex: "#CD7F32")   // bronze
        case 50: return Color(hex: "#B0B0B8")   // argent
        case 75: return Color(hex: "#F5C518")   // or
        default: return .accentGreen
        }
    }

    private var milestoneHelp: String {
        if percentage >= 75 { return "Palier Or atteint (75 %)" }
        if percentage >= 50 { return "Palier Argent atteint (50 %)" }
        return "Palier Bronze atteint (25 %)"
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "aujourd'hui" }
        if days == 1 { return "hier" }
        if days < 30 { return "il y a \(days) j" }
        return DataStore.formatMonthYear(date)
    }

    /// Tooltip riche au survol du chapitre : statut, progression, dernière modif, deadline.
    private var rowTooltip: String {
        var lines: [String] = [chapter.name]
        if let st = chapter.status, !chapter.isCompleted {
            lines.append("Statut : \(st.label)")
        } else if chapter.isCompleted {
            lines.append("Statut : Terminé")
        }
        if goal > 0 {
            lines.append("Progression : \(store.formatCount(latest)) / \(store.formatCount(goal)) (\(percentage) %)")
        } else if latest > 0 {
            lines.append("Total : \(store.formatCount(latest))")
        }
        if let lastDate = chapter.entries.map(\.date).max(),
           let parsed = DataStore.parseDate(lastDate) {
            lines.append("Dernière saisie : \(relativeDate(parsed))")
        }
        if !chapter.isCompleted, let deadline = chapter.deadline, let date = DataStore.parseDate(deadline) {
            lines.append("Échéance : \(DataStore.formatDate(date))")
        }
        if chapter.priority == .high && !chapter.isCompleted {
            lines.append("Priorité haute")
        }
        return lines.joined(separator: "\n")
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
