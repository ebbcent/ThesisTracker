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
                Text("Vue d'ensemble")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(store.data.projects.count) projet(s) · \(totalChapters) chapitre(s)")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()

            HStack(spacing: 8) {
                // Bouton Rapport directeur (V3.4)
                Button { showReport = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text.fill").font(.system(size: 12))
                        Text("Rapport").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentWarm)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accentWarm.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentWarm.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Bouton Export existant
                Button { showExport = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 12))
                        Text("Exporter").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accent)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Global stats

    private var globalStatsRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "Total écrit", value: store.formatCountShort(totalCharsAllTime), unit: "", color: .accent)
            MiniStatCard(label: "Aujourd'hui", value: store.formatCountShort(store.dailyProgress), unit: "", color: .accentWarm)
            MiniStatCard(label: "Série actuelle", value: "\(store.currentStreak)", unit: "j", color: .accentWarm)
            MiniStatCard(label: "Chapitres finis", value: "\(completedChapters)", unit: "/\(totalChapters)", color: .accentGreen)
        }
    }

    // MARK: - V3.2 Cockpit pipeline

    private var allChapters: [Chapter] {
        store.data.projects.flatMap { $0.chapters }
    }

    private var weeklyVelocity: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: today) else { return 0 }
        let weekStr = DataStore.dateString(from: weekAgo)
        return store.dailyTotals().filter { $0.key >= weekStr }.values.reduce(0, +)
    }

    private var thesisPipeline: some View {
        let chapters = allChapters
        guard !chapters.isEmpty else { return AnyView(EmptyView()) }

        // Groupement par statut
        let counts: [(ChapterStatus, Int)] = ChapterStatus.allCases.map { st in
            (st, chapters.filter { $0.status == st || (st == .termine && $0.isCompleted && $0.status == nil) }.count)
        }
        let noStatus = chapters.filter { $0.status == nil && !$0.isCompleted }.count
        let total = chapters.count
        let velocity = weeklyVelocity

        return AnyView(
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
        )
    }

    // MARK: - Projects grid

    private var projectsGrid: some View {
        VStack(spacing: 12) {
            if store.data.projects.isEmpty {
                emptyState
            } else {
                ForEach(store.data.projects) { project in
                    projectCard(project)
                }
            }
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let chapters = project.chapters
        let totalChars = chapters.reduce(0) { sum, ch in
            sum + (ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0)
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
                        RoundedRectangle(cornerRadius: 8)
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
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.accent.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                            if overdueCount > 0 {
                                Text("\(overdueCount) en retard")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.red.opacity(0.85))
                                    .clipShape(Capsule())
                            }
                        }
                        Text("\(chapters.count) chapitre(s)")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()

                    // Bouton "Aller au projet"
                    Button {
                        store.data.activeProjectId = project.id
                        store.save()
                        withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .dashboard }
                    } label: {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.plain)
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
        let latest = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
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
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 36)).foregroundColor(.labelMuted)
                Text("Aucun projet pour l'instant")
                    .font(.system(size: 14)).foregroundColor(.labelMuted)
                Button("Créer un projet") {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar = true }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accent))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 28)
        }
    }

    // MARK: - Helpers

    private var totalChapters: Int {
        store.data.projects.reduce(0) { $0 + $1.chapters.count }
    }

    private var completedChapters: Int {
        store.data.projects.flatMap { $0.chapters }.filter { $0.isCompleted }.count
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
