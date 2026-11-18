import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    static let navigateToHistory    = Notification.Name("navigateToHistory")
    static let showExport           = Notification.Name("showExport")
    static let pomodoroFocusStarted = Notification.Name("pomodoroFocusStarted")
    static let showAchievements     = Notification.Name("showAchievements")
    static let dashboardSave        = Notification.Name("dashboardSave")        // V5 — ⌘S
    static let dashboardFocusInput  = Notification.Name("dashboardFocusInput")  // V5 — ⌘N
    static let showFocusWriting     = Notification.Name("showFocusWriting")     // V5 — mode immersif
    static let showWritingSprint    = Notification.Name("showWritingSprint")    // V5 — sprint d'écriture
    static let navigateToDashboard  = Notification.Name("navigateToDashboard")  // #51 — Spotlight deep-link
    static let showTodayMode        = Notification.Name("showTodayMode")        // Mode "Aujourd'hui"
    static let showBlockedSession   = Notification.Name("showBlockedSession")   // Mode panne
    static let showSanctuary        = Notification.Name("showSanctuary")        // Mode Sanctuaire
    static let showCooldown         = Notification.Name("showCooldown")         // Cooldown post-session
}

enum NavItem: String, CaseIterable, Identifiable {
    case overview       = "Vue d'ensemble"
    case dashboard      = "Tableau de bord"
    case deadlines      = "Échéances"
    case search         = "Recherche"
    case charts         = "Graphiques"
    case activity       = "Activité"
    case history        = "Historique"
    case calendar       = "Calendrier"
    case timer          = "Minuteur"
    case achievements   = "Accomplissements"
    case kanban         = "Kanban"
    case analytics      = "Statistiques"
    case tableOfContents = "Table des matières"
    case widgets        = "Bibliothèque de widgets"
    case professor      = "Professeur"            // 5.13
    case recaps         = "Récaps du mois"        // 5.26

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview:      return "square.grid.2x2.fill"
        case .dashboard:     return "house.fill"
        case .deadlines:     return "calendar.badge.exclamationmark"
        case .search:        return "magnifyingglass"
        case .charts:        return "chart.line.uptrend.xyaxis"
        case .activity:      return "tablecells.fill"
        case .history:       return "clock.arrow.circlepath"
        case .calendar:      return "calendar"
        case .timer:         return "timer"
        case .achievements:  return "medal.fill"
        case .kanban:            return "rectangle.split.3x1.fill"
        case .analytics:         return "chart.bar.doc.horizontal"
        case .tableOfContents:   return "list.bullet.rectangle"
        case .widgets:           return "square.grid.3x3.square"
        case .professor:         return "graduationcap.fill"
        case .recaps:            return "rectangle.stack.fill"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .overview:     return "⌘1"
        case .dashboard:    return "⌘2"
        case .deadlines:    return "⌘3"
        case .search:       return "⌘4"
        case .charts:       return "⌘5"
        case .activity:     return "⌘6"
        case .history:      return "⌘7"
        case .calendar:     return "⌘8"
        case .timer:        return "⌘9"
        case .achievements: return nil
        case .kanban:           return nil
        case .analytics:        return nil
        case .tableOfContents:  return nil
        case .widgets:          return nil
        case .professor:        return nil
        case .recaps:           return nil
        }
    }
}

