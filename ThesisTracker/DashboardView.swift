import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var inputText: String = ""
    // Forces the input cluster to remount with a fresh @State when its parent
    // context (active chapter, selected date, file import) changes. Bumped by
    // refreshInput() and any code that previously assigned `inputText`.
    @State private var inputClusterToken: UUID = UUID()
    @State private var noteText: String = ""
    @State private var importedFileName: String? = nil
    @State private var importError: String? = nil
    // #7 — Dictée vocale
    @State private var isDictating: Bool = false
    // #3 — Drop fichier
    @State private var isFileDropTarget: Bool = false
    @State private var selectedDate: Date = Date()
    @State private var showSettings = false
    @State private var savedConfirmation = false
    @State private var showDeleteConfirm = false
    @State private var streakPulse = false
    @AppStorage("lastStreakMilestone") private var lastStreakMilestone: Int = 0
    @AppStorage("lastGoalReachedDate") private var lastGoalReachedDate: String = ""
    @State private var statsCache: DashboardStatsCache? = nil
    @State private var showConfetti: Bool = false
    @State private var goalBarFlash: Bool = false
    @State private var noteSaveDebouncer = Debouncer(delay: 0.6)
    @FocusState private var inputFieldFocused: Bool

    // #5 — Notes de chapitre structurées
    @State private var chapterNotesText: String = ""
    @State private var notesPlanText: String = ""
    @State private var notesIdeasText: String = ""
    @State private var notesBlockersText: String = ""
    @State private var chapterNotesDebouncer = Debouncer(delay: 0.8)
    @State private var showChapterNotes: Bool = false
    @State private var notesTabIndex: Int = 0   // 0=Plan 1=Idées 2=Blocages 3=Notes

    // #1 — Prochaine étape
    @State private var nextStepText: String = ""
    @State private var nextStepDebouncer = Debouncer(delay: 0.6)
    @State private var editingNextStep: Bool = false

    // #4 — Rapport directeur
    @State private var showDirectorReport: Bool = false

    // #5 — Breadcrumb cliquable
    @State private var showProjectPicker: Bool = false
    @State private var showChapterPicker: Bool = false

    // #39 — Ordre des widgets (gauche et droite)
    @AppStorage("dashboardWidgetOrder") private var widgetOrderStored: String =
        "healthScore,researchTime,focusChapter,writingSpeed,completion,quickStats,miniChart,dailySession,timeline,progress,planning,insights,weeklyChallenge,monthlyChallenge,weekComparison,upcomingDeadlines,dailyQuote,dailySnapshot"
    @AppStorage("dashboardLeftWidgets") private var leftWidgetsStored: String =
        "projectSelector,writingEntry,weekCalendar"
    @State private var showCustomizeSheet: Bool = false
    @State private var isCustomizing: Bool = false
    // #16 — Mode compact
    @AppStorage("dashboardCompact") private var dashboardCompact: Bool = false

    // Drag-and-drop
    @State private var draggingWidget: DashboardWidget? = nil
    @State private var dropHoverWidget: DashboardWidget? = nil
    @State private var hoveredInsertion: InsertionPoint? = nil

    struct InsertionPoint: Equatable {
        let column: ColumnSide
        let index: Int
    }

    private var activeProject: Project? { store.activeProject }
    private var activeChapter: Chapter? { store.activeChapter }
    private var selectedDateStr: String { DataStore.dateString(from: selectedDate) }
    private var isToday: Bool { selectedDateStr == DataStore.today }
    private var hasExistingEntry: Bool { activeChapter?.entryForDate(selectedDateStr) != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerView

                HStack(alignment: .top, spacing: 16) {
                    leftColumn
                    rightColumn
                    .sheet(isPresented: $showCustomizeSheet) {
                        DashboardCustomizeSheet(widgetOrderStored: $widgetOrderStored,
                                               leftWidgetsStored: $leftWidgetsStored)
                    }
                }
                .environment(\.compactDashboard, dashboardCompact)
            }
            .padding(20)
        }
        .onAppear {
            // Migration : ajouter les 3 widgets fixes en colonne gauche si absents
            if !leftWidgetsStored.contains("projectSelector") {
                let existing = leftWidgetsStored.isEmpty ? "" : "," + leftWidgetsStored
                leftWidgetsStored = "projectSelector,writingEntry,weekCalendar" + existing
            }
            refreshInput()
            if statsCache?.isValid(for: store) != true { statsCache = DashboardStatsCache(store: store) }
            // Focus le champ de saisie pour pouvoir taper directement à l'ouverture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NotificationCenter.default.post(name: .dashboardFocusInput, object: nil)
            }
        }
        .onChange(of: store.dataVersion) { _ in
            statsCache = DashboardStatsCache(store: store)
            // Sync chapter notes if changed externally
            if let ch = activeChapter {
                let stored = ch.notes ?? ""
                if stored != chapterNotesText { chapterNotesText = stored }
            }
        }
        // V5 — raccourcis clavier depuis MainView. (Le sauvegarde via .dashboardSave
        // est gérée directement dans WritingEntryInputCluster pour rester cohérente
        // avec l'état local du champ.)
        .onReceive(NotificationCenter.default.publisher(for: .dashboardFocusInput)) { _ in
            inputFieldFocused = true
        }
        // V5 — #5 : Flash + confetti quand objectif atteint pour la première fois du jour
        .onChange(of: currentEntryDelta) { _, newDelta in
            let goal = store.effectiveDailyGoal
            guard goal > 0, isToday, lastGoalReachedDate != DataStore.today else { return }
            if Double(newDelta) / Double(goal) >= 1.0 {
                lastGoalReachedDate = DataStore.today
                withAppAnimation(Motion.celebrate) { goalBarFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    withAppAnimation(Motion.quick) { goalBarFlash = false }
                }
                showConfetti = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { showConfetti = false }
                NSSound(named: .init("Hero"))?.play()
            }
        }
        .overlay { if showConfetti { ConfettiOverlay().allowsHitTesting(false) } }
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .alert("Effacer cette entrée ?", isPresented: $showDeleteConfirm) {
            Button("Effacer", role: .destructive) {
                if let chapter = activeChapter, let project = activeProject {
                    withAppAnimation { store.deleteEntry(for: chapter.id, in: project.id, date: selectedDateStr) }
                    inputText = ""
                    inputClusterToken = UUID()
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'entrée du \(formattedSelectedDate) sera supprimée définitivement.")
        }
    }

    // MARK: - #39 Widget order helpers

    enum DashboardWidget: String, CaseIterable {
        // Widgets de la colonne gauche (fixes par défaut)
        case projectSelector  = "projectSelector"
        case writingEntry     = "writingEntry"
        case weekCalendar     = "weekCalendar"
        // Widgets de la colonne droite (fixes par défaut)
        case healthScore      = "healthScore"
        case researchTime     = "researchTime"
        case completion       = "completion"
        case quickStats       = "quickStats"
        case miniChart        = "miniChart"
        case dailySession     = "dailySession"
        case timeline         = "timeline"
        case progress         = "progress"
        case planning         = "planning"
        case insights         = "insights"
        case weeklyChallenge   = "weeklyChallenge"
        case monthlyChallenge  = "monthlyChallenge"
        // #9-#15 nouveaux widgets
        case writingSpeed      = "writingSpeed"
        case weekComparison    = "weekComparison"
        case upcomingDeadlines = "upcomingDeadlines"
        case focusChapter      = "focusChapter"
        case dailyQuote        = "dailyQuote"
        case dailySnapshot     = "dailySnapshot"
        case supervisorReview  = "supervisorReview"
        case checkpoints       = "checkpoints"
        case weeklyPlan        = "weeklyPlan"
        case defenseNotes      = "defenseNotes"
        case wellbeing         = "wellbeing"
        case chapterHeatmap    = "chapterHeatmap"
        case defenseDate       = "defenseDate"
        case journal           = "journal"
        case fragments         = "fragments"
        case monthlyReport     = "monthlyReport"
        case painfulChapters   = "painfulChapters"
        case adminChecklist    = "adminChecklist"

        var label: String {
            switch self {
            case .projectSelector: return "Sélecteur projet / chapitre"
            case .writingEntry:    return "Saisie du jour"
            case .weekCalendar:    return "Calendrier de la semaine"
            case .healthScore:     return "Santé de la thèse"
            case .researchTime:    return "Temps de recherche"
            case .completion:      return "Progression du projet"
            case .quickStats:      return "Stats rapides"
            case .miniChart:       return "Activité 14 jours"
            case .dailySession:    return "Session quotidienne"
            case .timeline:        return "Timeline du jour"
            case .progress:        return "Progression chapitre"
            case .planning:        return "Planification"
            case .insights:        return "Insights"
            case .weeklyChallenge:  return "Défi hebdomadaire"
            case .monthlyChallenge: return "Défi mensuel"
            case .writingSpeed:     return "Vitesse d'écriture"
            case .weekComparison:   return "Comparaison semaines"
            case .upcomingDeadlines:return "Prochains jalons"
            case .focusChapter:     return "Chapitre en focus"
            case .dailyQuote:       return "Citation du jour"
            case .dailySnapshot:    return "Snapshot quotidien"
            case .supervisorReview: return "Relectures directeur"
            case .checkpoints:      return "Points de sauvegarde"
            case .weeklyPlan:       return "Plan de bataille hebdo"
            case .defenseNotes:     return "Notes de soutenance"
            case .wellbeing:        return "Énergie & repos"
            case .chapterHeatmap:   return "Heatmap par chapitre"
            case .defenseDate:      return "Projection soutenance"
            case .journal:          return "Journal de bord"
            case .fragments:        return "Carnet de fragments"
            case .monthlyReport:    return "Bilans mensuels"
            case .painfulChapters:  return "Chapitres qui font mal"
            case .adminChecklist:   return "Administratif"
            }
        }
        var icon: String {
            switch self {
            case .projectSelector: return "folder.fill"
            case .writingEntry:    return "pencil.line"
            case .weekCalendar:    return "calendar.badge.clock"
            case .healthScore:     return "heart.fill"
            case .researchTime:    return "brain.head.profile"
            case .completion:      return "chart.pie.fill"
            case .quickStats:      return "square.grid.2x2"
            case .miniChart:       return "chart.bar.fill"
            case .dailySession:    return "clock.fill"
            case .timeline:        return "list.bullet.rectangle"
            case .progress:        return "book.closed.fill"
            case .planning:        return "calendar"
            case .insights:        return "lightbulb.fill"
            case .weeklyChallenge:  return "trophy.fill"
            case .monthlyChallenge: return "calendar.badge.checkmark"
            case .writingSpeed:     return "speedometer"
            case .weekComparison:   return "chart.bar.doc.horizontal"
            case .upcomingDeadlines:return "flag.checkered"
            case .focusChapter:     return "doc.text.fill"
            case .dailyQuote:       return "quote.bubble.fill"
            case .dailySnapshot:    return "camera.viewfinder"
            case .supervisorReview: return "paperplane.fill"
            case .checkpoints:      return "bookmark.fill"
            case .weeklyPlan:       return "checklist"
            case .defenseNotes:     return "graduationcap.fill"
            case .wellbeing:        return "leaf.fill"
            case .chapterHeatmap:   return "square.grid.3x3.fill"
            case .defenseDate:      return "graduationcap.circle.fill"
            case .journal:          return "book.closed.fill"
            case .fragments:        return "scribble.variable"
            case .monthlyReport:    return "calendar.badge.checkmark"
            case .painfulChapters:  return "bandage.fill"
            case .adminChecklist:   return "tray.full.fill"
            }
        }

        /// Widgets affichés dans le panneau de personnalisation (ceux de la colonne droite uniquement)
        static var customizableWidgets: [DashboardWidget] {
            allCases.filter { $0 != .projectSelector && $0 != .writingEntry && $0 != .weekCalendar }
        }
    }

    private var leftWidgets: [DashboardWidget] {
        leftWidgetsStored.split(separator: ",").map(String.init).compactMap { DashboardWidget(rawValue: $0) }
    }

    private var widgetOrder: [DashboardWidget] {
        let leftSet = Set(leftWidgets)
        let keys = widgetOrderStored.split(separator: ",").map(String.init)
        // On respecte STRICTEMENT widgetOrderStored : un widget supprimé reste supprimé
        // jusqu'à ce que l'utilisateur le ré-ajoute via le panneau Personnaliser.
        return keys.compactMap { DashboardWidget(rawValue: $0) }.filter { !leftSet.contains($0) }
    }

    private func columnOf(_ widget: DashboardWidget) -> ColumnSide {
        leftWidgets.contains(widget) ? .left : .right
    }

    @ViewBuilder
    private func widgetView(for widget: DashboardWidget) -> some View {
        switch widget {
        case .projectSelector: projectChapterSelector
        case .writingEntry:
            if activeChapter != nil { entryCard } else { emptyState }
        case .weekCalendar:    weekCalendarSection
        case .healthScore:     ThesisHealthWidget(store: store)
        case .researchTime:    ResearchTimeCard(store: store)
        case .completion:      projectCompletionCard
        case .quickStats:      quickStatsGrid
        case .miniChart:       miniChartSection
        case .dailySession:    DailySessionCard(store: store)
        case .timeline:        TodayTimelineView(store: store)
        case .progress:        if activeChapter != nil { progressSection }
        case .planning:        if activeChapter != nil { planningSection }
        case .insights:        insightsSection
        case .weeklyChallenge:  WeeklyChallengeCard(store: store)
        case .monthlyChallenge: MonthlyChallengeCard(store: store)
        case .writingSpeed:     WritingSpeedWidget(store: store)
        case .weekComparison:   WeekComparisonWidget(store: store)
        case .upcomingDeadlines:UpcomingDeadlinesWidget(store: store)
        case .focusChapter:     FocusChapterWidget(store: store)
        case .dailyQuote:       DailyQuoteWidget(store: store)
        case .dailySnapshot:    DailySnapshotWidget(store: store)
        case .supervisorReview: SupervisorReviewCard(store: store)
        case .checkpoints:      CheckpointsWidget(store: store)
        case .weeklyPlan:       WeeklyPlanWidget(store: store)
        case .defenseNotes:     DefenseNotesWidget(store: store)
        case .wellbeing:        WellbeingWidget(store: store)
        case .chapterHeatmap:   ChapterHeatmapWidget(store: store)
        case .defenseDate:      DefenseDateWidget(store: store)
        case .journal:          JournalWidget(store: store)
        case .fragments:        FragmentsWidget(store: store)
        case .monthlyReport:    MonthlyReportWidget(store: store)
        case .painfulChapters:  PainfulChaptersWidget(store: store)
        case .adminChecklist:   AdminChecklistWidget(store: store)
        }
    }

    // MARK: - Drag-and-drop inline

    enum ColumnSide { case left, right }

    // MARK: - Colonnes du dashboard (extraites pour limiter le type-checking)

    @ViewBuilder
    private var leftColumn: some View {
        LazyVStack(spacing: 0) {
            if leftWidgets.isEmpty {
                columnDropZone(column: .left)
            } else {
                insertionZone(column: .left, index: 0)
                ForEach(Array(leftWidgets.enumerated()), id: \.element) { idx, widget in
                    widgetWrapper(for: widget, column: .left, index: idx, total: leftWidgets.count)
                    insertionZone(column: .left,
                                  index: idx + 1,
                                  isLast: idx == leftWidgets.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rightColumn: some View {
        VStack(spacing: 0) {
            rightColumnHeader
                .padding(.bottom, 8)
            LazyVStack(spacing: 0) {
                insertionZone(column: .right, index: 0)
                ForEach(Array(widgetOrder.enumerated()), id: \.element) { idx, widget in
                    widgetWrapper(for: widget, column: .right, index: idx, total: widgetOrder.count)
                    insertionZone(column: .right,
                                  index: idx + 1,
                                  isLast: idx == widgetOrder.count - 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var rightColumnHeader: some View {
        HStack {
            Spacer()
            if isCustomizing {
                Button {
                    withAppAnimation(.easeOut(duration: 0.15)) { isCustomizing = false }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                        Text("Terminer").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            } else {
                Button {
                    showCustomizeSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                        Text("Personnaliser").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.labelMuted)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.glassFill)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .help("Réorganiser les widgets")
            }
        }
    }

    @ViewBuilder
    private func widgetWrapper(for widget: DashboardWidget, column: ColumnSide, index: Int, total: Int) -> some View {
        let isDropTarget = dropHoverWidget == widget
        let isDragging   = draggingWidget == widget

        ZStack(alignment: .topTrailing) {
            widgetView(for: widget)
                .opacity(isDragging ? 0.45 : 1)

            if isCustomizing {
                columnSwitchControl(for: widget, column: column)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDropTarget ? Color.accent : (isCustomizing ? Color.accent.opacity(0.25) : Color.clear),
                    lineWidth: isDropTarget ? 2 : 1.5
                )
                .allowsHitTesting(false)
        )
        // Drag handle visible au hover (toujours, pas seulement en mode customize)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.labelMuted.opacity(0.45))
                .padding(8)
                .allowsHitTesting(false)
        }
        // Drag source — on track le début/fin du drag pour activer les insertion zones
        .draggable(widget.rawValue) {
            dragPreview(for: widget)
                .onAppear {
                    draggingWidget = widget
                }
                .onDisappear {
                    draggingWidget = nil
                    hoveredInsertion = nil
                }
        }
        // Drop target
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first,
                  let src = DashboardWidget(rawValue: raw),
                  src != widget else { return false }
            withAppAnimation(Motion.panel) {
                handleDrop(from: src, to: widget, dstColumn: column, location: location)
            }
            draggingWidget = nil
            dropHoverWidget = nil
            return true
        } isTargeted: { targeted in
            withAppAnimation(.easeInOut(duration: 0.14)) {
                dropHoverWidget = targeted ? widget : (dropHoverWidget == widget ? nil : dropHoverWidget)
                if targeted { draggingWidget = nil } // best-effort: clear on hover of different widget
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            withAppAnimation(.easeOut(duration: 0.15)) { isCustomizing = true }
        }
        // Clic droit → menu contextuel pour retirer le widget
        .contextMenu {
            Button {
                withAppAnimation(.easeOut(duration: 0.18)) {
                    removeWidget(widget)
                }
            } label: {
                Label("Retirer du tableau de bord", systemImage: "minus.circle")
            }
            Button {
                showCustomizeSheet = true
            } label: {
                Label("Personnaliser…", systemImage: "slider.horizontal.3")
            }
            Divider()
            if column == .right {
                Button {
                    withAppAnimation(.easeOut(duration: 0.15)) {
                        handleDrop(from: widget, to: nil, dstColumn: .left, location: .zero)
                    }
                } label: {
                    Label("Déplacer à gauche", systemImage: "arrow.left")
                }
            } else {
                Button {
                    withAppAnimation(.easeOut(duration: 0.15)) {
                        handleDrop(from: widget, to: nil, dstColumn: .right, location: .zero)
                    }
                } label: {
                    Label("Déplacer à droite", systemImage: "arrow.right")
                }
            }
        }
        .appAnimation(Motion.panel, value: isCustomizing)
        .appAnimation(.easeInOut(duration: 0.14), value: isDropTarget)
    }

    /// Retire un widget des deux colonnes (le rend "disponible" dans Personnaliser).
    private func removeWidget(_ widget: DashboardView.DashboardWidget) {
        var left = leftWidgetsStored.split(separator: ",").map(String.init)
        var right = widgetOrderStored.split(separator: ",").map(String.init)
        let raw = widget.rawValue
        left.removeAll { $0 == raw }
        right.removeAll { $0 == raw }
        leftWidgetsStored = left.joined(separator: ",")
        widgetOrderStored = right.joined(separator: ",")
    }

    /// Petite preview flottante pendant le drag
    @ViewBuilder
    private func dragPreview(for widget: DashboardWidget) -> some View {
        HStack(spacing: 8) {
            Image(systemName: widget.icon)
                .font(.system(size: 12))
                .foregroundColor(.accent)
            Text(widget.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
    }

    /// Badge pour changer de colonne (reste en mode customize)
    private func columnSwitchControl(for widget: DashboardWidget, column: ColumnSide) -> some View {
        Button {
            withAppAnimation(.easeOut(duration: 0.15)) {
                if column == .right { handleDrop(from: widget, to: nil, dstColumn: .left, location: .zero) }
                else                { handleDrop(from: widget, to: nil, dstColumn: .right, location: .zero) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: column == .right ? "arrow.left" : "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(column == .right ? "← Gauche" : "Droite →")
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.accent)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.regularMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.accent.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.pressable)
        .padding(8)
    }

    // MARK: - Insertion zones (drop fluide entre cartes / en fin de colonne)

    /// Zone d'insertion entre deux cartes (ou en début/fin de colonne).
    /// Invisible au repos, fine pendant un drag, écartée à pleine hauteur quand on survole.
    @ViewBuilder
    private func insertionZone(column: ColumnSide, index: Int, isLast: Bool = false) -> some View {
        let isDragging = draggingWidget != nil
        let isActive = hoveredInsertion == InsertionPoint(column: column, index: index)
        let baseHeight: CGFloat = dashboardCompact ? 4 : 8
        let dragHeight: CGFloat = isLast ? 64 : 14
        let activeHeight: CGFloat = isLast ? 64 : 50

        let height: CGFloat = {
            if isActive { return activeHeight }
            if isDragging { return dragHeight }
            return baseHeight
        }()

        ZStack {
            if isDragging {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isActive ? Color.accent : Color.labelMuted.opacity(0.18),
                        style: StrokeStyle(lineWidth: isActive ? 2 : 1, dash: isActive ? [] : [4, 3])
                    )
                    .frame(maxWidth: .infinity)
                if isActive {
                    Capsule()
                        .fill(Color.accent)
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                } else if isLast {
                    Text("Déposer ici")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.labelMuted.opacity(0.6))
                }
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first,
                  let src = DashboardWidget(rawValue: raw) else { return false }
            withAppAnimation(Motion.panel) {
                insertWidget(src, into: column, at: index)
            }
            draggingWidget = nil
            hoveredInsertion = nil
            dropHoverWidget = nil
            return true
        } isTargeted: { targeted in
            withAppAnimation(Motion.panel) {
                if targeted {
                    hoveredInsertion = InsertionPoint(column: column, index: index)
                } else if hoveredInsertion == InsertionPoint(column: column, index: index) {
                    hoveredInsertion = nil
                }
            }
        }
        .appAnimation(Motion.panel, value: isDragging)
        .appAnimation(Motion.panel, value: isActive)
    }

    /// Insère un widget dans la colonne cible à l'index donné (0 = avant la première carte).
    /// Gère le re-positionnement dans la même colonne ou la migration entre colonnes.
    private func insertWidget(_ src: DashboardWidget, into column: ColumnSide, at index: Int) {
        let srcColumn = columnOf(src)

        if column == .left {
            var left = leftWidgets
            if srcColumn == .right {
                var right = widgetOrder
                right.removeAll { $0 == src }
                widgetOrderStored = right.map(\.rawValue).joined(separator: ",")
                let clamped = max(0, min(left.count, index))
                left.insert(src, at: clamped)
            } else {
                let currentIdx = left.firstIndex(of: src)
                left.removeAll { $0 == src }
                var target = index
                if let cur = currentIdx, cur < index { target -= 1 }
                let clamped = max(0, min(left.count, target))
                left.insert(src, at: clamped)
            }
            leftWidgetsStored = left.map(\.rawValue).joined(separator: ",")
        } else {
            var right = widgetOrder
            if srcColumn == .left {
                var left = leftWidgets
                left.removeAll { $0 == src }
                leftWidgetsStored = left.map(\.rawValue).joined(separator: ",")
                let clamped = max(0, min(right.count, index))
                right.insert(src, at: clamped)
            } else {
                let currentIdx = right.firstIndex(of: src)
                right.removeAll { $0 == src }
                var target = index
                if let cur = currentIdx, cur < index { target -= 1 }
                let clamped = max(0, min(right.count, target))
                right.insert(src, at: clamped)
            }
            widgetOrderStored = right.map(\.rawValue).joined(separator: ",")
        }
    }

    private func columnDropZone(column: ColumnSide) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.rectangle")
                .font(.system(size: 18))
                .foregroundColor(.labelMuted.opacity(0.3))
            Text("Dépose une carte ici")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .foregroundColor(.labelMuted.opacity(0.18))
        )
        .transition(.opacity)
    }

    // MARK: - Drop logic

    private func handleDrop(from src: DashboardWidget, to dst: DashboardWidget?, dstColumn: ColumnSide, location: CGPoint) {
        let srcColumn = columnOf(src)

        if dstColumn == .left {
            // Destination : colonne gauche
            var left = leftWidgets
            // Retire de la source
            if srcColumn == .right {
                var right = widgetOrder
                right.removeAll { $0 == src }
                widgetOrderStored = right.map(\.rawValue).joined(separator: ",")
            } else {
                left.removeAll { $0 == src }
            }
            // Insère à la position cible
            if let dst, let di = left.firstIndex(of: dst) {
                left.insert(src, at: di)
            } else {
                if !left.contains(src) { left.append(src) }
            }
            leftWidgetsStored = left.map(\.rawValue).joined(separator: ",")

        } else {
            // Destination : colonne droite
            var right = widgetOrder
            // Retire de la source
            if srcColumn == .left {
                var left = leftWidgets
                left.removeAll { $0 == src }
                leftWidgetsStored = left.map(\.rawValue).joined(separator: ",")
            } else {
                right.removeAll { $0 == src }
            }
            // Insère à la position cible
            if let dst, let di = right.firstIndex(of: dst) {
                right.insert(src, at: di)
            } else {
                if !right.contains(src) { right.append(src) }
            }
            widgetOrderStored = right.map(\.rawValue).joined(separator: ",")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showSidebar ? .accentWarm : .labelMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(showSidebar ? Color.accentWarm.opacity(0.09) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(
                                showSidebar ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 3) {
                Text("Tableau de bord")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                HStack(spacing: 5) {
                    Text(formattedDate)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)

                    if let project = activeProject {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.4))
                        Circle()
                            .fill(Color.accentWarm)
                            .frame(width: 4, height: 4)

                        // Bouton breadcrumb : projet (cliquable, ouvre popover)
                        Button { showProjectPicker.toggle() } label: {
                            HStack(spacing: 3) {
                                Text(project.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.labelMuted)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .semibold))
                                    .foregroundColor(.labelMuted.opacity(0.5))
                            }
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(showProjectPicker ? Color.labelMuted.opacity(0.10) : .clear)
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.pressable)
                        .help("Changer de projet")
                        .popover(isPresented: $showProjectPicker, arrowEdge: .bottom) {
                            BreadcrumbProjectPicker(store: store) { showProjectPicker = false }
                        }

                        if let chapter = activeChapter {
                            Text("›")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.labelMuted.opacity(0.4))

                            // Bouton breadcrumb : chapitre (cliquable, ouvre popover)
                            Button { showChapterPicker.toggle() } label: {
                                HStack(spacing: 3) {
                                    Text(chapter.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundColor(.labelMuted.opacity(0.5))
                                }
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(showChapterPicker ? Color.labelMuted.opacity(0.10) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 5))
                            }
                            .buttonStyle(.pressable)
                            .help("Changer de chapitre")
                            .popover(isPresented: $showChapterPicker, arrowEdge: .bottom) {
                                BreadcrumbChapterPicker(store: store, project: project) { showChapterPicker = false }
                            }
                        }
                    }
                }
            }

            Spacer()

            // 5.18 : la série n'est plus répétée ici (elle est dans la barre du haut)

            Button { showDirectorReport = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: "person.text.rectangle")
                        .font(.system(size: 11))
                    Text("Rapport")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(Color(hex: "#0369A1"))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(hex: "#0369A1").opacity(0.09))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(hex: "#0369A1").opacity(0.22), lineWidth: 1))
                )
            }
            .buttonStyle(.pressable)
            .help("Rapport pour le directeur")
            .sheet(isPresented: $showDirectorReport) {
                DirectorReportSheet(store: store)
            }

            // 5.14 — Professeur en note rapide (fenêtre flottante)
            ProfessorQuickButton(store: store)

            // #16 — Toggle compact
            Button {
                withAppAnimation(.easeInOut(duration: 0.15)) { dashboardCompact.toggle() }
            } label: {
                Image(systemName: dashboardCompact ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .font(.system(size: 12))
                    .foregroundColor(dashboardCompact ? .accent : .labelMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(dashboardCompact ? Color.accent.opacity(0.09) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(
                                dashboardCompact ? Color.accent.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help(dashboardCompact ? "Mode normal" : "Mode compact")
            .accessibilityLabel(dashboardCompact ? "Mode normal" : "Mode compact")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Réglages")
            .accessibilityLabel("Réglages")
        }
    }


    // MARK: - Project + Chapter selector

    private var projectChapterSelector: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    if store.data.projects.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.labelMuted)
                                .font(.system(size: 13))
                            Text("Aucun projet")
                                .foregroundColor(.labelMuted)
                                .font(.system(size: 14))
                        }
                    } else {
                        CompactDropdownPicker(
                            icon: "folder.fill",
                            iconColor: .accent,
                            placeholder: "Choisir un projet",
                            items: store.data.projects.map { (id: $0.id, name: $0.name) },
                            selectedId: store.data.activeProjectId
                        ) { id in
                            store.data.activeProjectId = id
                            store.save()
                            refreshInput()
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Button {
                        withAppAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder.badge.gearshape").font(.system(size: 11))
                            Text("Projets").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.accent.opacity(0.10))
                            .overlay(Capsule().stroke(Color.accent.opacity(0.20), lineWidth: 1)))
                    }
                    .buttonStyle(.pressable)
                }

                if let project = activeProject, !project.chapters.isEmpty {
                    Divider()

                    HStack(spacing: 8) {
                        CompactDropdownPicker(
                            icon: "book.closed.fill",
                            iconColor: .accentWarm,
                            placeholder: "Choisir un chapitre",
                            items: project.chapters.map { (id: $0.id, name: $0.name) },
                            selectedId: project.activeChapterId
                        ) { id in
                            if let projIdx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                                store.data.projects[projIdx].activeChapterId = id
                                store.save()
                                refreshInput()
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // #18 — Réorganisation des chapitres : ↑↓
                        if let chapter = activeChapter {
                            let chapters = project.chapters
                            let idx = chapters.firstIndex(where: { $0.id == chapter.id }) ?? -1
                            HStack(spacing: 2) {
                                Button {
                                    store.moveChapter(chapter.id, direction: -1, in: project.id)
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(idx > 0 ? .secondary : .labelMuted.opacity(0.3))
                                        .frame(width: 22, height: 22)
                                        .background(Color.glassFill)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.pressable)
                                .disabled(idx <= 0)
                                .help("Monter le chapitre")
                                .accessibilityLabel("Monter le chapitre")

                                Button {
                                    store.moveChapter(chapter.id, direction: 1, in: project.id)
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(idx < chapters.count - 1 ? .secondary : .labelMuted.opacity(0.3))
                                        .frame(width: 22, height: 22)
                                        .background(Color.glassFill)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.pressable)
                                .disabled(idx >= chapters.count - 1)
                                .help("Descendre le chapitre")
                                .accessibilityLabel("Descendre le chapitre")
                            }
                        }

                        // #5 — Bouton toggle note de chapitre
                        if activeChapter != nil {
                            Button {
                                withAppAnimation(.easeOut(duration: 0.15)) { showChapterNotes.toggle() }
                            } label: {
                                Image(systemName: showChapterNotes ? "note.text.badge.plus" : "note.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(showChapterNotes ? .accentWarm : .labelMuted)
                                    .frame(width: 28, height: 28)
                                    .background(showChapterNotes ? Color.accentWarm.opacity(0.10) : Color.glassFill)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(
                                        showChapterNotes ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                            .help("Note de chapitre")
                            .accessibilityLabel("Note de chapitre")
                        }
                    }

                    // #1 — Prochaine étape
                    if let chapter = activeChapter, let project = activeProject {
                        Divider()
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(nextStepText.isEmpty ? .labelMuted.opacity(0.35) : .accent)
                            if editingNextStep {
                                TextField("Prochaine étape…", text: $nextStepText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .onSubmit { editingNextStep = false }
                                    .onChange(of: nextStepText) { _, newVal in
                                        nextStepDebouncer.schedule {
                                            store.updateNextStep(newVal, for: chapter.id, in: project.id)
                                        }
                                    }
                            } else {
                                Button {
                                    editingNextStep = true
                                } label: {
                                    Text(nextStepText.isEmpty ? "Ajouter la prochaine étape…" : nextStepText)
                                        .font(.system(size: 12, weight: nextStepText.isEmpty ? .regular : .medium))
                                        .foregroundColor(nextStepText.isEmpty ? .labelMuted.opacity(0.5) : .primary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.pressable)
                                if !nextStepText.isEmpty {
                                    Button {
                                        nextStepText = ""
                                        store.updateNextStep(nil, for: chapter.id, in: project.id)
                                    } label: {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 11))
                                            .foregroundColor(.accentGreen)
                                    }
                                    .buttonStyle(.pressable)
                                    .help("Marquer comme fait")
                                    .accessibilityLabel("Marquer comme fait")
                                }
                            }
                        }
                        .padding(.top, 2)
                        .onChange(of: chapter.id) { _, _ in
                            editingNextStep = false
                            nextStepText = activeChapter?.nextStep ?? ""
                        }
                    }

                    // #5 — Notes structurées (onglets)
                    if showChapterNotes, let chapter = activeChapter, let project = activeProject {
                        VStack(alignment: .leading, spacing: 8) {
                            // Onglets
                            HStack(spacing: 0) {
                                ForEach(["Plan", "Idées", "Blocages", "Notes"].indices, id: \.self) { i in
                                    let label = ["Plan", "Idées", "Blocages", "Notes"][i]
                                    let icons  = ["list.number", "lightbulb.fill", "exclamationmark.triangle", "note.text"]
                                    let hasContent = [
                                        !notesPlanText.isEmpty,
                                        !notesIdeasText.isEmpty,
                                        !notesBlockersText.isEmpty,
                                        !chapterNotesText.isEmpty
                                    ][i]
                                    Button {
                                        withAppAnimation(.easeInOut(duration: 0.12)) { notesTabIndex = i }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: icons[i])
                                                .font(.system(size: 10))
                                            Text(label)
                                                .font(.system(size: 11, weight: notesTabIndex == i ? .semibold : .regular))
                                            if hasContent && notesTabIndex != i {
                                                Circle().fill(Color.accentWarm).frame(width: 4, height: 4)
                                            }
                                        }
                                        .foregroundColor(notesTabIndex == i ? .accentWarm : .labelMuted)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(notesTabIndex == i ? Color.accentWarm.opacity(0.10) : Color.clear)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.pressable)
                                }
                                Spacer()
                            }

                            let placeholder = ["Plan et structure du chapitre…",
                                               "Idées, fragments, pistes à explorer…",
                                               "Blocages actuels, questions en suspens…",
                                               "Notes générales…"][notesTabIndex]
                            let binding: Binding<String> = [
                                $notesPlanText, $notesIdeasText, $notesBlockersText, $chapterNotesText
                            ][notesTabIndex]

                            // #5 — Templates de chapitre (onglet Plan, champ vide)
                            if notesTabIndex == 0 && notesPlanText.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(ChapterPlanTemplate.all, id: \.name) { tmpl in
                                            Button {
                                                notesPlanText = tmpl.content
                                                scheduleNotesSave(chapter: chapter, project: project)
                                            } label: {
                                                HStack(spacing: 4) {
                                                    Image(systemName: tmpl.icon).font(.system(size: 10))
                                                    Text(tmpl.name).font(.system(size: 10, weight: .medium))
                                                }
                                                .foregroundColor(.accent)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Color.accent.opacity(0.07))
                                                .clipShape(Capsule())
                                                .overlay(Capsule().stroke(Color.accent.opacity(0.15), lineWidth: 1))
                                            }
                                            .buttonStyle(.pressable)
                                            .help("Appliquer le modèle « \(tmpl.name) »")
                                        }
                                    }
                                }
                                .transition(.opacity)
                            }

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: binding)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 72, maxHeight: 160)
                                    .padding(8)
                                    .background(Color.fieldBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                                    .onChange(of: notesPlanText)    { _, v in scheduleNotesSave(chapter: chapter, project: project) }
                                    .onChange(of: notesIdeasText)   { _, v in scheduleNotesSave(chapter: chapter, project: project) }
                                    .onChange(of: notesBlockersText) { _, v in scheduleNotesSave(chapter: chapter, project: project) }
                                    .onChange(of: chapterNotesText) { _, v in scheduleNotesSave(chapter: chapter, project: project) }
                                if binding.wrappedValue.isEmpty {
                                    Text(placeholder)
                                        .font(.system(size: 12))
                                        .foregroundColor(.labelMuted.opacity(0.35))
                                        .padding(.horizontal, 13).padding(.top, 13)
                                        .allowsHitTesting(false)
                                }
                            }
                        }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                    }
                }
            }
        }
    }

    // MARK: - Entry card

    // Nombre de caractères enregistrés pour la date sélectionnée
    private var currentEntryTotal: Int {
        activeChapter?.entryForDate(selectedDateStr)?.totalCount ?? 0
    }

    // Delta = incrément du jour sélectionné (0 si absent)
    private var currentEntryDelta: Int {
        guard let chapter = activeChapter else { return 0 }
        return chapter.increment(for: selectedDateStr)
    }

    // 5.12 — « ≈ X pages rédigées sur Y (calibrage 1 500 car./p) »
    private var heroPagesLine: String? {
        guard currentEntryTotal > 0,
              let written = store.pagesNumber(currentEntryTotal),
              let calibration = store.pageCalibrationLabel else { return nil }
        if let goal = activeChapter?.goal, goal > 0, let total = store.pagesNumber(goal, digits: 0) {
            return "≈ \(written) pages rédigées sur \(total) (\(calibration))"
        }
        return "≈ \(written) pages rédigées (\(calibration))"
    }

    // Variation nette du jour sélectionné (négative après une correction)
    private var currentEntryNet: Int {
        activeChapter?.netChange(for: selectedDateStr) ?? 0
    }

    // V5 — #4 : Nouveau record personnel ?
    private var isNewPersonalRecord: Bool {
        guard isToday, currentEntryDelta > 0 else { return false }
        return currentEntryDelta > store.allTimeBestDay
    }

    // V5 — #6 : "Dernière écriture il y a X jours"
    private var daysSinceLastEntry: Int? {
        guard let ch = activeChapter, isToday, currentEntryDelta == 0 else { return nil }
        let today = DataStore.today
        guard let last = ch.entries.filter({ $0.date < today }).max(by: { $0.date < $1.date }),
              let lastDate = DataStore.parseDate(last.date) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return days > 0 ? days : nil
    }

    private var entryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {

                // ── Barre de date + actions ──────────────────────
                HStack(spacing: 8) {
                    CompactDatePicker(date: $selectedDate, maxDate: Date())
                        .onChange(of: selectedDate) { _, _ in refreshInput() }
                    Spacer()
                    DayOffMenuButton(store: store, date: selectedDateStr)
                    if !isToday {
                        Label("Passé", systemImage: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.orange.opacity(0.12))
                                .overlay(Capsule().stroke(Color.orange.opacity(0.20), lineWidth: 1)))
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    }
                    if hasExistingEntry {
                        Button { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.red.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                        .help("Supprimer la saisie")
                        .accessibilityLabel("Supprimer la saisie")
                    }
                }
                .appAnimation(.easeOut(duration: 0.15), value: hasExistingEntry)
                .appAnimation(.easeOut(duration: 0.15), value: isToday)

                // ── Hero count ─────────────────────────────────
                VStack(spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(store.data.useWordCount
                             ? DataStore.formatNumber(currentEntryTotal / 5)
                             : DataStore.formatNumber(currentEntryTotal))
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: currentEntryTotal > 0 ? [.primary, .primary.opacity(0.7)] : [Color.labelMuted.opacity(0.4)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .contentTransition(.numericText())
                            .appAnimation(Motion.progress, value: currentEntryTotal)
                        Text(store.data.useWordCount ? "mots" : "car.")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.labelMuted)
                            .padding(.bottom, 6)
                    }

                    // 5.12 — équivalent en pages de thèse
                    if let line = heroPagesLine {
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }

                    if currentEntryDelta > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                            Text("+\(store.formatCount(currentEntryDelta)) aujourd'hui")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.accentGreen)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))

                        // V5 — #4 : Badge record personnel
                        if isNewPersonalRecord {
                            HStack(spacing: 4) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 10))
                                Text("Nouveau record personnel !")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.yellow.opacity(0.12)))
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                        }
                    } else if currentEntryNet < 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(store.formatCount(currentEntryNet)) \(isToday ? "aujourd'hui" : "ce jour-là")")
                                .font(.system(size: 11))
                            if activeChapter?.entryForDate(selectedDateStr)?.isCorrection == true {
                                Text("Correction")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentWarm.opacity(0.15)))
                            }
                        }
                        .foregroundColor(.accentWarm)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else if currentEntryTotal == 0 {
                        Text(isToday ? "Aucune entrée pour aujourd'hui" : "Aucune entrée ce jour-là")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.6))
                    }

                    // V5 — #6 : Dernière écriture il y a X jours
                    if let days = daysSinceLastEntry {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text("Dernière écriture : il y a \(days) jour\(days > 1 ? "s" : "")")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.orange.opacity(0.8))
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

                // ── Barre de progression objectif ──────────────
                if store.effectiveDailyGoal > 0 && currentEntryDelta > 0 {
                    let ratio = min(1.0, Double(currentEntryDelta) / Double(store.effectiveDailyGoal))
                    VStack(spacing: 5) {
                        HStack {
                            Text("Objectif — \(store.formatCount(store.effectiveDailyGoal))")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Text("\(Int(ratio * 100))%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(ratio >= 1.0 ? .accentGreen : .accent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.cardBorder).frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LinearGradient(
                                        colors: goalBarFlash ? [.accentGreen, .accentGreen]
                                              : ratio >= 1.0 ? [.accentGreen] : [.accent, .accentWarm],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * CGFloat(ratio), height: goalBarFlash ? 5 : 3)
                                    .appAnimation(Motion.progress, value: ratio)
                                    .appAnimation(.spring(response: 0.2), value: goalBarFlash)
                            }
                        }
                        .frame(height: 5)
                        // V5 — #10 : Tooltip
                        .help("\(store.formatCount(currentEntryDelta)) / \(store.formatCount(store.effectiveDailyGoal)) \(store.data.useWordCount ? "mots" : "car.") · \(Int(ratio * 100))% de l'objectif journalier")
                    }
                    .padding(.bottom, 12)
                }

                Divider()

                // ── #4 : Alerte de régression ─────────────────
                if isToday, let chapter = activeChapter, let project = activeProject,
                   let warn = store.regressionWarning(for: chapter.id, in: project.id, date: selectedDateStr) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 11))
                            .foregroundColor(.accentWarm)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Rythme en baisse")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentWarm)
                            Text("Aujourd'hui \(store.formatCount(warn.todayDelta)) vs moy. \(store.formatCount(warn.avg7))/j sur 7j (\(Int(warn.ratio * 100))%)")
                                .font(.system(size: 10))
                                .foregroundColor(.accentWarm.opacity(0.8))
                        }
                        Spacer()
                    }
                    .padding(9)
                    .background(Color.accentWarm.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentWarm.opacity(0.2), lineWidth: 1))
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // ── Champ de saisie ───────────────────────────
                // Isolated subview owns its own typing state — keystrokes do NOT
                // re-evaluate DashboardView.body (was the main typing-lag source).
                WritingEntryInputCluster(
                    useWordCount: store.data.useWordCount,
                    initialText: inputText,
                    entryForHistory: activeChapter?.entryForDate(selectedDateStr),
                    previousTotal: activeChapter?.previousTotal(before: selectedDateStr) ?? 0,
                    savedConfirmation: savedConfirmation,
                    focused: $inputFieldFocused,
                    isDictating: $isDictating,
                    onSave: { count, correction in saveEntry(count, isCorrection: correction) }
                )
                .id(inputClusterToken)

                // ── Note du jour ──────────────────────────────
                Divider().padding(.top, 10)
                HStack(spacing: 8) {
                    Image(systemName: "note.text").foregroundColor(.labelMuted).font(.system(size: 11))
                    TextField("Note du jour (optionnel)…", text: $noteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .onSubmit { saveNote() }
                        .onChange(of: noteText) { _, _ in
                            if hasExistingEntry {
                                noteSaveDebouncer.schedule { saveNote() }
                            }
                        }
                }
                .padding(.top, 9)

                // ── Import fichier ────────────────────────────
                Divider().padding(.top, 8)
                HStack(spacing: 6) {
                    Button {
                        importError = nil
                        importedFileName = nil
                        importFile()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.badge.arrow.up")
                                .font(.system(size: 10))
                            Text("Importer depuis un fichier…")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.accent)
                    }
                    .buttonStyle(.pressable)
                    .help("Extrait le nombre de mots/caractères d'un .docx, .doc, .rtf ou .txt")

                    Spacer()

                    if let name = importedFileName {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10)).foregroundColor(.accentGreen)
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                                .lineLimit(1)
                        }
                        .transition(.opacity)
                    } else if let err = importError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10)).foregroundColor(.accentWarm)
                            Text(err)
                                .font(.system(size: 10))
                                .foregroundColor(.accentWarm)
                                .lineLimit(1)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.top, 6)
                .appAnimation(.easeInOut(duration: 0.2), value: importedFileName)
                .appAnimation(.easeInOut(duration: 0.2), value: importError)
            }
        }
        // #3 / #57 — Drop fichier directement sur la carte (Finder & autres sources)
        .onDrop(of: [.fileURL, .plainText, .rtf,
                     UTType(filenameExtension: "docx") ?? .data,
                     UTType(filenameExtension: "doc")  ?? .data],
                isTargeted: $isFileDropTarget) { providers in
            guard let provider = providers.first else { return false }
            // Prefer file URL
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                _ = provider.loadDataRepresentation(forTypeIdentifier: "public.file-url") { data, _ in
                    guard let data else { return }
                    // Finder encodes as a file:// URL string (UTF-8, possibly NUL-terminated)
                    let cleaned = data.filter { $0 != 0 }
                    guard let urlStr = String(data: cleaned, encoding: .utf8),
                          let url = URL(string: urlStr) else { return }
                    DispatchQueue.main.async { importFromURL(url) }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                // Plain text content dropped directly (e.g. from TextEdit)
                _ = provider.loadDataRepresentation(forTypeIdentifier: "public.plain-text") { data, _ in
                    guard let data, let text = String(data: data, encoding: .utf8) else { return }
                    DispatchQueue.main.async { importPlainText(text, fileName: "texte déposé") }
                }
            }
            return true
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accent, lineWidth: 2)
                .opacity(isFileDropTarget ? 1 : 0)
                .appAnimation(.easeInOut(duration: 0.15), value: isFileDropTarget)
        )
        // #59 — Onboarding contextuel
        .onboardingTooltip(
            key: "dashboard_entry",
            message: "Saisissez votre compteur de caractères ici, ou glissez-déposez un fichier pour l'importer automatiquement.",
            icon: "pencil.and.outline",
            alignment: .bottom
        )
    }

    // MARK: - Mini-graphique 14 jours

    @ViewBuilder
    private var miniChartSection: some View {
        if let project = activeProject {
            let data = last14DaysData(for: project)
            if data.contains(where: { $0 > 0 }) {
                VStack(spacing: 10) {
                    SectionHeader("Activité récente")
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 4) {
                                Text("14 derniers jours · \(project.name)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                                    .lineLimit(1)
                                Spacer()
                                let total = data.reduce(0, +)
                                Text(store.formatCount(total))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                            MiniBarChartView(data: data, color: .accent, goal: store.data.dailyGoal)
                                .frame(height: 44)
                        }
                    }
                }
            }
        }
    }

    private func last14DaysData(for project: Project) -> [Int] {
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let totals = store.dailyTotals(projectId: project.id)
        return (0..<14).reversed().map { offset -> Int in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            return totals[DataStore.dateString(from: date)] ?? 0
        }
    }

    // MARK: - Progress section

    private var progressSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Progression")
            GlassCard {
                VStack(spacing: 0) {
                    ProgressBarView(
                        label: "Objectif du jour",   // 5.18 : objectif du jour de la semaine (comme la barre du haut)
                        icon: "sun.max.fill",
                        value: store.dailyProgress,
                        goal: store.effectiveDailyGoal,
                        color: Color.accent,
                        trackColor: Color.accent.opacity(0.12)
                    )
                    .help(store.effectiveDailyGoal > 0
                          ? "\(store.formatCount(store.dailyProgress)) / \(store.formatCount(store.effectiveDailyGoal)) \(store.data.useWordCount ? "mots" : "car.") · \(min(100, Int(Double(store.dailyProgress) / Double(store.effectiveDailyGoal) * 100)))% de l'objectif du jour"
                          : "\(store.formatCount(store.dailyProgress)) \(store.data.useWordCount ? "mots" : "car.") aujourd'hui")
                    if let ddg = store.deadlineDailyGoal, store.deadlineDailyGoalDiffers {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 10)).foregroundColor(Color(red: 0.929, green: 0.329, blue: 0.329))
                            Text(echeanceLabel(ddg))   // 5.18 : le but d'abord, l'effort ensuite
                                .font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color(red: 0.929, green: 0.329, blue: 0.329).opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.929, green: 0.329, blue: 0.329).opacity(0.15), lineWidth: 1))
                        .padding(.top, 4)
                    } else if store.adaptedDailyGoalDiffers {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 10)).foregroundColor(.accentWarm)
                            Text("Objectif adaptatif : \(store.formatCount(store.adaptedDailyGoal)) aujourd'hui")
                                .font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.accentWarm.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentWarm.opacity(0.15), lineWidth: 1))
                        .padding(.top, 8)
                    }

                    Divider().padding(.vertical, 12)

                    ProgressBarView(
                        label: "30 derniers jours",
                        icon: "calendar",
                        value: store.monthlyProgress,
                        goal: store.data.monthlyGoal,
                        color: Color.accentWarm,
                        trackColor: Color.accentWarm.opacity(0.12)
                    )

                    if let chapter = activeChapter {
                        Divider().padding(.vertical, 12)
                        ProgressBarView(
                            label: chapter.name,
                            icon: "book.closed.fill",
                            value: store.chapterProgress,
                            goal: chapter.goal,
                            color: Color.accentGreen,
                            trackColor: Color.accentGreen.opacity(0.12)
                        )
                        .help(chapter.goal > 0
                              ? "\(store.formatCount(store.chapterProgress)) / \(store.formatCount(chapter.goal)) \(store.data.useWordCount ? "mots" : "car.") · \(min(100, Int(Double(store.chapterProgress) / Double(chapter.goal) * 100)))% du chapitre"
                              : "\(store.formatCount(store.chapterProgress)) \(store.data.useWordCount ? "mots" : "car.") dans ce chapitre")
                        ChapterGoalStatusLine(store: store, chapter: chapter, total: store.chapterProgress)
                    }
                }
            }
        }
    }

    // MARK: - Quick stats 2×2

    private var quickStatsGrid: some View {
        let vel = store.velocity14Days
        let weekly = store.weeklyProgress
        let weeklyGoal = store.data.weeklyGoal
        let weeklyPct = weeklyGoal > 0 ? min(100, Int(Double(weekly) / Double(weeklyGoal) * 100)) : 0
        let daysLeft: Int? = {
            guard let project = activeProject else { return nil }
            guard let eta = store.estimatedCompletionDate(for: project.id) else { return nil }
            return max(0, Calendar.current.dateComponents([.day], from: Date(), to: eta).day ?? 0)
        }()
        let bestDay = store.allTimeBestDay
        let bestDayDate = store.allTimeBestDayDate
        let daysWritten = store.daysWrittenThisMonth
        let daysInMonth = store.daysInCurrentMonth

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            // Vitesse
            StatMiniCard(
                icon: "bolt.fill",
                iconBg: Color.accent.opacity(0.12),
                iconColor: .accent,
                value: store.formatCount(vel) + "/j",
                label: "vitesse · 14j",
                badge: nil,
                badgeColor: .clear
            )
            // Objectif hebdo
            StatMiniCard(
                icon: "target",
                iconBg: Color.blue.opacity(0.12),
                iconColor: .blue,
                value: weeklyGoal > 0 ? "\(weeklyPct)%" : "—",
                label: "objectif hebdo",
                badge: weeklyPct >= 100 ? "✓" : nil,
                badgeColor: .accentGreen
            )
            // Total semaine
            StatMiniCard(
                icon: "chart.bar.fill",
                iconBg: Color.accentGreen.opacity(0.10),
                iconColor: .accentGreen,
                value: store.formatCount(weekly),
                label: "cette semaine",
                badge: nil,
                badgeColor: .clear
            )
            // Projection
            StatMiniCard(
                icon: "flag.fill",
                iconBg: Color.accentWarm.opacity(0.10),
                iconColor: .accentWarm,
                value: daysLeft.map { "\($0) j" } ?? "—",
                label: "avant la fin",
                badge: nil,
                badgeColor: .clear
            )
            // #2 — Record personnel
            StatMiniCard(
                icon: "trophy.fill",
                iconBg: Color.yellow.opacity(0.12),
                iconColor: .yellow,
                value: bestDay > 0 ? store.formatCount(bestDay) : "—",
                label: bestDayDate.map { "record · \($0)" } ?? "record",
                badge: nil,
                badgeColor: .clear
            )
            // #4 — Jours écrits ce mois
            StatMiniCard(
                icon: "calendar.badge.checkmark",
                iconBg: Color.purple.opacity(0.10),
                iconColor: .purple,
                value: "\(daysWritten) / \(daysInMonth)",
                label: "jours écrits · mois",
                badge: daysWritten >= daysInMonth ? "✓" : nil,
                badgeColor: .accentGreen
            )
        }
    }

    // MARK: - Project Completion Card (amélioration #11)

    @ViewBuilder
    private var projectCompletionCard: some View {
        if let project = activeProject {
            let eta = store.estimatedCompletionDate(for: project.id)
            let totalGoal    = project.chapters.reduce(0) { $0 + $1.goal }
            // Use latestTotalsAll — O(1) per chapter, already cached per dataVersion
            let latests      = store.latestTotalsAll
            let totalWritten = project.chapters.reduce(0) { $0 + (latests[$1.id] ?? 0) }
            let ratio = store.projectRatiosAll[project.id] ?? 0.0

            // Calcul du statut deadline
            let allDeadlines = project.chapters.compactMap { ch -> Date? in
                guard let str = ch.deadline else { return nil }
                return DataStore.parseDate(str)
            }
            let nextDeadline = allDeadlines.filter { $0 > Date() }.sorted().first
            let isOnTrack: Bool = {
                guard let eta, let deadline = nextDeadline else { return true }
                return eta <= deadline
            }()
            let statusColor: Color = ratio >= 1.0 ? .accentGreen : (isOnTrack ? .accent : .orange)

            GlassCard {
                HStack(spacing: 12) {
                    ProgressRingView(
                        ratio: ratio,
                        color: statusColor,
                        lineWidth: 3,
                        size: 38,
                        label: "\(Int(ratio * 100))%"
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if ratio >= 1.0 {
                            Label("Projet terminé", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentGreen)
                        } else if let eta {
                            HStack(spacing: 4) {
                                Image(systemName: isOnTrack ? "arrow.right.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(statusColor)
                                Text("Fin estimée : \(DataStore.formatDate(eta))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("Pas assez de données pour projeter")
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(store.formatCountShort(totalWritten))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("/ \(store.formatCountShort(totalGoal))")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }
                }
                .padding(2)
            }
        }
    }

    /// 5.18 : « Échéance 27 novembre 2026 · 36 j de retard à ce rythme »
    private func chapterDeadlineSubtitle(chapter: Chapter, projectId: UUID) -> String {
        guard let deadline = chapter.deadline.flatMap(DataStore.parseDate) else { return "Sans échéance" }
        var s = "Échéance \(DataStore.formatDate(deadline))"
        if let eta = store.estimatedCompletionDate(for: chapter.id, in: projectId) {
            let cal = Calendar.current
            let late = cal.dateComponents([.day], from: cal.startOfDay(for: deadline), to: cal.startOfDay(for: eta)).day ?? 0
            if late > 0 { s += " · \(late) j de retard à ce rythme" }
            else if late < 0 { s += " · \(-late) j d'avance" }
        }
        return s
    }

    @ViewBuilder
    private var planningSection: some View {
        if let project = activeProject, let chapter = activeChapter {
            VStack(spacing: 10) {
                SectionHeader("Planification")
                GlassCard {
                    VStack(spacing: 0) {
                        planningRow(
                            title: "Fin projet",
                            value: store.estimatedCompletionDate(for: project.id).map(DataStore.formatDate(_:)) ?? "—",
                            subtitle: "Projection 14 jours"
                        )
                        Divider().padding(.vertical, 10)
                        planningRow(
                            title: "Fin chapitre",
                            value: store.estimatedCompletionDate(for: chapter.id, in: project.id).map(DataStore.formatDate(_:)) ?? "—",
                            subtitle: chapterDeadlineSubtitle(chapter: chapter, projectId: project.id)
                        )

                        // Velocity section
                        if currentVelocity > 0 || chapterRequiredVelocity > 0 {
                            Divider().padding(.vertical, 10)
                            velocityRow(chapter: chapter)
                        }
                    }
                }
            }
        }
    }

    private var currentVelocity: Int {
        guard let project = activeProject else { return 0 }
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        let totals = store.dailyTotals(projectId: project.id)
        var increments: [Int] = []
        for offset in 1...14 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let total = totals[DataStore.dateString(from: date)] ?? 0
            if total > 0 { increments.append(total) }
        }
        guard !increments.isEmpty else { return 0 }
        return increments.reduce(0, +) / increments.count
    }

    // 5.18 : un seul calcul du rythme d'échéance, celui du DataStore (profil de rythme, jours d'écriture).
    // Avant : un second calcul naïf ici (reste ÷ jours calendaires depuis l'heure courante) donnait un autre chiffre.
    private var chapterRequiredVelocity: Int { store.deadlineDailyGoal ?? 0 }

    private var daysToChapterDeadline: Int? {
        guard let chapter = activeChapter,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: deadline)).day ?? 0
        return days >= 0 ? days : nil
    }

    /// « Pour tenir le 27 novembre : 13 060 par jour (6 183 de plus qu'à ton rythme) »
    private func echeanceLabel(_ perDay: Int) -> String {
        let date = activeChapter?.deadline.flatMap(DataStore.parseDate).map { DataStore.formatDate($0) } ?? "l'échéance"
        var s = "Pour tenir le \(date) : \(store.formatCount(perDay)) par jour"
        let gap = perDay - currentVelocity
        if currentVelocity > 0 && gap > 0 { s += " (\(store.formatCount(gap)) de plus qu'à ton rythme)" }
        return s
    }

    @ViewBuilder
    private func velocityRow(chapter: Chapter) -> some View {
        let vel = currentVelocity
        let req = chapterRequiredVelocity
        let daysLeft = daysToChapterDeadline

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("À MON RYTHME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1)
                Spacer()
            }

            HStack(spacing: 12) {
                // Current velocity
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cadence actuelle")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                    Text(vel > 0 ? store.formatCount(vel) + "/j" : "—")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                }

                if req > 0 {
                    Divider().frame(height: 30)

                    // Required velocity
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rythme pour l'échéance")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                        Text(store.formatCount(req) + "/j")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(vel >= req ? .accentGreen : .accentWarm)
                    }
                }

                if let days = daysLeft {
                    Divider().frame(height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Jours restants")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                        Text("\(days) j")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(days < 7 ? Color(red: 0.929, green: 0.329, blue: 0.329) : .primary)
                    }
                }

                Spacer()
            }

            // Adaptive message
            if let msg = adaptiveMessage(vel: vel, req: req, daysLeft: daysToChapterDeadline) {
                HStack(spacing: 6) {
                    Image(systemName: vel > 0 && req > 0 && vel >= req ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(vel > 0 && req > 0 && vel >= req ? .accentGreen : .accentWarm)
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(
                    (vel > 0 && req > 0 && vel >= req ? Color.accentGreen : Color.accentWarm).opacity(0.07)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func adaptiveMessage(vel: Int, req: Int, daysLeft: Int?) -> String? {
        guard vel > 0 else { return nil }
        if req > 0 {
            if vel >= req {
                return "Tu es en avance. Continue à ce rythme !"
            } else {
                let extra = req - vel
                return "Il faut écrire \(store.formatCount(extra))/j de plus pour tenir la deadline."
            }
        } else if let days = daysLeft {
            return "Plus que \(days) jour\(days > 1 ? "s" : "") avant la deadline."
        }
        return nil
    }

    private func planningRow(title: String, value: String, subtitle: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
    }


    // MARK: - Mini-calendrier hebdomadaire

    @ViewBuilder
    private var weekCalendarSection: some View {
        let goal = store.data.dailyGoal
        let days = currentWeekData
        let anyActivity = days.contains { $0.written > 0 }
        if anyActivity || goal > 0 {
            VStack(spacing: 12) {
                SectionHeader("Cette semaine")
                GlassCard {
                    HStack(spacing: 4) {
                        ForEach(days.indices, id: \.self) { i in
                            weekDayCell(day: days[i], goal: goal)
                        }
                    }
                }
            }
        }
    }

    private struct WeekDayData {
        let date: Date
        let dateStr: String
        let written: Int
        let isToday: Bool
        let isFuture: Bool
        let letter: String
        let dayNumber: Int
    }

    // Lit directement le cache DataStore — O(1) par frappe au lieu de O(7×N×entries).
    private var currentWeekData: [WeekDayData] {
        store.currentWeekInfo.map { info in
            WeekDayData(
                date:      DataStore.parseDate(info.dateStr) ?? Date(),
                dateStr:   info.dateStr,
                written:   info.written,
                isToday:   info.isToday,
                isFuture:  info.isFuture,
                letter:    info.letter,
                dayNumber: info.dayNumber
            )
        }
    }

    private func weekDayCell(day: WeekDayData, goal: Int) -> some View {
        let ratio: Double = goal > 0 ? min(1.0, Double(day.written) / Double(goal)) : 0
        let reached = goal > 0 && day.written >= goal
        let hasWriting = day.written > 0

        let circleColor: Color
        if day.isFuture        { circleColor = Color.white.opacity(0.05) }
        else if reached        { circleColor = Color.accentGreen }
        else if hasWriting     { circleColor = Color.accent.opacity(max(0.30, ratio * 0.9)) }
        else                   { circleColor = Color.white.opacity(0.07) }

        return VStack(spacing: 5) {
            // Lettre du jour
            Text(day.letter)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(day.isToday ? .accent : .labelMuted)

            // Numéro du jour
            Text("\(day.dayNumber)")
                .font(.system(size: 12, weight: day.isToday ? .bold : .regular))
                .foregroundColor(day.isFuture ? .labelMuted.opacity(0.4) : .primary)

            // Indicateur
            ZStack {
                Circle().fill(circleColor).frame(width: 26, height: 26)
                if reached {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                } else if hasWriting && !day.isFuture {
                    Text("\(Int(ratio * 100))%")
                        .font(.system(size: 7, weight: .bold)).foregroundColor(.white)
                }
            }

            // Mini barre de progression
            if goal > 0 && !day.isFuture {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.08)).frame(height: 2)
                        if ratio > 0 {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(reached ? Color.accentGreen : Color.accent)
                                .frame(width: geo.size.width * ratio, height: 2)
                        }
                    }
                }
                .frame(height: 2)
            } else {
                Color.clear.frame(height: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8).padding(.horizontal, 4)
        .background(day.isToday ? Color.accent.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(day.isToday
            ? RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.25), lineWidth: 1)
            : nil)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        let totals = store.dailyTotals()
        let hasData = !totals.isEmpty
        return VStack(spacing: 10) {
            SectionHeader("Insights")
            GlassCard {
                if !hasData {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundColor(.labelMuted)
                        Text("Pas encore de données.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 0) {
                        insightRow(
                            icon: "star.fill", color: .accent,
                            title: "Meilleur jour",
                            value: insightBestWeekday.name,
                            subtitle: insightBestWeekday.avg > 0 ? "moy. \(store.formatCount(insightBestWeekday.avg))" : "—"
                        )
                        Divider().padding(.vertical, 9)
                        insightRow(
                            icon: "checkmark.seal.fill", color: .accentGreen,
                            title: "Objectif 30j",
                            value: store.data.dailyGoal > 0 ? "\(insightGoalRate)%" : "—",
                            subtitle: store.data.dailyGoal > 0 ? "\(insightGoalDays) / 30 jours" : "Aucun objectif"
                        )
                        Divider().padding(.vertical, 9)
                        insightRow(
                            icon: "trophy.fill", color: .accentWarm,
                            title: "Record",
                            value: insightRecord.chars > 0 ? store.formatCount(insightRecord.chars) : "—",
                            subtitle: insightRecord.chars > 0 ? insightRecord.label : "—"
                        )
                        Divider().padding(.vertical, 9)
                        insightRow(
                            icon: "chart.line.uptrend.xyaxis",
                            color: Color(red: 0.706, green: 0.502, blue: 0.984),
                            title: "Moy. 30j actifs",
                            value: insightAvg30 > 0 ? store.formatCount(insightAvg30) : "—",
                            subtitle: "\(insightActiveDays30) jours actifs"
                        )
                    }
                }
            }
        }
    }

    private func insightRow(icon: String, color: Color, title: String, value: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Insights computed data (backed by DashboardStatsCache)

    private var insightBestWeekday: (name: String, avg: Int) {
        let frenchDays = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
        if let c = statsCache, let best = c.bestWeekday {
            return (best.day, best.count)
        }
        // Fallback (cache not yet built)
        let totals = store.dailyTotals()
        let cal = Calendar(identifier: .gregorian)
        var byWeekday: [Int: [Int]] = [:]
        for (dateStr, val) in totals {
            guard val > 0, let date = DataStore.parseDate(dateStr) else { continue }
            byWeekday[cal.component(.weekday, from: date), default: []].append(val)
        }
        guard !byWeekday.isEmpty else { return ("—", 0) }
        let best = byWeekday.max { ($0.value.reduce(0,+)/$0.value.count) < ($1.value.reduce(0,+)/$1.value.count) }!
        return (frenchDays[best.key - 1], best.value.reduce(0,+) / best.value.count)
    }

    private var insightGoalDays: Int {
        if let c = statsCache { return c.goalDays30 }
        guard store.data.dailyGoal > 0 else { return 0 }
        let cal = Calendar(identifier: .gregorian); let totals = store.dailyTotals()
        return (0..<30).filter { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: Date()) else { return false }
            return (totals[DataStore.dateString(from: d)] ?? 0) >= store.data.dailyGoal
        }.count
    }

    private var insightGoalRate: Int { Int(Double(insightGoalDays) / 30.0 * 100) }

    private var insightRecord: (chars: Int, label: String) {
        let totals = store.dailyTotals()
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return (0, "") }
        let label = DataStore.parseDate(best.key).map { DataStore.formatDate($0) } ?? best.key
        return (best.value, label)
    }

    private var insightActiveDays30: Int { statsCache?.activeDays30 ?? 0 }

    private var insightAvg30: Int { statsCache?.avg30 ?? 0 }

    // MARK: - Empty state

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 16) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundColor(.labelMuted)
                Text(store.data.projects.isEmpty
                     ? "Créez un projet pour commencer"
                     : "Ajoutez un chapitre à ce projet")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                Button("Ouvrir les projets") {
                    withAppAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accent)
                    .shadow(color: Color.accent.opacity(0.35), radius: 8, x: 0, y: 3))
                .buttonStyle(.pressable)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Helpers

    private var formattedDate: String {
        DataStore.formatLongDate(Date(), capitalize: true)
    }

    private var formattedSelectedDate: String {
        DataStore.formatDate(selectedDate)
    }

    private func saveEntry(_ count: Int, isCorrection: Bool) {
        guard let chapter = activeChapter,
              let project = activeProject else { return }
        inputText = "\(count)"
        withAppAnimation { store.setTotalForDate(count, for: chapter.id, in: project.id, date: selectedDateStr, isCorrection: isCorrection) }
        withAppAnimation(.easeOut(duration: 0.15)) { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAppAnimation(.easeOut(duration: 0.15)) { savedConfirmation = false }
        }
        checkMilestones()
    }

    private func checkMilestones() {
        let streak = store.currentStreak
        let smallMilestones = [7, 14]
        let bigMilestones   = [30, 60, 100, 200, 365]

        // Petit jalon → pulse du badge
        if smallMilestones.contains(streak) && streak > lastStreakMilestone {
            lastStreakMilestone = streak
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                streakPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { streakPulse = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { streakPulse = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { streakPulse = false }
            }
        }

        // Grand jalon streak → toast
        if bigMilestones.contains(streak) && streak > lastStreakMilestone {
            lastStreakMilestone = streak
            store.showMilestone(.streak(streak))
        }

        // 100% d'objectif chapitre → toast
        if let chapter = activeChapter, chapter.goal > 0 {
            let progress = store.chapterProgress
            if progress >= chapter.goal {
                store.showMilestone(.chapterComplete(chapter.name))
            }
        }
    }

    // MARK: - Import fichier (.docx / .doc / .rtf / .txt) — #3

    private func importFile() {
        let panel = NSOpenPanel()
        panel.title = "Importer un document"
        panel.message = "Le nombre de mots ou caractères sera extrait automatiquement"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .plainText,
            .rtf,
            UTType(filenameExtension: "doc")  ?? .data,
            UTType(filenameExtension: "docx") ?? .data,
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importDocument(at: url)
    }

    // #57 — Drop texte brut (sans fichier)
    private func importPlainText(_ text: String, fileName: String) {
        let count: Int
        if store.data.useWordCount {
            count = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        } else {
            count = text.filter { !$0.isWhitespace }.count
        }
        DispatchQueue.main.async {
            self.inputText      = "\(count)"
            self.inputClusterToken = UUID()
            self.importedFileName = fileName
        }
    }

    // #3 — Drop fichier : extraction depuis une URL
    private func importFromURL(_ url: URL) {
        importDocument(at: url)
    }

    /// Extraction + comptage hors du main thread, résultat appliqué sur le main actor.
    private func importDocument(at url: URL) {
        let useWordCount = store.data.useWordCount
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.extractCount(from: url, useWordCount: useWordCount)
            }.value
            guard let count = result else {
                importError = "textutil indisponible"
                return
            }
            inputText = "\(count)"
            inputClusterToken = UUID()
            importedFileName = url.lastPathComponent
        }
    }

    /// Convertit le document en texte via textutil puis compte mots/caractères.
    /// La sortie est écrite dans un fichier temporaire (-output) plutôt qu'un
    /// pipe : pas de blocage quand le texte dépasse la taille du tampon (64 Ko).
    nonisolated private static func extractCount(from url: URL, useWordCount: Bool) -> Int? {
        let fm = FileManager.default
        let tmpURL = fm.temporaryDirectory
            .appendingPathComponent("textutil-\(UUID().uuidString)")
            .appendingPathExtension("txt")
        defer { try? fm.removeItem(at: tmpURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-encoding", "UTF-8", "-output", tmpURL.path, url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError  = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0,
              let raw = try? Data(contentsOf: tmpURL) else { return nil }
        let text = String(data: raw, encoding: .utf8) ?? ""

        if useWordCount {
            return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        } else {
            return text.filter { !$0.isWhitespace }.count
        }
    }

    private func saveNote() {
        guard let chapter = activeChapter, let project = activeProject, hasExistingEntry else { return }
        store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: selectedDateStr)
    }

    private func refreshInput() {
        defer { inputClusterToken = UUID() }
        guard let chapter = activeChapter else {
            inputText = ""; noteText = ""; chapterNotesText = ""
            notesPlanText = ""; notesIdeasText = ""; notesBlockersText = ""
            nextStepText = ""
            return
        }
        let entry = chapter.entryForDate(selectedDateStr)
        inputText        = entry.map { "\($0.totalCount)" } ?? ""
        noteText         = entry?.note ?? ""
        chapterNotesText = chapter.notes ?? ""
        notesPlanText    = chapter.notesPlan ?? ""
        notesIdeasText   = chapter.notesIdeas ?? ""
        notesBlockersText = chapter.notesBlockers ?? ""
        nextStepText     = chapter.nextStep ?? ""
    }

    private func scheduleNotesSave(chapter: Chapter, project: Project) {
        chapterNotesDebouncer.schedule {
            store.updateChapterNotes(
                plan:     notesPlanText.isEmpty     ? nil : notesPlanText,
                ideas:    notesIdeasText.isEmpty    ? nil : notesIdeasText,
                blockers: notesBlockersText.isEmpty ? nil : notesBlockersText,
                general:  chapterNotesText.isEmpty  ? nil : chapterNotesText,
                for: chapter.id, in: project.id
            )
        }
    }

    private func saveChapterNotes(chapterId: UUID, projectId: UUID, text: String) {
        guard let projIdx = store.data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = store.data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        store.data.projects[projIdx].chapters[chapIdx].notes = text.isEmpty ? nil : text
        store.save()
    }
}

