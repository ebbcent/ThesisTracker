import SwiftUI

// MARK: - Vue « tableau complet » (tous les widgets, filtré par chapitre)

/// Onglet qui affiche TOUS les widgets disponibles dans une grande grille, sans classement
/// ni bouton d'ajout. Un picker en haut (Général / chapitre) recontextualise toutes les données.
struct WidgetLibraryView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var selectedContext: LibraryContext = .general
    @State private var isEditingVisibility: Bool = false

    enum LibraryContext: Hashable {
        case general
        case chapter(projectId: UUID, chapterId: UUID)

        var isChapter: Bool {
            if case .chapter = self { return true }
            return false
        }
    }

    // Tous les widgets disponibles affichés en grille (réutilisables, ie. avec une vue publique).
    private let widgets: [DashboardView.DashboardWidget] = [
        // Vue d'ensemble écriture
        .healthScore, .writingSpeed, .weekComparison,
        .focusChapter, .researchTime,
        // Heatmap & timeline
        .chapterHeatmap, .timeline, .dailySession,
        // Défis & objectifs
        .weeklyChallenge, .monthlyChallenge,
        .wellbeing, .upcomingDeadlines,
        // Plan & administratif
        .weeklyPlan, .adminChecklist,
        .defenseDate, .painfulChapters,
        // Qualité / relectures
        .supervisorReview, .checkpoints, .defenseNotes,
        // Réflexion
        .journal, .fragments, .monthlyReport,
        // Inspiration
        .dailyQuote, .dailySnapshot
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                contextPicker
                widgetsGrid
            }
            .padding(24)
        }
        .background(AppBackdrop())
        .onChange(of: selectedContext) { _, new in
            applyContextChange(new)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            if !showSidebar {
                Button { withAppAnimation { showSidebar = true } } label: {
                    Image(systemName: "sidebar.left").font(.system(size: 14))
                        .foregroundColor(.labelMuted)
                }
                .buttonStyle(.pressable)
                .help("Afficher la barre latérale")
                .accessibilityLabel("Afficher la barre latérale")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Bibliothèque de widgets")
                    .font(.system(size: 22, weight: .bold, design: AppLook.fontDesign))
                Text(subtitleForContext)
                    .font(.system(size: 12)).foregroundColor(.labelMuted)
            }
            Spacer()
            editVisibilityControls
        }
    }

    @ViewBuilder
    private var editVisibilityControls: some View {
        if selectedContext.isChapter {
            HStack(spacing: 6) {
                if isEditingVisibility, hiddenCount > 0 {
                    Button { resetVisibility() } label: {
                        Text("Tout réafficher (\(hiddenCount))")
                            .font(.system(size: AppLook.fs(11), weight: .medium))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color.accent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                Button {
                    withAppAnimation(.easeOut(duration: 0.15)) {
                        isEditingVisibility.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isEditingVisibility ? "checkmark" : "checklist")
                            .font(.system(size: AppLook.fs(11), weight: .medium))
                        Text(isEditingVisibility ? "Terminer" : "Modifier l'affichage")
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                    }
                    .foregroundColor(isEditingVisibility ? .white : .labelMuted)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(isEditingVisibility ? Color.accent : Color.glassFill)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isEditingVisibility ? Color.accent : Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .help("Masquer ou réafficher des widgets pour ce chapitre")
            }
        }
    }

    private var subtitleForContext: String {
        switch selectedContext {
        case .general:
            return "Vue d'ensemble · tous projets confondus"
        case let .chapter(pid, cid):
            let project = store.data.projects.first { $0.id == pid }
            let chapter = project?.chapters.first { $0.id == cid }
            if let project, let chapter {
                return "\(project.name) › \(chapter.name)"
            }
            return "Chapitre"
        }
    }

    // MARK: - Context picker

    private var contextPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                contextChip(label: "Général", icon: "globe", subtitle: nil,
                            isSelected: selectedContext == .general) {
                    selectedContext = .general
                }
                Divider().frame(height: 26)
                ForEach(store.data.projects.filter { !$0.isArchived }) { project in
                    ForEach(project.chapters) { chapter in
                        let ctx = LibraryContext.chapter(projectId: project.id, chapterId: chapter.id)
                        contextChip(
                            label: chapter.name,
                            icon: chapter.isCompleted ? "checkmark.circle.fill" : "doc.text",
                            subtitle: project.name,
                            isSelected: selectedContext == ctx
                        ) {
                            selectedContext = ctx
                        }
                    }
                }
            }
        }
    }

    private func contextChip(label: String, icon: String, subtitle: String?,
                             isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: AppLook.fs(11)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: AppLook.fs(10)))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .labelMuted)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(isSelected ? Color.accent : Color.glassFill)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.cardBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Grille des widgets

    private var widgetsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 340, maximum: 520), spacing: 16)],
            spacing: 16
        ) {
            ForEach(visibleWidgets, id: \.self) { widget in
                widgetWithVisibilityControls(widget)
            }
        }
    }

    /// La liste des widgets à afficher selon contexte + mode édition.
    private var visibleWidgets: [DashboardView.DashboardWidget] {
        guard case .chapter = selectedContext, !isEditingVisibility else { return widgets }
        let hidden = currentHiddenSet
        return widgets.filter { !hidden.contains($0.rawValue) }
    }

    @ViewBuilder
    private func widgetWithVisibilityControls(_ widget: DashboardView.DashboardWidget) -> some View {
        let isHidden = currentHiddenSet.contains(widget.rawValue)
        let showOverlay = isEditingVisibility && selectedContext.isChapter
        ZStack(alignment: .topTrailing) {
            widgetView(for: widget)
                .opacity(showOverlay && isHidden ? 0.4 : 1)
                .grayscale(showOverlay && isHidden ? 0.6 : 0)
            if showOverlay {
                Button { toggleHidden(widget) } label: {
                    Image(systemName: isHidden ? "circle" : "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(isHidden ? .labelMuted : .accent)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.pressable)
                .padding(10)
                .help(isHidden ? "Réafficher ce widget" : "Masquer ce widget pour ce chapitre")
                .accessibilityLabel(isHidden ? "Réafficher ce widget" : "Masquer ce widget pour ce chapitre")
            }
        }
    }

    @ViewBuilder
    private func widgetView(for widget: DashboardView.DashboardWidget) -> some View {
        switch widget {
        case .healthScore:      ThesisHealthWidget(store: store)
        case .researchTime:     ResearchTimeCard(store: store)
        case .dailySession:     DailySessionCard(store: store)
        case .timeline:         TodayTimelineView(store: store)
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
        default:                EmptyView()
        }
    }

    // MARK: - Application du contexte

    private func applyContextChange(_ ctx: LibraryContext) {
        switch ctx {
        case .general:
            isEditingVisibility = false
        case let .chapter(projectId, chapterId):
            store.data.activeProjectId = projectId
            if let pIdx = store.data.projects.firstIndex(where: { $0.id == projectId }) {
                store.data.projects[pIdx].activeChapterId = chapterId
            }
        }
    }

    // MARK: - Visibilité par chapitre

    private var currentChapter: Chapter? {
        guard case let .chapter(pid, cid) = selectedContext,
              let project = store.data.projects.first(where: { $0.id == pid }) else { return nil }
        return project.chapters.first { $0.id == cid }
    }

    private var currentHiddenSet: Set<String> {
        Set(currentChapter?.hiddenWidgets ?? [])
    }

    private var hiddenCount: Int { currentHiddenSet.count }

    private func toggleHidden(_ widget: DashboardView.DashboardWidget) {
        guard case let .chapter(pid, cid) = selectedContext else { return }
        store.toggleChapterWidgetHidden(widget.rawValue, chapterId: cid, in: pid)
    }

    private func resetVisibility() {
        guard case let .chapter(pid, cid) = selectedContext else { return }
        store.resetChapterWidgetsVisibility(chapterId: cid, in: pid)
    }
}