struct MainView: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoroController: PomodoroAppController
    @State private var showSidebar: Bool = true
    @State private var selectedNav: NavItem = .dashboard
    @AppStorage("sidebarWidth") private var sidebarWidthStored: Double = 280
    @AppStorage("interfaceMode") private var interfaceMode: String = "VT"   // 5.24 : Tuiles par défaut
    @AppStorage("forceDarkMode") private var forceDarkMode: Bool = false
    @AppStorage("forceLightMode") private var forceLightMode: Bool = false  // 5.24 : clair forcé
    /// 5.26 — page affichée, sortie du corps de la vue (expression principale trop lourde à typer).
    @ViewBuilder private var currentPage: some View {
        switch selectedNav {
        case .overview:
            OverviewView(store: store, showSidebar: $showSidebar, selectedNav: $selectedNav)
        case .dashboard:
            dashboardPage
        case .deadlines:
            DeadlineBoardView(store: store, showSidebar: $showSidebar)
        case .search:
            SearchView(store: store, showSidebar: $showSidebar)
        case .charts, .activity, .history, .calendar, .analytics:
            // 5.15 : regroupées sous « Statistiques », à onglets
            StatsHubView(store: store, showSidebar: $showSidebar, selectedNav: $selectedNav)
        case .timer:
            PomodoroTimerTabView(showSidebar: $showSidebar)
        case .achievements:
            AchievementsView(store: store, showSidebar: $showSidebar)
        case .kanban:
            KanbanView(store: store, showSidebar: $showSidebar)
        case .tableOfContents:
            TableOfContentsView(store: store, showSidebar: $showSidebar)
        case .widgets:
            WidgetLibraryView(store: store, showSidebar: $showSidebar)
        case .professor:
            ProfessorView(store: store, showSidebar: $showSidebar)
        case .recaps:
            MonthlyRecapArchiveView(store: store, showSidebar: $showSidebar)
        }
    }

    /// Sorti du corps de la vue en 5.24 (expression principale trop lourde à typer).
    private func handleAppear() {
        liveSidebarWidth = CGFloat(sidebarWidthStored)
        if !onboardingComplete && store.data.projects.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.4) { showOnboarding = true }
        }
        // Le bilan mensuel est généré uniquement après que load() ait peuplé les
        // projets — garde interne dans `checkAndGenerateMonthlyReport`. Délai
        // pour laisser load() async finir d'abord.
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2.5) {
            store.checkAndGenerateMonthlyReport()
            MonthlyRecap.notifyIfDue(store: store)   // 5.26 — récap du mois écoulé : une notification par mois
        }
    }

    /// Tableau de bord selon l'affichage choisi (VA, VD, ou VT depuis la 5.24).
    /// Sorti du corps de la vue : l'expression principale devenait trop lourde à typer.
    @ViewBuilder private var dashboardPage: some View {
        if interfaceMode == "VD" {
            PaperDashboardView(store: store, showSidebar: $showSidebar)
        } else if interfaceMode == "VT" {
            TilesDashboardView(store: store, showSidebar: $showSidebar)
        } else {
            DashboardView(store: store, showSidebar: $showSidebar)
        }
    }

    /// 5.24 — sombre forcé, clair forcé, ou apparence du système.
    private var preferredScheme: ColorScheme? {
        if forceDarkMode { return .dark }
        return forceLightMode ? .light : nil
    }
    @AppStorage("onboardingComplete") private var onboardingComplete: Bool = false
    // #40 — Raccourcis configurables
    @AppStorage("shortcutFocusKey")  private var shortcutFocusKey:  String = "i"
    @AppStorage("shortcutSprintKey") private var shortcutSprintKey: String = "t"
    @State private var showOnboarding: Bool = false
    @State private var liveSidebarWidth: CGFloat = 280
    @State private var dragStartWidth: CGFloat?
    @State private var isFocusMode: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var showTodayMode: Bool = false
    @State private var showBlockedSession: Bool = false
    @State private var showSanctuary: Bool = false
    @State private var showCooldown: Bool = false
    @State private var focusSessionStartedAt: Date? = nil
    @State private var showExport: Bool = false
    @State private var sidebarHandleHovering = false
    @State private var sidebarHandleDragging = false
    // #58 — Mode présentation
    @State private var showPresentation: Bool = false
    @State private var showPostSessionPrompt: Bool = false
    @State private var showFocusWriting: Bool = false
    @State private var showWritingSprint: Bool = false
    /// #43 — snapshot du progrès au démarrage d'une session focus Pomodoro
    @State private var pomodoroSessionStartProgress: Int = 0
    @State private var pomodoroSessionWasActive: Bool = false

    private let minSidebarWidth: CGFloat = 220
    private let maxSidebarWidth: CGFloat = 420

    private func handlePomodoroSnapshot(_ snapshot: PomodoroTimerSnapshot) {
        if case .running(let mode) = snapshot.phase, mode == .focus, !pomodoroSessionWasActive {
            pomodoroSessionStartProgress = store.dailyProgress
            pomodoroSessionWasActive = true
            focusSessionStartedAt = Date()
        }
        if case .idle = snapshot.phase {
            pomodoroSessionWasActive = false
        }
    }

    // MARK: - Hidden keyboard shortcuts (extracted to reduce type-checker load)

    @ViewBuilder private var hiddenShortcuts: some View {
        // 5.15 : rien d'animé au clavier (gestes répétés cent fois par jour : l'animation les ferait paraître lents)
        Group {
            ForEach(Array(NavItem.allCases.enumerated()), id: \.offset) { idx, item in
                if idx < 9 {
                    Button("") { withoutAnimation { selectedNav = item } }
                        .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(49 + idx)!)), modifiers: .command)
                }
            }
            Button("") {
                withoutAnimation {
                    isFocusMode.toggle()
                    if isFocusMode { showSidebar = false }
                }
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])
            // ⌘Z / ⌘⇧Z : gérés par le menu Édition (CommandGroup .undoRedo dans
            // ThesisTrackerApp) pour ne pas court-circuiter l'annulation des champs texte.
            Button("") { showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
            // ⌘⇧E : géré par la commande de menu « Exporter les données… ».
            Button("") { NotificationCenter.default.post(name: .dashboardSave, object: nil) }
                .keyboardShortcut("s", modifiers: .command)
            Button("") { NotificationCenter.default.post(name: .dashboardFocusInput, object: nil) }
                .keyboardShortcut("n", modifiers: .command)
        }
        Group {
            Button("") { withoutAnimation { showFocusWriting = true } }
                .keyboardShortcut(KeyEquivalent(shortcutFocusKey.first ?? "i"), modifiers: [.command, .shift])
            Button("") { withoutAnimation { showWritingSprint = true } }
                .keyboardShortcut(KeyEquivalent(shortcutSprintKey.first ?? "t"), modifiers: [.command, .shift])
            Button("") { showPresentation = true }
                .keyboardShortcut("p", modifiers: [.option, .command])
            // 5.14 — Professeur en note rapide
            Button("") { ProfessorPanelManager.shared.toggle(store: store) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Button("") { withoutAnimation { showTodayMode = true } }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            // Mode panne : ⌘⇧D (⌘⇧B est réservé à « Accomplissements »)
            Button("") { withoutAnimation { showBlockedSession = true } }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("") { withoutAnimation { showSanctuary = true } }
                .keyboardShortcut("k", modifiers: [.command, .shift, .option])
        }
        .frame(width: 0, height: 0)
        .hidden()
    }

    /// 5.19 — titre de fenêtre : la page, et le temps restant quand un bloc tourne.
    private var windowTitle: String {
        let snap = pomodoroController.timerSnapshot
        guard snap.phase != .idle else { return selectedNav.rawValue }
        let t = pomodoroController.formattedDuration(snap.remainingTime)
        let mode = snap.phase.activeMode == .focus ? "bloc" : "pause"
        return "\(selectedNav.rawValue) — \(mode) \(t)\(snap.phase.isPaused ? ", en pause" : "")"
    }

    private func updateWindowTitle(from data: AppData) {
        let title = data.projects.first(where: { $0.id == data.activeProjectId })?.name ?? "Writing Process"
        NSApp.mainWindow?.title = title
    }

    private func handlePomodoroFocusStarted() {
        if selectedNav == .timer, showSidebar {
            withAppAnimation(.easeOut(duration: 0.15)) { showSidebar = false }
        }
    }

    private func updateWeeklyPomodoroCount(_ data: PomodoroAppData) {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return }
        let count = data.sessions.completedFocusOnly().filter {
            $0.endedAt >= weekInterval.start && $0.endedAt < weekInterval.end
        }.count
        store.setWeeklyPomodoroSessionCount(count)
    }

    private func handleFocusSessionCompleted(_ completed: Bool) {
        guard completed else { return }
        let delta = store.dailyProgress - pomodoroSessionStartProgress
        pomodoroController.sessionWritingDelta = delta > 0 ? delta : nil
        // Cooldown automatique si la session a duré ≥ 45 min
        if let started = focusSessionStartedAt {
            // Durée active (pauses et veille exclues) de la session enregistrée ;
            // à défaut, durée écoulée depuis le démarrage.
            let recorded = pomodoroController.data.sessions
                .filter { $0.kind == .focus && $0.endedAt >= started }
                .max { $0.endedAt < $1.endedAt }
            let duration = recorded?.duration ?? Date().timeIntervalSince(started)
            if duration >= 45 * 60 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAppAnimation(.easeOut(duration: 0.15)) { showCooldown = true }
                }
            }
        }
        focusSessionStartedAt = nil
        pomodoroSessionWasActive = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAppAnimation(.easeOut(duration: 0.15)) {
                self.showPostSessionPrompt = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAppAnimation { self.showPostSessionPrompt = false }
            }
        }
    }

    @ViewBuilder
    private func iCloudConflictBanner(conflict: DataStore.iCloudConflict) -> some View {
        let fmt: DateFormatter = {
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            f.locale = Locale(identifier: "fr_FR"); return f
        }()
        let localEntries  = conflict.localData.projects.flatMap(\.chapters).flatMap(\.entries).count
        let iCloudEntries = conflict.iCloudData.projects.flatMap(\.chapters).flatMap(\.entries).count

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.icloud.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.semOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conflit iCloud détecté")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Deux versions différentes du fichier existent. Laquelle conserver ?")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
                Spacer()
                Button { store.pendingConflict = nil } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11)).foregroundColor(.labelMuted)
                        .padding(5).background(Color.cardBg).clipShape(Circle())
                }
                .buttonStyle(.pressable)
                .help("Fermer l’alerte de conflit")
                .accessibilityLabel("Fermer l’alerte de conflit")
            }

            HStack(spacing: 10) {
                conflictVersionCard(
                    title: "Local",
                    icon: "internaldrive.fill",
                    color: .accent,
                    entries: localEntries,
                    modified: fmt.string(from: conflict.localModified)
                ) { store.resolveConflict(keepLocal: true) }

                conflictVersionCard(
                    title: "iCloud",
                    icon: "icloud.fill",
                    color: Color.semBlue,
                    entries: iCloudEntries,
                    modified: fmt.string(from: conflict.iCloudModified)
                ) { store.resolveConflict(keepLocal: false) }
            }
        }
        .padding(16)
        .frame(maxWidth: 500)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.30), lineWidth: 1))
    }

    @ViewBuilder
    private func conflictVersionCard(title: String, icon: String, color: Color, entries: Int, modified: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12)).foregroundColor(color)
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
            }
            Text("\(entries) entrées").font(.system(size: 11, design: .monospaced)).foregroundColor(.labelMuted)
            Text(modified).font(.system(size: 10)).foregroundColor(.labelMuted)
            Button("Garder \(title)") { action() }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .buttonStyle(.pressable)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.20), lineWidth: 1))
    }

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarView(
                    store: store,
                    selectedNav: $selectedNav,
                    showSidebar: $showSidebar
                )
                .frame(width: liveSidebarWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))

                sidebarResizeHandle
                    .transition(.opacity)
            }

            VStack(spacing: 0) {
                // ── Barre de statut persistante ──────────────────
                StatusBarView(store: store)

                Divider()
                    .overlay(Color.cardBorder)

                ZStack {
                    AppBackdrop().ignoresSafeArea()   // 5.16 : fond à réfracter pour le verre

                    currentPage
                    .id(selectedNav)
                    .transition(.opacity)
                    .appAnimation(.easeInOut(duration: 0.15), value: selectedNav)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .appAnimation(.easeOut(duration: 0.20), value: showSidebar)
        .frame(minWidth: showSidebar ? 720 : 460, minHeight: 560)
        .navigationTitle(windowTitle)   // 5.18 : la fenêtre dit où l'on est ; 5.19 : + minuteur en cours
        .background(AppBackdrop().ignoresSafeArea())   // 5.16 : la barre latérale en verre réfracte le même fond
        .appGlassContainer()                          // 5.16 : verre rendu en commun (performance, fusion des formes)
        .preferredColorScheme(preferredScheme)  // #28 — Slate theme ; 5.24 : clair forcé
        .modifier(AppLookRefresher())           // 5.24 — changer d'affichage redessine toute l'app
        .onAppear(perform: handleAppear)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(store: store, isPresented: $showOnboarding)
                .onDisappear { onboardingComplete = true }
        }
        .overlay(alignment: .top) {
            if isFocusMode {
                HStack {
                    Spacer()
                    Button {
                        withAppAnimation(.easeOut(duration: 0.15)) { isFocusMode = false }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                            Text("Mode focus — ⌘⇧F pour quitter")
                                .font(.system(size: 11))
                                .lineLimit(1)
                        }
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.cardBg.opacity(0.95))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    Spacer()
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(store.$data)                                                        { updateWindowTitle(from: $0) }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHistory))     { _ in withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .history } }
        .onReceive(NotificationCenter.default.publisher(for: .showAchievements))      { _ in withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .achievements } }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroFocusStarted))  { _ in handlePomodoroFocusStarted() }
        .onReceive(pomodoroController.$focusSessionJustCompleted)                     { handleFocusSessionCompleted($0) }
        .onReceive(pomodoroController.$timerSnapshot)                                 { handlePomodoroSnapshot($0) }
        .onReceive(pomodoroController.$data)                                          { updateWeeklyPomodoroCount($0) }
        .onReceive(NotificationCenter.default.publisher(for: .showExport))            { _ in showExport = true }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDashboard))   { _ in withAppAnimation(.easeInOut(duration: 0.2)) { selectedNav = .dashboard } }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTimer))   { _ in withoutAnimation { selectedNav = .timer } }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToProfessor))   { _ in withAppAnimation(.easeInOut(duration: 0.2)) { selectedNav = .professor } }
        .onReceive(store.$showDailySummary) { show in
            // handled via overlay below
        }
        // Daily summary overlay
        .overlay {
            if store.showDailySummary {
                DailySummaryOverlay(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(99)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: store.showDailySummary)
        // Weekly summary overlay
        .overlay {
            if store.showWeeklySummary {
                WeeklySummaryOverlay(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(97)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: store.showWeeklySummary)
        // Milestone toast
        .overlay(alignment: .bottom) {
            if let milestone = store.pendingMilestone {
                MilestoneToastView(milestone: milestone) {
                    store.dismissMilestone()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(98)
                .padding(.bottom, 28)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: store.pendingMilestone != nil)

        // Post-session writing prompt
        .overlay(alignment: .bottom) {
            if showPostSessionPrompt {
                PostSessionPromptView(store: store) {
                    withAppAnimation { showPostSessionPrompt = false }
                    QuickEntryPanelManager.shared.show(store: store)
                } onDismiss: {
                    withAppAnimation { showPostSessionPrompt = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(96)
                .padding(.bottom, 28)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: showPostSessionPrompt)

        // #31 — Rapport hebdomadaire automatique le lundi
        .overlay(alignment: .bottom) {
            if store.showWeeklyReportPrompt {
                WeeklyReportPromptBanner(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(95)
                    .padding(.bottom, 28)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: store.showWeeklyReportPrompt)

        // #70 — iCloud conflict resolution
        .overlay(alignment: .bottom) {
            if let conflict = store.pendingConflict {
                iCloudConflictBanner(conflict: conflict)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(96)
                    .padding(.bottom, store.showWeeklyReportPrompt ? 100 : 28)
            }
        }
        .appAnimation(.easeOut(duration: 0.22), value: store.pendingConflict != nil)

        // V5 — Overlays immersifs : mode focus (⌘⇧I) et sprint (⌘⇧T)
        .overlay { immersiveOverlays }
        .onReceive(NotificationCenter.default.publisher(for: .showFocusWriting)) { _ in
            withAppAnimation(.easeOut(duration: 0.15)) { showFocusWriting = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showWritingSprint)) { _ in
            withAppAnimation(.easeOut(duration: 0.15)) { showWritingSprint = true }
        }

        // Command Palette (Cmd+K)
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    store: store,
                    isPresented: $showCommandPalette,
                    onNavigate: { nav in
                        withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = nav }
                    },
                    onSelectProject: { project in
                        store.data.activeProjectId = project.id
                        store.save()
                        withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .zIndex(100)
            }
        }
        .appAnimation(.easeOut(duration: 0.15), value: showCommandPalette)
        .background(hiddenShortcuts)
        .sheet(isPresented: $showExport) {
            ExportView(store: store)
        }
        // #58 — Mode présentation (⌥⌘P)
        .sheet(isPresented: $showPresentation) {
            PresentationModeView(store: store)
        }
        .modifier(BlockedSessionAndTodayHooks(
            store: store,
            showBlockedSession: $showBlockedSession,
            showTodayMode: $showTodayMode,
            showWritingSprint: $showWritingSprint,
            showCommandPalette: $showCommandPalette,
            showSanctuary: $showSanctuary,
            showCooldown: $showCooldown,
            selectedNav: $selectedNav
        ))
    }

    // V5 — Mode focus + sprint : extraits pour éviter l'explosion de type-checking du body
    @ViewBuilder private var immersiveOverlays: some View {
        if showFocusWriting {
            FocusWritingView(store: store) {
                withAppAnimation(.easeOut(duration: 0.15)) { showFocusWriting = false }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            .zIndex(101)
        }
        if showTodayMode {
            TodayModeView(
                store: store,
                onDismiss: { withAppAnimation(.easeOut(duration: 0.15)) { showTodayMode = false } },
                onStartFocus: { withAppAnimation(.easeOut(duration: 0.15)) { showFocusWriting = true } },
                onOpenDashboard: { withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard } }
            )
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            .zIndex(103)
        }
        if showSanctuary {
            SanctuaryModeView(store: store) {
                withAppAnimation(.easeOut(duration: 0.15)) { showSanctuary = false }
            }
            .transition(.opacity)
            .zIndex(104)
        }
        if showWritingSprint {
            WritingSprintView(store: store) {
                withAppAnimation(.easeOut(duration: 0.15)) { showWritingSprint = false }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            .zIndex(102)
        }
    }

    private var sidebarResizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 12)
            .overlay(
                Capsule()
                    .fill(
                        sidebarHandleDragging
                            ? Color.accent.opacity(0.7)
                            : sidebarHandleHovering
                                ? Color.accent.opacity(0.45)
                                : Color.cardBorder.opacity(0.7)
                    )
                    .frame(width: sidebarHandleHovering || sidebarHandleDragging ? 4 : 3)
                    .appAnimation(.easeInOut(duration: 0.15), value: sidebarHandleHovering)
                    .appAnimation(.easeInOut(duration: 0.1), value: sidebarHandleDragging)
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                sidebarHandleHovering = hovering
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        sidebarHandleDragging = true
                        if dragStartWidth == nil { dragStartWidth = liveSidebarWidth }
                        let base = dragStartWidth ?? liveSidebarWidth
                        liveSidebarWidth = min(max(minSidebarWidth, base + value.translation.width), maxSidebarWidth)
                    }
                    .onEnded { _ in
                        sidebarHandleDragging = false
                        dragStartWidth = nil
                        sidebarWidthStored = Double(liveSidebarWidth)
                    }
            )
            .help("Redimensionner la barre latérale")
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @ObservedObject var store: DataStore
    /// 5.18 : pages, vitesse et hebdo affichés sur demande (chevron) ; série, aujourd'hui, chapitre toujours.
    @AppStorage("statusBarExpanded") private var expanded = false
    @ObservedObject private var notifStore: AppNotificationStore = .shared
    @State private var syncRotation: Double = 0
    @State private var copiedFeedback: Bool = false
    @State private var showNotificationCenter: Bool = false

    private func chapterHelp(_ chapter: Chapter) -> String {
        let latest = store.latestTotal(for: chapter.id, in: store.data.activeProjectId ?? UUID())
        let pct = chapter.goal > 0 ? min(100, Int(Double(latest) / Double(chapter.goal) * 100)) : 0
        return "\(chapter.name) : \(store.formatCount(latest)) sur \(store.formatCount(chapter.goal)) (\(pct) %)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // #42 — Indicateur iCloud discret
            if store.isUsingICloud {
                sbItem {
                    HStack(spacing: 5) {
                        if store.iCloudSyncActive {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.accent)
                                .rotationEffect(.degrees(syncRotation))
                                .onAppear {
                                    withAppAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                        syncRotation = 360
                                    }
                                }
                                .onDisappear { syncRotation = 0 }
                        } else {
                            Image(systemName: "checkmark.icloud")
                                .font(.system(size: 10))
                                .foregroundColor(.accentGreen.opacity(0.7))
                        }
                        Text("iCloud")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                }
                .appAnimation(Motion.quick, value: store.iCloudSyncActive)
            }

            // Streak
            sbItem {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.currentStreak > 0 ? Color.accentGreen : Color.cardBorder)
                        .frame(width: 5, height: 5)
                        .shadow(color: store.currentStreak > 0 ? Color.accentGreen.opacity(0.7) : .clear, radius: 4)
                    if store.currentStreak > 0 {
                        Text("Série active")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(store.currentStreak) j")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    } else {
                        Text("Pas de série")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                }
            }

            // 5.12 — pages de thèse rédigées (5.18 : sur demande)
            if expanded, let pages = store.pagesNumber(store.thesisWrittenChars, digits: 0), store.thesisWrittenChars > 0 {
                sbItem {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundColor(.accent)
                        Text("\(pages) p. thèse")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .help(store.pageCalibrationLabel.map { "Pages de thèse rédigées (\($0))" } ?? "Pages de thèse rédigées")
            }

            // #54 — Aujourd'hui / objectif journalier
            if store.effectiveDailyGoal > 0 || store.dailyProgress > 0 {
                sbItem {
                    let today = store.dailyProgress
                    let goal  = store.effectiveDailyGoal
                    let done  = goal > 0 && today >= goal
                    HStack(spacing: 5) {
                        Image(systemName: done ? "checkmark.circle.fill" : "pencil")
                            .font(.system(size: 10, weight: done ? .semibold : .regular))
                            .foregroundColor(done ? .accentGreen : .accent)
                        Text("Aujourd'hui")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text(store.formatCount(today))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(done ? .accentGreen : .primary)
                        if goal > 0 {
                            Text("/")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                            Text(store.formatCount(goal))
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                    }
                }
            }

            // Velocity (5.18 : sur demande)
            if expanded { sbItem {
                HStack(spacing: 5) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.accentWarm)
                    Text("Vitesse")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                    Text(store.formatCount(store.velocity14Days) + "/j")
                        .font(.system(size: 11, weight: .semibold))
                }
            } }

            // Weekly (5.18 : sur demande)
            if expanded && store.data.weeklyGoal > 0 {
                sbItem {
                    let written = store.weeklyProgress
                    let goal = store.data.weeklyGoal
                    let pct = goal > 0 ? min(100, Int(Double(written) / Double(goal) * 100)) : 0
                    HStack(spacing: 5) {
                        Image(systemName: "target")
                            .font(.system(size: 10))
                            .foregroundColor(.accentWarm)
                        Text("Hebdo")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text(store.formatCount(written))
                            .font(.system(size: 11, weight: .semibold))
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text("\(pct)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(pct >= 100 ? .accentGreen : .accentWarm)
                    }
                }
            }

            // Active chapter
            if let chapter = store.activeChapter, chapter.goal > 0 {
                sbItem {
                    let latest = store.latestTotal(for: chapter.id, in: store.data.activeProjectId ?? UUID())
                    let pct = min(100, Int(Double(latest) / Double(chapter.goal) * 100))
                    HStack(spacing: 5) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentWarm.opacity(0.7))
                        Text(chapter.shortLabel)   // 5.19 : titres longs → « Ch. 4 »
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1)
                        Text("\(pct)%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(pct >= 100 ? .accentGreen : .primary)
                    }
                }
                .help(chapterHelp(chapter))   // 5.18
            }

            // 5.18 : afficher / masquer les indicateurs secondaires
            Button { withAppAnimation(Motion.quick) { expanded.toggle() } } label: {
                Image(systemName: expanded ? "chevron.left" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .frame(width: 22, height: 33)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help(expanded ? "Masquer pages, vitesse et hebdo" : "Afficher pages, vitesse et hebdo")
            .accessibilityLabel(expanded ? "Masquer les indicateurs secondaires" : "Afficher les indicateurs secondaires")

            Spacer()

            // ETA deadline
            if let eta = store.estimatedCompletionDate(for: store.data.activeProjectId ?? UUID()) {
                let days = Calendar.current.dateComponents([.day], from: Date(), to: eta).day ?? 0
                HStack(spacing: 6) {
                    Text("Fin estimée")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                    Text(DataStore.formatDate(eta))
                        .font(.system(size: 11, weight: .semibold))
                    if days >= 0 {
                        Text("\(days) j")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentWarm)
                            .padding(.horizontal, 6).padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(Color.accentWarm.opacity(0.10))
                                    .overlay(Capsule().stroke(Color.accentWarm.opacity(0.20), lineWidth: 1))
                            )
                    }
                }
                .padding(.horizontal, 13)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.cardBorder).frame(width: 1)
                }
            }

            // Cloche centre de notifications
            Button { showNotificationCenter.toggle() } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: notifStore.unreadCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(notifStore.unreadCount > 0 ? .accent : .labelMuted)
                        .symbolRenderingMode(notifStore.unreadCount > 0 ? .multicolor : .monochrome)
                }
                .padding(.horizontal, 10)
                .frame(height: 33)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("Centre de notifications")
            .accessibilityLabel("Centre de notifications")
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.cardBorder).frame(width: 1)
            }
            .popover(isPresented: $showNotificationCenter, arrowEdge: .bottom) {
                NotificationCenterView()
                    .preferredColorScheme(nil)
            }

            // #30 — Bouton copier le résumé du jour
            Button { copyDailySummary() } label: {
                HStack(spacing: 4) {
                    Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(copiedFeedback ? .accentGreen : .labelMuted)
                    if copiedFeedback {
                        Text("Copié !")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentGreen)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 33)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .help("Copier le résumé du jour dans le presse-papier")
            .appAnimation(.easeInOut(duration: 0.2), value: copiedFeedback)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.cardBorder).frame(width: 1)
            }
        }
        .frame(height: 33)
        // 5.25 — en Tuiles : barre flottante arrondie
        .clipShape(AppLook.panelShape(16))
        .appGlass(in: AppLook.panelShape(16), fallback: .sidebarBg)   // 5.16 : verre (5.15 : matériau de barre)
        .padding(.horizontal, AppLook.tiles ? 12 : 0)
        .padding(.top, AppLook.tiles ? 10 : 0)
        .padding(.bottom, AppLook.tiles ? 6 : 0)
    }

    private func copyDailySummary() {
        let todayDelta = store.dailyProgress
        var parts: [String] = ["+\(store.formatCount(todayDelta))"]

        if let chapter = store.activeChapter {
            parts.append(chapter.shortLabel)
            if chapter.goal > 0 {
                let latest = store.chapterProgress
                let pct = min(100, Int(Double(latest) / Double(chapter.goal) * 100))
                parts.append("\(pct)%")
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: " · "), forType: .string)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedFeedback = false }
    }

    private func sbItem<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .frame(height: 33)
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.cardBorder).frame(width: 1)
            }
    }
}

