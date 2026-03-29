import SwiftUI

// MARK: - Notification names

extension Notification.Name {
    static let navigateToHistory    = Notification.Name("navigateToHistory")
    static let showExport           = Notification.Name("showExport")
    static let pomodoroFocusStarted = Notification.Name("pomodoroFocusStarted")
    static let showAchievements     = Notification.Name("showAchievements")
}

enum NavItem: String, CaseIterable, Identifiable {
    case overview       = "Vue d'ensemble"
    case dashboard      = "Tableau de bord"
    case deadlines      = "Echeances"
    case search         = "Recherche"
    case charts         = "Graphiques"
    case activity       = "Activité"
    case history        = "Historique"
    case calendar       = "Calendrier"
    case timer          = "Minuteur"
    case achievements   = "Accomplissements"
    case kanban         = "Kanban"
    case timeline       = "Timeline"

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
        case .kanban:        return "rectangle.split.3x1.fill"
        case .timeline:      return "calendar.day.timeline.left"
        }
    }
}

struct MainView: View {
    @ObservedObject var store: DataStore
    @State private var showSidebar: Bool = true
    @State private var selectedNav: NavItem = .dashboard
    @AppStorage("sidebarWidth") private var sidebarWidthStored: Double = 280
    @AppStorage("interfaceMode") private var interfaceMode: String = "VA"
    @State private var liveSidebarWidth: CGFloat = 280
    @State private var dragStartWidth: CGFloat?
    @State private var isFocusMode: Bool = false
    @State private var showCommandPalette: Bool = false
    @State private var showExport: Bool = false
    @State private var showFocusEntry: Bool = false
    @State private var sidebarHandleHovering = false
    @State private var sidebarHandleDragging = false

    private let minSidebarWidth: CGFloat = 220
    private let maxSidebarWidth: CGFloat = 420

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