// MARK: - Writing entry input cluster
//
// Owns its own @State `text` so that typing only re-evaluates THIS subview,
// not the entire 2000+ line DashboardView.body. The parent passes `initialText`
// once (and forces a remount via `.id(inputClusterToken)` whenever it needs
// to push a new value — file import, date/chapter change, delete, etc.).
private struct WritingEntryInputCluster: View {
    let useWordCount: Bool
    let initialText: String
    let entryForHistory: DailyEntry?
    let previousTotal: Int
    let savedConfirmation: Bool
    @FocusState.Binding var focused: Bool
    @Binding var isDictating: Bool
    let onSave: (Int, Bool) -> Void

    @State private var text: String
    @State private var isCorrection: Bool
    @State private var showEntryHistory: Bool = false

    init(useWordCount: Bool,
         initialText: String,
         entryForHistory: DailyEntry?,
         previousTotal: Int,
         savedConfirmation: Bool,
         focused: FocusState<Bool>.Binding,
         isDictating: Binding<Bool>,
         onSave: @escaping (Int, Bool) -> Void) {
        self.useWordCount = useWordCount
        self.initialText = initialText
        self.entryForHistory = entryForHistory
        self.previousTotal = previousTotal
        self.savedConfirmation = savedConfirmation
        self._focused = focused
        self._isDictating = isDictating
        self.onSave = onSave
        self._text = State(initialValue: initialText)
        self._isCorrection = State(initialValue: entryForHistory?.isCorrection ?? false)
    }