// MARK: - Weekly Summary Overlay

struct WeeklySummaryOverlay: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoroController: PomodoroAppController

    private var stats: (chars: Int, activeDays: Int, bestDay: Int, topProject: String?) {
        store.prevWeekStats
    }

    private var pomodoroWeekStats: (sessions: Int, focusMinutes: Int) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart),
              let prevEnd = cal.date(byAdding: .day, value: 7, to: prevStart)
        else { return (0, 0) }
        let sessions = pomodoroController.data.sessions.filter {
            $0.startedAt >= prevStart && $0.startedAt < prevEnd && $0.kind == .focus && $0.completionState == .completed
        }
        let focusMinutes = Int(sessions.reduce(0) { $0 + $1.duration } / 60)
        return (sessions.count, focusMinutes)
    }

    private var prevWeekChallenge: WeeklyChallenge? {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let prevDate = cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: prevDate)
        let key = String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
        return store.data.weeklyChallenges.first { $0.weekKey == key }
    }

    private var weekLabel: String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let prevStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart),
              let prevEnd   = cal.date(byAdding: .day, value: 6, to: prevStart) else {
            return "Semaine passée"
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        return "\(fmt.string(from: prevStart)) – \(fmt.string(from: prevEnd))"
    }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.accentWarm.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: "calendar.badge.checkmark")
                                .font(.system(size: 15))
                                .foregroundColor(.accentWarm)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Récap de la semaine")
                                .font(.system(size: 15, weight: .bold, design: AppLook.fontDesign))
                                .foregroundColor(.primary)
                            Text(weekLabel)
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Button {
                            withAppAnimation { store.dismissWeeklySummary() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.labelMuted)
                                .padding(6)
                                .background(Color.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        .help("Fermer le résumé hebdomadaire")
                        .accessibilityLabel("Fermer le résumé hebdomadaire")
                    }

                    Divider()

                    HStack(spacing: 16) {
                        weekPill(icon: "text.cursor",
                                 value: store.formatCount(stats.chars),
                                 label: "écrits")
                        weekPill(icon: "flame.fill",
                                 value: "\(stats.activeDays) j",
                                 label: "actifs")
                        weekPill(icon: "bolt.fill",
                                 value: store.formatCount(stats.bestDay),
                                 label: "record")
                        if let proj = stats.topProject {
                            weekPill(icon: "folder.fill", value: proj, label: "top projet")
                        }
                    }
                    let pStats = pomodoroWeekStats
                    if pStats.sessions > 0 {
                        Divider()
                        HStack(spacing: 16) {
                            weekPill(icon: "timer",
                                     value: "\(pStats.sessions)",
                                     label: "sessions")
                            weekPill(icon: "brain.head.profile",
                                     value: "\(pStats.focusMinutes) min",
                                     label: "concentration")
                        }
                    }

                    // Défi de la semaine passée
                    if let prevChallenge = prevWeekChallenge {
                        Divider()
                        HStack(spacing: 10) {
                            Image(systemName: prevChallenge.isCompleted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(prevChallenge.isCompleted ? Color.semGreen : .labelMuted)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Défi \(prevChallenge.isCompleted ? "relevé" : "non relevé") — \(prevChallenge.kind.displayName)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)
                                let prog = store.challengeProgress(prevChallenge)
                                Text("\(prog) / \(prevChallenge.target) \(prevChallenge.kind.unit)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(prevChallenge.isCompleted
                                    ? Color.semGreen.opacity(0.08)
                                    : Color.fieldBg)
                        )
                    }
                }
                .padding(18)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.cardBg)
                        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: -2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentWarm.opacity(0.25), lineWidth: 1)
                )
                Spacer()
            }
            .padding(.bottom, 20)
        }
        .ignoresSafeArea()
    }

    private func weekPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentWarm)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: AppLook.fontDesign))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Daily Summary Overlay

