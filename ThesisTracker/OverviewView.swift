import SwiftUI

struct OverviewView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool
    @Binding var selectedNav: NavItem
    @State private var showExport  = false
    @State private var showReport  = false   // V3.4

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView
                // #40 — Suggestions d'archivage automatique
                AutoArchiveSuggestionBanner(store: store)
                globalStatsRow
                // Pipeline + Projection côte à côte
                HStack(alignment: .top, spacing: 16) {
                    thesisPipeline                               // V3.2
                        .frame(maxWidth: .infinity)
                    ThesisProjectionCard(store: store)           // V3.4
                        .frame(maxWidth: .infinity)
                }
                // V3.4 — tendance + productivité
                MonthlyMiniChart(store: store)
                WeekdayChart(store: store)
                projectsGrid
            }
            .padding(20)
        }
        .sheet(isPresented: $showExport) {
            ExportView(store: store)
        }
        .sheet(isPresented: $showReport) {   // V3.4
            ThesisReportSheet(store: store)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
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
                Text("Vue d'ensemble")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(activeProjects.count) projet(s) · \(totalChapters) chapitre(s)")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()

            HStack(spacing: 8) {
                // Bouton Rapport directeur (V3.4)
                Button { showReport = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.fill").font(.system(size: 12))
                        Text("Rapport")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.accentWarm)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentWarm.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.accentWarm.opacity(0.25), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                }
                .buttonStyle(.pressable)

                // Bouton Export existant
                Button { showExport = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text("Exporter")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                }
                .buttonStyle(.pressable)
            }
        }
    }

    // MARK: - Global stats

    private var globalStatsRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                MiniStatCard(label: "Total écrit", value: store.formatCountShort(totalCharsAllTime), unit: "", color: .accent)
                MiniStatCard(label: "Aujourd'hui", value: store.formatCountShort(store.dailyProgress), unit: "", color: .accentWarm)
                MiniStatCard(label: "Série actuelle", value: "\(store.currentStreak)", unit: "j", color: Color(red: 0.961, green: 0.455, blue: 0.114))
                MiniStatCard(label: "Chapitres finis", value: "\(completedChapters)", unit: "/\(totalChapters)", color: .accentGreen)
            }
            // #21 — Progression globale toutes thèses
            globalProgressBar
        }
    }

    @ViewBuilder
    private var globalProgressBar: some View {
        let allProjects = store.data.projects.filter { !$0.isArchived }
        let totalGoal = allProjects.reduce(0) { sum, p in sum + p.chapters.reduce(0) { $0 + $1.goal } }
        let totalWritten = allProjects.reduce(0) { sum, p in
            sum + p.chapters.reduce(0) { t, ch in t + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0) }
        }
        if totalGoal > 0 {
            let ratio = min(1.0, Double(totalWritten) / Double(totalGoal))
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Progression globale", systemImage: "chart.bar.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(ratio >= 1 ? .accentGreen : .accent)
                        Text("·")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted.opacity(0.4))
                        Text(store.formatCount(totalWritten) + " / " + store.formatCount(totalGoal))
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accent.opacity(0.12))
                                .frame(height: 8)
                            // Segmented bars per project
                            HStack(spacing: 2) {
                                ForEach(Array(allProjects.enumerated()), id: \.element.id) { idx, project in
                                    let pGoal = project.chapters.reduce(0) { $0 + $1.goal }
                                    let pWritten = project.chapters.reduce(0) { t, ch in t + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0) }
                                    let pRatio = pGoal > 0 ? min(1.0, Double(pWritten) / Double(pGoal)) : 0.0
                                    let segWidth = geo.size.width * (Double(pGoal) / Double(totalGoal))
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.chapterColor(at: idx).opacity(0.18))
                                            .frame(width: segWidth, height: 8)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.chapterColor(at: idx))
                                            .frame(width: segWidth * pRatio, height: 8)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 8)
                    // Project legend
                    if allProjects.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(allProjects.enumerated()), id: \.element.id) { idx, project in
                                    let pGoal = project.chapters.reduce(0) { $0 + $1.goal }
                                    let pWritten = project.chapters.reduce(0) { t, ch in t + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0) }
                                    let pRatio = pGoal > 0 ? min(1.0, Double(pWritten) / Double(pGoal)) : 0.0
                                    HStack(spacing: 4) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.chapterColor(at: idx))
                                            .frame(width: 10, height: 10)
                                        Text(project.name)
                                            .font(.system(size: 10))
                                            .foregroundColor(.labelMuted)
                                            .lineLimit(1)
                                        Text("\(Int(pRatio * 100))%")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - V3.2 Cockpit pipeline

    private var allChapters: [Chapter] {
        store.data.projects.flatMap { $0.chapters }.filter { $0.countsInThesisTotal }
    }

    private var weeklyVelocity: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else { return 0 }
        let weekStr = DataStore.dateString(from: weekAgo)
        return store.dailyTotals().filter { $0.key >= weekStr }.values.reduce(0, +)
    }

    @ViewBuilder
    private var thesisPipeline: some View {
        let chapters = allChapters
        if !chapters.isEmpty {
            let counts: [(ChapterStatus, Int)] = ChapterStatus.allCases.map { st in
                (st, chapters.filter { $0.status == st || (st == .termine && $0.isCompleted && $0.status == nil) }.count)
            }
            let noStatus = chapters.filter { $0.status == nil && !$0.isCompleted }.count
            let total = chapters.count
            let velocity = weeklyVelocity

            GlassCard {
                VStack(alignment: .leading, spacing: 14) {
                    // Titre
                    HStack {
                        Label("Pipeline de thèse", systemImage: "chart.bar.xaxis")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        if velocity > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.accentWarm)
                                Text(store.formatCountShort(velocity) + " / semaine")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.accentWarm)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.accentWarm.opacity(0.10))
                            .clipShape(Capsule())
                        }
                    }

                    // Barre pipeline
                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(ChapterStatus.allCases, id: \.self) { st in
                                let count = counts.first(where: { $0.0 == st })?.1 ?? 0
                                if count > 0 {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color(hex: st.color))
                                        .frame(width: geo.size.width * CGFloat(count) / CGFloat(max(total, 1)))
                                }
                            }
                            if noStatus > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.primary.opacity(0.10))
                                    .frame(width: geo.size.width * CGFloat(noStatus) / CGFloat(max(total, 1)))
                            }
                        }
                    }
                    .frame(height: 10)

                    // Légende
                    HStack(spacing: 12) {
                        ForEach(ChapterStatus.allCases, id: \.self) { st in
                            let count = counts.first(where: { $0.0 == st })?.1 ?? 0
                            HStack(spacing: 5) {
                                Circle().fill(Color(hex: st.color)).frame(width: 7, height: 7)
                                Text("\(count) \(st.label)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }
                        }
                        if noStatus > 0 {
                            HStack(spacing: 5) {
                                Circle().fill(Color.primary.opacity(0.25)).frame(width: 7, height: 7)
                                Text("\(noStatus) Non défini")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }
                        }
                        Spacer()
                        Text("\(total) chapitres")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.labelMuted)
                    }
                }
            }
        }
    }

    // MARK: - Projects grid

    private var activeProjects: [Project] { store.data.projects.filter { !$0.isArchived } }
    private var archivedProjects: [Project] { store.data.projects.filter { $0.isArchived } }

    @State private var showArchivedOverview: Bool = false

    private var projectsGrid: some View {
        VStack(spacing: 12) {
            if activeProjects.isEmpty && archivedProjects.isEmpty {
                emptyState
            } else if activeProjects.isEmpty {
                emptyState
            } else {
                ForEach(activeProjects) { project in
                    projectCard(project)
                }
            }

            // #17 — Archived projects fold-out
            if !archivedProjects.isEmpty {
                VStack(spacing: 8) {
                    Button {
                        withAppAnimation(.easeInOut(duration: 0.2)) { showArchivedOverview.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: showArchivedOverview ? "archivebox.fill" : "archivebox")
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                            Text("\(archivedProjects.count) projet(s) archivé(s)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Image(systemName: showArchivedOverview ? "chevron.up" : "chevron.down")
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted.opacity(0.6))
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)

                    if showArchivedOverview {
                        ForEach(archivedProjects) { project in
                            projectCard(project)
                                .opacity(0.65)
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        store.unarchiveProject(project.id)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.uturn.up").font(.system(size: 10))
                                            Text("Restaurer")
                                                .font(.system(size: 10, weight: .medium))
                                                .lineLimit(1)
                                        }
                                        .foregroundColor(.accent)
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(Color.accent.opacity(0.10))
                                        .clipShape(Capsule())
                                        .contentShape(Capsule())
                                        .padding(12)
                                    }
                                    .buttonStyle(.pressable)
                                }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let chapters = project.chapters
        let totalChars = chapters.reduce(0) { sum, ch in
            sum + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0)
        }
        let totalGoal = chapters.reduce(0) { $0 + $1.goal }
        let ratio = totalGoal > 0 ? min(1.0, Double(totalChars) / Double(totalGoal)) : 0.0
        let overdueCount = chapters.filter { isOverdue($0) }.count
        let lastActivity = lastActivityDate(project)
        let eta = store.estimatedCompletionDate(for: project.id)
        let isActive = store.data.activeProjectId == project.id

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // En-tête projet
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.accent.opacity(0.12))
                            .frame(width: 34, height: 34)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(project.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            if isActive {
                                Text("actif")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accent.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                            if overdueCount > 0 {
                                Text("\(overdueCount) en retard")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                        }
                        // #20 — supervisor
                        if let supervisor = project.supervisor, !supervisor.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.labelMuted.opacity(0.7))
                                Text(supervisor)
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }
                        } else {
                            Text("\(chapters.count) chapitre(s)")
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                    }
                    Spacer()

                    // Bouton "Aller au projet"
                    Button {
                        store.data.activeProjectId = project.id
                        store.save()
                        withAppAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard }
                    } label: {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.pressable)
                    .help("Aller au projet")
                    .accessibilityLabel("Aller au projet")
                }

                // Barre de progression globale
                if totalGoal > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(store.formatCount(totalChars) + " / " + store.formatCount(totalGoal))
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Text("\(Int(ratio * 100))%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(ratio >= 1 ? .accentGreen : .accent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accent.opacity(0.12))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(ratio >= 1 ? Color.accentGreen : Color.accent)
                                    .frame(width: geo.size.width * ratio, height: 6)
                            }
                        }
                        .frame(height: 6)
                    }
                }

                // Chapitres (mini liste)
                if !chapters.isEmpty {
                    Divider()
                    VStack(spacing: 6) {
                        ForEach(Array(chapters.prefix(4).enumerated()), id: \.element.id) { idx, chapter in
                            chapterRow(chapter, in: project, colorIdx: idx)
                        }
                        if chapters.count > 4 {
                            Text("+ \(chapters.count - 4) chapitre(s)")
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // #16 — Notes de projet
                if let notes = project.notes, !notes.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted.opacity(0.6))
                        Text(notes)
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }

                // Pied de carte : dernière activité + projection
                Divider()
                HStack(spacing: 16) {
                    if let lastDate = lastActivity {
                        Label(DataStore.formatDate(lastDate), systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    } else {
                        Label("Aucune activité", systemImage: "clock")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    if let etaDate = eta {
                        Label("Fin ~" + DataStore.formatDate(etaDate), systemImage: "flag.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accentWarm)
                    }
                    Spacer()
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter, in project: Project, colorIdx: Int) -> some View {
        let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
        let goal = chapter.goal
        let ratio = goal > 0 ? min(1.0, Double(latest) / Double(goal)) : 0.0
        let color = Color.chapterColor(at: colorIdx)
        let overdue = isOverdue(chapter)

        return HStack(spacing: 8) {
            Circle()
                .fill(chapter.isCompleted ? Color.accentGreen : (overdue ? Color.red : color))
                .frame(width: 7, height: 7)
            Text(chapter.name)
                .font(.system(size: 12))
                .foregroundColor(chapter.isCompleted ? .labelMuted : .primary)
                .lineLimit(1)
                .strikethrough(chapter.isCompleted, color: .labelMuted)
            Spacer()
            if goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.15)).frame(height: 4)
                        RoundedRectangle(cornerRadius: 2).fill(chapter.isCompleted ? Color.accentGreen : color)
                            .frame(width: geo.size.width * ratio, height: 4)
                    }
                }
                .frame(width: 80, height: 4)
                Text("\(Int(ratio * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .frame(width: 32, alignment: .trailing)
            } else if chapter.isCompleted {
                Text("Terminé")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentGreen)
            } else {
                Text(store.formatCountShort(latest))
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        GlassCard {   // 5.15 : état vide commun
            EmptyStateView(icon: "folder.badge.plus", title: "Aucun projet pour l'instant",
                           message: "Un projet regroupe les chapitres d'une thèse ou d'un livre.", iconColor: .accent,
                           action: { withAppAnimation(Motion.quick) { showSidebar = true } }, actionLabel: "Créer un projet")
        }
    }

    // MARK: - Helpers

    private var totalChapters: Int {
        activeProjects.reduce(0) { $0 + $1.chapters.count }
    }

    private var completedChapters: Int {
        activeProjects.flatMap { $0.chapters }.filter { $0.isCompleted }.count
    }

    private var totalCharsAllTime: Int {
        store.dailyTotals().values.reduce(0, +)
    }

    private func isOverdue(_ chapter: Chapter) -> Bool {
        guard !chapter.isCompleted,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr) else { return false }
        return Calendar.current.startOfDay(for: deadline) < Calendar.current.startOfDay(for: Date())
    }

    private func lastActivityDate(_ project: Project) -> Date? {
        let totals = store.dailyTotals(projectId: project.id)
        guard let lastDateStr = totals.filter({ $0.value > 0 }).keys.max() else { return nil }
        return DataStore.parseDate(lastDateStr)
    }
}