    private var inputInt: Int? {
        Int(text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private func commit() {
        guard let n = inputInt else { return }
        onSave(n, isCorrection && n < previousTotal)
    }

    var body: some View {
        let n = inputInt           // memoize once per render (was 3× string-cleaning)
        let hasValue = n != nil
        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                inputRow
                saveButton(hasValue: hasValue)
            }
            if let n, n < previousTotal {
                correctionRow(delta: n - previousTotal)
            }
            if let n, n > 0 {
                liveCounter(n: n)
            }
        }
        .padding(.top, 12)
        .appAnimation(.easeInOut(duration: 0.15), value: hasValue)
        .onReceive(NotificationCenter.default.publisher(for: .dashboardSave)) { _ in
            commit()
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat.123")
                .foregroundColor(.labelMuted)
                .font(.system(size: 12))
            NativeNumericTextField(
                text: $text,
                placeholder: "ex: 15 340",
                onSubmit: { commit() }
            )
            .frame(maxWidth: .infinity)
            if !text.isEmpty {
                Text(useWordCount ? "mots" : "car.")
                    .foregroundColor(.labelMuted)
                    .font(.system(size: 12))
            }
            VoiceDictationButton(isDictating: $isDictating) { spokenNumber in
                text = "\(spokenNumber)"
                focused = false
            }
            if let entry = entryForHistory, !entry.editHistory.isEmpty {
                Button {
                    showEntryHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
                .buttonStyle(.pressable)
                .help("Historique des modifications")
                .accessibilityLabel("Historique des modifications")
                .popover(isPresented: $showEntryHistory, arrowEdge: .bottom) {
                    EntryEditHistoryPopover(entry: entry, useWords: useWordCount)
                }
                .accessibilityLabel("Historique des modifications")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isDictating ? Color.accent.opacity(0.08) : Color.fieldBg)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(isDictating ? Color.accent : Color.cardBorder, lineWidth: isDictating ? 1.5 : 1))
        )
        .appAnimation(.easeInOut(duration: 0.2), value: isDictating)
    }