struct DailySummaryOverlay: View {
    @ObservedObject var store: DataStore

    private var stats: (chars: Int, projects: Int, topProject: String?) { store.todayStats }

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    // Header
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().fill(Color.accent.opacity(0.15)).frame(width: 36, height: 36)
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.accent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bilan du jour")
                                .font(.system(size: 15, weight: .bold, design: AppLook.fontDesign))
                                .foregroundColor(.primary)
                            Text(DataStore.formatLongDate(Date(), capitalize: true))
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Button {
                            withAppAnimation { store.dismissDailySummary() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.labelMuted)
                                .padding(6)
                                .background(Color.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        .help("Fermer le résumé du jour")
                        .accessibilityLabel("Fermer le résumé du jour")
                    }

                    Divider()

                    // Stats
                    HStack(spacing: 20) {
                        statPill(
                            icon: "text.cursor",
                            value: store.formatCount(stats.chars),
                            label: "écrits"
                        )
                        if let goal = store.data.dailyGoal > 0 ? store.data.dailyGoal : nil {
                            let pct = min(100, Int(Double(stats.chars) / Double(goal) * 100))
                            statPill(
                                icon: "target",
                                value: "\(pct)%",
                                label: "de l'objectif"
                            )
                        }
                        if let proj = stats.topProject {
                            statPill(icon: "folder.fill", value: proj, label: "meilleur projet")
                        }
                        if store.currentStreak > 1 {
                            statPill(
                                icon: "flame.fill",
                                value: "\(store.currentStreak) jours",
                                label: "de suite"
                            )
                        }
                    }
                }
                .padding(18)
                .frame(width: 420)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.cardBg)
                        .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: -2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.cardBorder, lineWidth: 1)
                )

                Spacer()
            }
            .padding(.bottom, 20)
        }
        .ignoresSafeArea()
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accent)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: AppLook.fontDesign))
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Milestone Toast