            ZStack {
                Color.appBg.ignoresSafeArea()

                Group {
                    switch selectedNav {
                    case .overview:
                        OverviewView(store: store, showSidebar: $showSidebar, selectedNav: $selectedNav)
                    case .dashboard:
                        if interfaceMode == "VD" {
                            PaperDashboardView(store: store, showSidebar: $showSidebar)
                        } else {
                            DashboardView(store: store, showSidebar: $showSidebar)
                        }
                    case .deadlines:
                        DeadlineBoardView(store: store, showSidebar: $showSidebar)
                    case .search:
                        SearchView(store: store, showSidebar: $showSidebar)
                    case .charts:
                        ChartView(store: store, showSidebar: $showSidebar)
                    case .activity:
                        HeatmapView(store: store, showSidebar: $showSidebar)
                    case .history:
                        HistoryListView(store: store, showSidebar: $showSidebar)
                    case .calendar:
                        CalendarView(store: store, showSidebar: $showSidebar)
                    case .timer:
                        PomodoroTimerTabView(showSidebar: $showSidebar)
                    case .achievements:
                        AchievementsView(store: store, showSidebar: $showSidebar)
                    case .kanban:
                        KanbanView(store: store, showSidebar: $showSidebar)
                    case .timeline:
                        TimelineView(store: store, showSidebar: $showSidebar)
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.18), value: selectedNav)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.88), value: showSidebar)
        .frame(minWidth: showSidebar ? 720 : 460, minHeight: 560)
        .onAppear { liveSidebarWidth = CGFloat(sidebarWidthStored) }
        .overlay(alignment: .top) {
            if isFocusMode {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { isFocusMode = false }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 10))
                            Text("Mode focus — ⌘⇧F pour quitter")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.cardBg.opacity(0.95))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(store.$data) { data in
            let title = data.projects.first(where: { $0.id == data.activeProjectId })?.name ?? "Writing Process"
            NSApp.mainWindow?.title = title
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHistory)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .history }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAchievements)) { _ in
            withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .achievements }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pomodoroFocusStarted)) { _ in
            if selectedNav == .timer, showSidebar {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) { showSidebar = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showExport)) { _ in
            showExport = true
        }
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.showDailySummary)
        // Weekly summary overlay
        .overlay {
            if store.showWeeklySummary {
                WeeklySummaryOverlay(store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(97)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.showWeeklySummary)
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
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.pendingMilestone != nil)

        // Command Palette (Cmd+K)
        .overlay {
            if showCommandPalette {
                CommandPaletteView(
                    store: store,
                    isPresented: $showCommandPalette,
                    onNavigate: { nav in
                        withAnimation(.easeInOut(duration: 0.15)) { selectedNav = nav }
                    },
                    onSelectProject: { project in
                        store.data.activeProjectId = project.id
                        store.save()
                        withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: showCommandPalette)
        // Hidden keyboard shortcuts
        .background(
            Group {
                ForEach(Array(NavItem.allCases.enumerated()), id: \.offset) { idx, item in
                    if idx < 9 {
                        Button("") { withAnimation(.easeInOut(duration: 0.15)) { selectedNav = item } }
                            .keyboardShortcut(KeyEquivalent(Character(UnicodeScalar(49 + idx)!)), modifiers: .command)
                    }
                }
                Button("") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        isFocusMode.toggle()
                        if isFocusMode { showSidebar = false }
                    }
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                // Undo / Redo
                Button("") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)

                // Command Palette
                Button("") { showCommandPalette = true }
                    .keyboardShortcut("k", modifiers: .command)

                // Export
                Button("") { showExport = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])

                // Mode Élan
                Button("") { showFocusEntry = true }
                    .keyboardShortcut("e", modifiers: [.command, .option])
            }
            .frame(width: 0, height: 0)
            .hidden()
        )
        .sheet(isPresented: $showExport) {
            ExportView(store: store)
        }
        .sheet(isPresented: $showFocusEntry) {
            FocusEntryView(store: store)
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
                    .animation(.easeInOut(duration: 0.15), value: sidebarHandleHovering)
                    .animation(.easeInOut(duration: 0.1), value: sidebarHandleDragging)
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
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text(weekLabel)
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Button {
                            withAnimation { store.dismissWeeklySummary() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.labelMuted)
                                .padding(6)
                                .background(Color.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
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
                                .foregroundColor(prevChallenge.isCompleted ? Color(red: 0.220, green: 0.753, blue: 0.439) : .labelMuted)
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
                                    ? Color(red: 0.220, green: 0.753, blue: 0.439).opacity(0.08)
                                    : Color.fieldBg)
                        )
                    }
                }
                .padding(18)
                .frame(width: 440)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.cardBg)
                        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: -4)
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
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
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text(DataStore.formatLongDate(Date(), capitalize: true))
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Button {
                            withAnimation { store.dismissDailySummary() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.labelMuted)
                                .padding(6)
                                .background(Color.cardBg)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
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
                        .shadow(color: .black.opacity(0.18), radius: 20, x: 0, y: -4)
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
                .font(.system(size: 13, weight: .bold, design: .rounded))
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

    private struct BadgeInfo {
        let icon: String
        let color: Color
        let name: String
        let subtitle: String
    }

    private static func badgeInfo(for n: Int) -> BadgeInfo {
        switch n {
        case 3:   return BadgeInfo(icon: "flame",         color: .accent,                                              name: "Étincelle",    subtitle: "3 jours consécutifs — tu commences bien.")
        case 7:   return BadgeInfo(icon: "flame.fill",    color: Color(red: 0.961, green: 0.620, blue: 0.043),        name: "Régulier",     subtitle: "Une semaine complète. Beau rythme.")
        case 14:  return BadgeInfo(icon: "star.fill",     color: Color(red: 0.961, green: 0.455, blue: 0.114),        name: "Persévérant",  subtitle: "Deux semaines — la régularité paie.")
        case 30:  return BadgeInfo(icon: "bolt.fill",     color: Color(red: 0.929, green: 0.329, blue: 0.329),        name: "Acharné",      subtitle: "Un mois d'écriture continue. Impressionnant.")
        case 60:  return BadgeInfo(icon: "crown.fill",    color: Color(red: 0.749, green: 0.318, blue: 0.918),        name: "Légende",      subtitle: "Deux mois sans interruption. Remarquable.")
        case 100: return BadgeInfo(icon: "trophy.fill",   color: .accentWarm,                                         name: "Immortel",     subtitle: "100 jours. Performance exceptionnelle.")
        default:  return BadgeInfo(icon: "flame.fill",    color: .accent,                                             name: "\(n) jours",   subtitle: "Continue comme ça.")
        }
    }

    private var icon: String {
        switch milestone {
        case .streak(let n):              return MilestoneToastView.badgeInfo(for: n).icon
        case .chapterComplete:            return "checkmark.seal.fill"
        case .challengeComplete(let k):   return k.icon
        }
    }

    private var iconColor: Color {
        switch milestone {
        case .streak(let n):            return MilestoneToastView.badgeInfo(for: n).color
        case .chapterComplete:          return .accentGreen
        case .challengeComplete:        return Color(red: 0.220, green: 0.753, blue: 0.439)
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
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(iconColor.opacity(0.15)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: 380)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.cardBg)
                .shadow(color: .black.opacity(0.20), radius: 16, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(iconColor.opacity(0.25), lineWidth: 1)
        )
    }
}