    // Static gradients — avoid building a fresh LinearGradient per render.
    private static let saveGradient = LinearGradient(
        colors: [.accent, .accentWarm], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let savedGradient = LinearGradient(
        colors: [.accentGreen, .accentGreen], startPoint: .topLeading, endPoint: .bottomTrailing)

    private func saveButton(hasValue: Bool) -> some View {
        Button(action: commit) {
            HStack(spacing: 5) {
                Image(systemName: savedConfirmation ? "checkmark" : "arrow.down.circle.fill")
                    .font(.system(size: 12))
                Text(savedConfirmation ? "Enregistré" : "Sauvegarder")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(savedConfirmation ? .white : .black)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(savedConfirmation ? Self.savedGradient : Self.saveGradient)
                    .shadow(color: Color.accent.opacity(0.3), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.pressable)
        .disabled(!hasValue)
        .help("Sauvegarder · ⌘S")
        .appAnimation(.easeInOut(duration: 0.2), value: savedConfirmation)
    }

    // Total en baisse : du texte a été retiré. La case marque le jour comme
    // une correction, qui ne casse pas la série.
    private func correctionRow(delta: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                isCorrection.toggle()
                // Entrée déjà enregistrée avec ce total : la marque s'applique tout de suite.
                if let entry = entryForHistory, entry.totalCount == inputInt { commit() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isCorrection ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(isCorrection ? .accentWarm : .labelMuted)
                    Text("Correction")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isCorrection ? .accentWarm : .primary)
                }
            }
            .buttonStyle(.pressable)
            .help("Jour de correction : du texte a été retiré. Le jour compte dans la série.")
            .accessibilityAddTraits(isCorrection ? .isSelected : [])
            Text("\(DataStore.formatNumber(delta)) \(useWordCount ? "mots" : "car.") par rapport au total précédent")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
            Spacer()
        }
        .padding(.leading, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func liveCounter(n: Int) -> some View {
        HStack(spacing: 10) {
            if useWordCount {
                Label("\(DataStore.formatNumber(n)) mots", systemImage: "text.word.spacing")
                    .font(.system(size: 10)).foregroundColor(.accent)
                Text("·").foregroundColor(.labelMuted).font(.system(size: 10))
                Label("≈ \(DataStore.formatNumber(n * 5)) car.", systemImage: "textformat.123")
                    .font(.system(size: 10)).foregroundColor(.labelMuted)
            } else {
                Label("\(DataStore.formatNumber(n)) car.", systemImage: "textformat.123")
                    .font(.system(size: 10)).foregroundColor(.accent)
                Text("·").foregroundColor(.labelMuted).font(.system(size: 10))
                Label("≈ \(DataStore.formatNumber(max(1, n / 5))) mots", systemImage: "text.word.spacing")
                    .font(.system(size: 10)).foregroundColor(.labelMuted)
            }
            Spacer()
        }
        .padding(.leading, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Native text field
//
// Wraps NSTextField directly — SwiftUI's TextField bridges to NSTextField
// but with overhead that adds latency to per-keystroke updates in complex
// hierarchies. This wrapper goes through SwiftUI only on focus / external
// resets, not on every character typed.
private struct NativeNumericTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField()
        tf.delegate = context.coordinator
        tf.placeholderString = placeholder
        tf.stringValue = text
        tf.isBordered = false
        tf.drawsBackground = false
        tf.focusRingType = .none
        tf.isAutomaticTextCompletionEnabled = false
        tf.cell?.usesSingleLineMode = true
        tf.cell?.wraps = false
        tf.cell?.isScrollable = true
        tf.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        tf.lineBreakMode = .byTruncatingTail
        context.coordinator.observeFocusRequests(textField: tf)
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        // Disable expensive auto-text features once the field editor exists
        // (currentEditor() returns nil before the field is first focused).
        if let textView = nsView.currentEditor() as? NSTextView,
           !context.coordinator.didDisableAutoFeatures {
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            context.coordinator.didDisableAutoFeatures = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeNumericTextField
        var didDisableAutoFeatures: Bool = false
        private weak var textField: NSTextField?
        private var focusObserver: NSObjectProtocol?

        init(_ parent: NativeNumericTextField) { self.parent = parent }

        deinit {
            if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        }

        func observeFocusRequests(textField: NSTextField) {
            self.textField = textField
            focusObserver = NotificationCenter.default.addObserver(
                forName: .dashboardFocusInput, object: nil, queue: .main
            ) { [weak self] _ in
                guard let tf = self?.textField, let win = tf.window else { return }
                win.makeFirstResponder(tf)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = obj.object as? NSTextField else { return }
            parent.text = tf.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
        }
    }
}

// MARK: - Mini bar chart

private struct MiniBarChartView: View {
    let data: [Int]
    let color: Color
    let goal: Int

    /// 5.18 : échelle plafonnée quand une journée hors norme (import, rattrapage) écraserait les autres.
    /// Plafond = 2 × le 75e centile des jours non nuls (et au moins l'objectif) ; la barre dépassante
    /// est pleine, marquée d'une encoche, valeur exacte au survol.
    private var maxVal: CGFloat {
        let peak = CGFloat(max(data.max() ?? 0, goal > 0 ? goal : 0, 1))
        let nonZero = data.filter { $0 > 0 }.sorted()
        guard nonZero.count >= 4 else { return peak }
        let p75 = CGFloat(nonZero[Int(Double(nonZero.count - 1) * 0.75)])
        let cap = max(p75 * 2, CGFloat(goal), 1)
        return min(peak, cap)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                // Ligne d'objectif
                if goal > 0 {
                    let goalRatio = min(1.0, CGFloat(goal) / maxVal)
                    Rectangle()
                        .fill(Color.labelMuted.opacity(0.18))
                        .frame(height: 1)
                        .offset(y: geo.size.height * (1 - goalRatio))
                }

                // Barres
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(data.indices, id: \.self) { i in
                        let v = data[i]
                        let ratio = CGFloat(v) / maxVal
                        let isToday = i == data.count - 1
                        let reachedGoal = goal > 0 && v >= goal

                        VStack(spacing: 0) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    reachedGoal ? Color.accentGreen :
                                    isToday ? color :
                                    color.opacity(max(0.18, min(1, ratio) * 0.80))
                                )
                                .frame(height: max(2, geo.size.height * min(1, ratio)))
                                .overlay(alignment: .top) {
                                    if ratio > 1 {   // hors échelle : encoche
                                        Rectangle().fill(Color.cardBg).frame(height: 2).offset(y: 5)
                                    }
                                }
                        }
                        .help(v > 0 ? "\(DataStore.formatNumber(v)) car." + (ratio > 1 ? " (hors échelle)" : "") : "Rien ce jour-là")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Stat Mini Card

private struct StatMiniCard: View {
    let icon: String
    let iconBg: Color
    let iconColor: Color
    let value: String
    let label: String
    let badge: String?
    let badgeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(iconBg)
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(badgeColor)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(badgeColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
        }
        .padding(12)
        .background(Color.fieldBg)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.cardBorder, lineWidth: 1))
    }
}

// MARK: - #39 Feuille de personnalisation des widgets

struct DashboardCustomizeSheet: View {
    @Binding var widgetOrderStored: String
    @Binding var leftWidgetsStored: String
    @Environment(\.dismiss) var dismiss

    @State private var items: [DashboardView.DashboardWidget] = []
    @State private var dropHover: DashboardView.DashboardWidget? = nil

    // MARK: — Layout profiles (#17)
    private struct LayoutProfile {
        let name: String
        let icon: String
        let rightOrder: String
    }
    private let profiles: [LayoutProfile] = [
        LayoutProfile(
            name: "Défaut",
            icon: "square.grid.2x2",
            rightOrder: "healthScore,researchTime,focusChapter,writingSpeed,completion,quickStats,miniChart,dailySession,timeline,progress,planning,insights,weeklyChallenge,monthlyChallenge,weekComparison,upcomingDeadlines,dailyQuote,dailySnapshot"
        ),
        LayoutProfile(
            name: "Focus écriture",
            icon: "pencil.and.outline",
            rightOrder: "focusChapter,writingSpeed,dailySnapshot,dailyQuote,weeklyChallenge,monthlyChallenge,weekComparison,healthScore,completion,quickStats,miniChart,dailySession,timeline,progress,planning,insights,researchTime,upcomingDeadlines"
        ),
        LayoutProfile(
            name: "Synthèse",
            icon: "chart.bar.xaxis",
            rightOrder: "healthScore,completion,quickStats,insights,weekComparison,upcomingDeadlines,progress,timeline,writingSpeed,monthlyChallenge,weeklyChallenge,focusChapter,dailySnapshot,dailyQuote,miniChart,dailySession,planning,researchTime"
        ),
    ]

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Personnaliser la colonne droite")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text("Glisse pour réorganiser · drag depuis le tableau pour déplacer")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(8)
                            .background(Color.cardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .padding(20)

                Divider()

                // Profils prédéfinis
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profils")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    HStack(spacing: 8) {
                        ForEach(profiles, id: \.name) { profile in
                            Button {
                                applyProfile(profile)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: profile.icon)
                                        .font(.system(size: 10, weight: .medium))
                                    Text(profile.name)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.accent)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accent.opacity(0.18), lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                            .help("Appliquer le profil « \(profile.name) »")
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("AFFICHÉS DANS LE TABLEAU DE BORD", count: items.count)
                        activeWidgetsList
                        if !availableItems.isEmpty {
                            sectionHeader("DISPONIBLES À AJOUTER", count: availableItems.count)
                                .padding(.top, 16)
                            availableWidgetsList
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }

                Divider()

                HStack {
                    Button("Tout réinitialiser") {
                        items = DashboardView.DashboardWidget.customizableWidgets
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
                    .buttonStyle(.pressable)

                    Spacer()

                    Button("Appliquer") {
                        widgetOrderStored = items.map(\.rawValue).joined(separator: ",")
                        dismiss()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 9)
                    .background(Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .buttonStyle(.pressable)
                }
                .padding(20)
            }
        }
        .sheetFrame(width: 420, height: 600)
        .onAppear {
            loadItems()
        }
    }

    // MARK: - Sections

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.labelMuted.opacity(0.7))
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Color.labelMuted.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(.bottom, 6)
    }

    private var activeWidgetsList: some View {
        VStack(spacing: 1) {
            ForEach(items, id: \.self) { widget in
                activeWidgetRow(widget)
                if widget != items.last { Divider() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
    }

    private func activeWidgetRow(_ widget: DashboardView.DashboardWidget) -> some View {
        let isTarget = dropHover == widget
        return HStack(spacing: 12) {
            Image(systemName: widget.icon)
                .font(.system(size: 12))
                .foregroundColor(.accent)
                .frame(width: 20)
            Text(widget.label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) {
                    items.removeAll { $0 == widget }
                }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(Color(red: 0.93, green: 0.26, blue: 0.26).opacity(0.7))
            }
            .buttonStyle(.pressable)
            .help("Retirer du tableau de bord")
            .accessibilityLabel("Retirer du tableau de bord")
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted.opacity(0.35))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(isTarget ? Color.accent.opacity(0.07) : Color.cardBg)
        .overlay(alignment: .top) {
            if isTarget {
                Rectangle().fill(Color.accent).frame(height: 2)
            }
        }
        .draggable(widget.rawValue)
        .dropDestination(for: String.self) { dropped, _ in
            guard let raw = dropped.first,
                  let src = DashboardView.DashboardWidget(rawValue: raw),
                  src != widget,
                  let si = items.firstIndex(of: src),
                  let di = items.firstIndex(of: widget) else { return false }
            withAppAnimation(Motion.panel) {
                items.move(fromOffsets: IndexSet(integer: si), toOffset: di < si ? di : di + 1)
            }
            dropHover = nil
            return true
        } isTargeted: { targeted in
            withAppAnimation(.easeInOut(duration: 0.12)) {
                dropHover = targeted ? widget : (dropHover == widget ? nil : dropHover)
            }
        }
    }

    private var availableWidgetsList: some View {
        VStack(spacing: 1) {
            ForEach(availableItems, id: \.self) { widget in
                HStack(spacing: 12) {
                    Image(systemName: widget.icon)
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted.opacity(0.7))
                        .frame(width: 20)
                    Text(widget.label)
                        .font(.system(size: 13))
                        .foregroundColor(.labelMuted)
                    Spacer()
                    Button {
                        withAppAnimation(.easeOut(duration: 0.18)) {
                            items.append(widget)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Ajouter")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accent.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Color.cardBg.opacity(0.5))
                if widget != availableItems.last { Divider() }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder.opacity(0.5), lineWidth: 1))
    }

    private var availableItems: [DashboardView.DashboardWidget] {
        DashboardView.DashboardWidget.customizableWidgets.filter { !items.contains($0) }
    }

    private func loadItems() {
        let keys = widgetOrderStored.split(separator: ",").map(String.init)
        let mapped = keys.compactMap { DashboardView.DashboardWidget(rawValue: $0) }
                         .filter { DashboardView.DashboardWidget.customizableWidgets.contains($0) }
        // On NE remplit PAS automatiquement avec les widgets manquants.
        // Tout ce qui n'est pas dans widgetOrderStored est considéré "disponible".
        items = mapped
    }

    private func applyProfile(_ profile: LayoutProfile) {
        widgetOrderStored = profile.rightOrder
        withAppAnimation(.easeOut(duration: 0.15)) { loadItems() }
    }
}