struct MilestoneToastView: View {
    let milestone: DataStore.MilestoneType
    let onDismiss: () -> Void

    @State private var haloScale: CGFloat = 0.6
    @State private var haloOpacity: Double = 0.7
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0

    private struct BadgeInfo {
        let icon: String
        let color: Color
        let name: String
        let subtitle: String
    }

    private static func badgeInfo(for n: Int) -> BadgeInfo {
        switch n {
        case 3:   return BadgeInfo(icon: "flame",         color: .accent,                                              name: "Étincelle",    subtitle: "3 jours consécutifs — tu commences bien.")
        case 7:   return BadgeInfo(icon: "flame.fill",    color: Color.semAmber,        name: "Régulier",     subtitle: "Une semaine complète. Beau rythme.")
        case 14:  return BadgeInfo(icon: "star.fill",     color: Color.semOrange,        name: "Persévérant",  subtitle: "Deux semaines — la régularité paie.")
        case 30:  return BadgeInfo(icon: "bolt.fill",     color: Color.semRed,        name: "Acharné",      subtitle: "Un mois d'écriture continue. Impressionnant.")
        case 60:  return BadgeInfo(icon: "crown.fill",    color: Color.semViolet,        name: "Légende",      subtitle: "Deux mois sans interruption. Remarquable.")
        case 100: return BadgeInfo(icon: "trophy.fill",   color: .accentWarm,                                         name: "Immortel",     subtitle: "100 jours. Performance exceptionnelle.")
        case 200: return BadgeInfo(icon: "shield.fill",   color: Color.semPurple,        name: "Titan",        subtitle: "200 jours de suite. Un mental d'acier.")
        case 365: return BadgeInfo(icon: "rosette",       color: Color.semPink,        name: "Année pleine", subtitle: "Une année entière sans rupture. Légendaire.")
        default:  return BadgeInfo(icon: "flame.fill",    color: .accent,                                             name: "\(n) jours",   subtitle: "Continue comme ça.")
        }
    }

    private static func volumeInfo(for n: Int) -> (name: String, icon: String, color: Color) {
        switch n {
        case 100_000:    return ("100\u{202F}000 caractères", "seal.fill",       Color.semAmber)
        case 500_000:    return ("500\u{202F}000 caractères", "crown.fill",      Color.semViolet)
        case 1_000_000:  return ("1 million de caractères",   "trophy.fill",     Color.semYellow)
        case 2_000_000:  return ("2 millions de caractères",  "medal.fill",      Color.semOrange)
        case 5_000_000:  return ("5 millions de caractères",  "laurel.leading",  Color.semPurple)
        default:         return ("\(n) caractères",           "sparkles",        .accent)
        }
    }

    private var icon: String {
        switch milestone {
        case .streak(let n):              return MilestoneToastView.badgeInfo(for: n).icon
        case .chapterComplete:            return "checkmark.seal.fill"
        case .challengeComplete(let k):   return k.icon
        case .volumeMilestone(let n):     return MilestoneToastView.volumeInfo(for: n).icon
        case .projectPercent(_, let pct): return pct >= 100 ? "trophy.circle.fill" : "chart.pie.fill"
        case .firstChapterCompleted:      return "checkmark.seal.fill"
        case .dailyRecord:                return "bolt.fill"
        }
    }

    private var iconColor: Color {
        switch milestone {
        case .streak(let n):              return MilestoneToastView.badgeInfo(for: n).color
        case .chapterComplete:            return .accentGreen
        case .challengeComplete:          return Color.semGreen
        case .volumeMilestone(let n):     return MilestoneToastView.volumeInfo(for: n).color
        case .projectPercent(_, let pct):
            if pct >= 100 { return Color.semOrange }
            if pct >= 75  { return Color.semViolet }
            return Color.semSky
        case .firstChapterCompleted:      return .accentGreen
        case .dailyRecord:                return Color.semRed
        }
    }

    private var title: String {
        switch milestone {
        case .streak(let n):
            return "Badge « \(MilestoneToastView.badgeInfo(for: n).name) » débloqué !"
        case .chapterComplete:
            return "Chapitre terminé !"
        case .challengeComplete:
            return "Défi hebdomadaire relevé ! 🎯"
        case .volumeMilestone(let n):
            return "Cap des \(MilestoneToastView.volumeInfo(for: n).name) franchi !"
        case .projectPercent(_, let pct):
            return pct >= 100 ? "Projet complété ! 🏆" : "\(pct) % du projet atteint !"
        case .firstChapterCompleted:
            return "Premier chapitre terminé !"
        case .dailyRecord:
            return "Nouveau record personnel ! ⚡️"
        }
    }

    private var subtitle: String {
        switch milestone {
        case .streak(let n):
            return MilestoneToastView.badgeInfo(for: n).subtitle
        case .chapterComplete(let name):
            return "\(name) — objectif atteint."
        case .challengeComplete(let kind):
            return "Tu as complété le défi « \(kind.displayName) » cette semaine."
        case .volumeMilestone:
            return "Une étape symbolique dans ton parcours d'écriture."
        case .projectPercent(let name, _):
            return "Projet « \(name) »."
        case .firstChapterCompleted(let projectName):
            return "Premier jalon validé pour « \(projectName) »."
        case .dailyRecord(let n):
            return "\(n.formatted()) caractères en une journée — meilleur jour à ce jour."
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                // Halo ring — expands and fades on appear (#24)
                Circle()
                    .stroke(iconColor.opacity(0.4), lineWidth: 2)
                    .frame(width: 38, height: 38)
                    .scaleEffect(haloScale)
                    .opacity(haloOpacity)
                // Icon background
                Circle().fill(iconColor.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: AppLook.fontDesign))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .padding(5)
                    .background(Color.fieldBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(iconColor.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            // Icon bounce in
            withAppAnimation(.easeOut(duration: 0.22)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            // Halo expand + fade
            withAppAnimation(.easeOut(duration: 0.9)) {
                haloScale = 2.2
                haloOpacity = 0
            }
        }
    }
}

// MARK: - Post-Session Writing Prompt (#13)

struct PostSessionPromptView: View {
    @ObservedObject var store: DataStore
    let onLog: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.accentWarm.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentWarm)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Session focus terminée")
                    .font(.system(size: 14, weight: .bold, design: AppLook.fontDesign))
                    .foregroundColor(.primary)
                Text("Tu as écrit combien de caractères ?")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button("Saisir") {
                onLog()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.accent)
            .clipShape(Capsule())
            .buttonStyle(.pressable)

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .padding(5)
                    .background(Color.fieldBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 400)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.accentWarm.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - Weekly Report Prompt Banner (#31)

struct WeeklyReportPromptBanner: View {
    @ObservedObject var store: DataStore
    @State private var showExport: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 20))
                .foregroundColor(Color.semBlue)
                .frame(width: 36, height: 36)
                .background(Color.semBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("Rapport hebdomadaire disponible")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Générez le PDF de la semaine écoulée")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }

            Spacer()

            Button {
                showExport = true
            } label: {
                Text("Télécharger")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.semBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.pressable)

            Button { store.dismissWeeklyReportPrompt() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .padding(6)
                    .background(Color.cardBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: 440)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.semBlue.opacity(0.22), lineWidth: 1))
        .sheet(isPresented: $showExport) {
            ExportView(store: store)
        }
    }
}
