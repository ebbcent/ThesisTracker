import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct DeadlineBoardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    private var items: [(project: Project, chapter: Chapter)] { store.chaptersWithDeadlines }

    // MARK: - Onglets
    enum Tab: Int { case chapitres = 0, jalons = 1, gantt = 2, next72h = 3, critique = 4 }
    @State private var selectedTab: Tab = .chapitres
    @State private var expandedPacing: Set<UUID> = []   // 5.12 — simulateurs de rythme ouverts

    // MARK: - Feuilles
    @State private var showAddMilestone: Bool = false
    @State private var milestoneTargetProject: Project? = nil
    @State private var editingMilestone: (project: Project, milestone: Milestone)? = nil // #26/#28
    @State private var showEditMilestone: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView
                tabBar

                // #38 — contenu avec transition directionnelle
                Group {
                    switch selectedTab {
                    case .chapitres:
                        VStack(spacing: 22) {
                            if items.isEmpty { emptyState } else { summaryRow; deadlineList }
                        }
                    case .jalons:
                        milestonesSection
                    case .gantt:
                        ganttSection
                    case .next72h:
                        next72hSection
                    case .critique:
                        critiqueSection
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .appAnimation(.easeInOut(duration: 0.15), value: selectedTab)
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddMilestone) {
            if let project = milestoneTargetProject {
                MilestoneFormView(store: store, project: project)
            }
        }
        .sheet(isPresented: $showEditMilestone) {      // #26/#28 — édition depuis Gantt
            if let item = editingMilestone {
                MilestoneFormView(store: store, project: item.project, existing: item.milestone)
            }
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
                Text("Échéances")
                    .font(TypeScale.pageTitle)
                Text(selectedTab == .chapitres
                     ? "\(items.count) chapitre\(items.count > 1 ? "s" : "") avec échéance"
                     : selectedTab == .jalons
                         ? "\(store.allMilestonesSorted.count) jalon(s)"
                         : selectedTab == .next72h
                             ? "72 heures à venir"
                             : selectedTab == .critique
                                 ? "\(store.criticalPathMilestones.count) jalon(s) bloquant(s)"
                                 : "Vue chronologique")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()

            // #25 — Export .ics
            Button {
                exportICS()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                    Text("Calendrier (.ics)")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.labelMuted)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Color.cardBg)
                .clipShape(AppLook.buttonShape(8))
                .overlay(AppLook.buttonShape(8).stroke(Color.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .help("Exporter les échéances et jalons au format iCal (.ics)")

            // Bouton ajouter jalon (tab Jalons uniquement)
            if selectedTab == .jalons && !store.data.projects.isEmpty {
                Menu {
                    ForEach(store.data.projects) { project in
                        Button(project.name) {
                            milestoneTargetProject = project
                            showAddMilestone = true
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: AppLook.fs(11), weight: .bold))
                        Text("Jalon")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.accent)
                    .clipShape(AppLook.buttonShape(8))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton("Chapitres", icon: "doc.text",                    tab: .chapitres)
            tabButton("Jalons",    icon: "flag.fill",                    tab: .jalons)
            tabButton("Gantt",     icon: "chart.bar.xaxis",              tab: .gantt)
            tabButton("72h",       icon: "clock.badge.exclamationmark",  tab: .next72h)
            tabButton("Critique",  icon: "exclamationmark.triangle.fill", tab: .critique)
        }
        .background(FloatingSurface(radius: 10))   // 5.27 : verre en Tuiles
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(AppLook.hairline, lineWidth: 1))
    }

    private func tabButton(_ label: String, icon: String, tab: Tab) -> some View {
        Button {
            withAppAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: AppLook.fs(11)))
                Text(label)
                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(selectedTab == tab ? .accent : .labelMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selectedTab == tab ? Color.accent.opacity(0.10) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(9, 13)))
            .contentShape(RoundedRectangle(cornerRadius: AppLook.r(9, 13)))
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Chapitres tab

    private var summaryRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "En retard", value: "\(overdueCount)", unit: "", color: .red)
            MiniStatCard(label: "Cette semaine", value: "\(dueThisWeekCount)", unit: "", color: .accentWarm)
            MiniStatCard(label: "Terminés", value: "\(completedCount)", unit: "", color: .accentGreen)
        }
    }

    private var deadlineList: some View {
        deadlineListCards(items: items)
    }

    private func deadlineListCards(items: [(project: Project, chapter: Chapter)]) -> some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.chapter.id) { item in
                let deadline = store.effectiveDeadlineDate(for: item.chapter.deadline) ?? Date()
                let latest = store.latestTotal(for: item.chapter.id, in: item.project.id)
                let eta = store.estimatedCompletionDate(for: item.chapter.id, in: item.project.id)
                let pace = store.requiredPacePerDay(for: item.chapter, in: item.project) // #27
                GlassCard {
                  VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        // V5 — #8 : Quick-check chapitre
                        Button {
                            store.toggleChapterComplete(item.chapter.id, in: item.project.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .stroke(item.chapter.isCompleted ? Color.accentGreen : statusColor(for: deadline),
                                            lineWidth: 1.5)
                                    .frame(width: 20, height: 20)
                                if item.chapter.isCompleted {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: AppLook.fs(10), weight: .bold))
                                        .foregroundColor(.accentGreen)
                                }
                            }
                        }
                        .buttonStyle(.pressable)
                        .padding(.top, 3)
                        .help(item.chapter.isCompleted ? "Marquer comme non terminé" : "Marquer comme terminé")
                        .accessibilityLabel(item.chapter.isCompleted ? "Marquer comme non terminé" : "Marquer comme terminé")

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(item.project.name) · \(item.chapter.name)")
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)   // 5.19 : titres du plan, longs
                            // #24 — affiche la deadline effective (avec buffer si actif)
                            HStack(spacing: 6) {
                                Text("Échéance : \(DataStore.formatDate(deadline))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.labelMuted)
                                if store.deadlineBuffer > 0 {
                                    Text("(buffer \(store.deadlineBuffer)j)")
                                        .font(.system(size: AppLook.fs(10)))
                                        .foregroundColor(.orange.opacity(0.8))
                                }
                            }
                            Text(progressLabel(latest: latest, goal: item.chapter.goal, useWordCount: store.data.useWordCount)
                                 + pagesSuffix(latest: latest, goal: item.chapter.goal))
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                            if let eta {
                                Text("Projection : \(DataStore.formatDate(eta))")
                                    .font(.system(size: 12))
                                    .foregroundColor(eta > deadline ? .red : .accentGreen)
                            }
                            // #27 — rythme nécessaire
                            if let pace, !item.chapter.isCompleted {
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: AppLook.fs(10)))
                                    let paceStr = store.data.useWordCount
                                        ? "\(DataStore.formatNumber(pace / 5)) mots/jour"
                                        : "\(DataStore.formatNumber(pace)) signes/jour"
                                    Text(item.chapter.pacing?.profile.map { "Rythme \($0.label) : \(paceStr) aujourd'hui" }
                                         ?? "Il faut \(paceStr) pour finir à temps")
                                        .font(.system(size: AppLook.fs(11)))
                                }
                                .foregroundColor(statusColor(for: deadline))
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            // Badge J-X (#2)
                            if !item.chapter.isCompleted {
                                let days = daysRemaining(for: deadline)
                                Text(days < 0 ? "\(abs(days)) j de retard" : (days == 0 ? "Aujourd'hui" : "dans \(days) j"))
                                    .font(.system(size: AppLook.fs(10), weight: .bold, design: .monospaced))
                                    .foregroundColor(statusColor(for: deadline))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(statusColor(for: deadline).opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        Text(statusText(for: deadline, completed: item.chapter.isCompleted))
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                            .foregroundColor(item.chapter.isCompleted ? .accentGreen : statusColor(for: deadline))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((item.chapter.isCompleted ? Color.accentGreen : statusColor(for: deadline)).opacity(0.12)))
                        }  // end VStack trailing
                    }
                    // 5.12 — simulateur de rythme du chapitre
                    if !item.chapter.isCompleted, item.chapter.goal > 0, item.chapter.deadline != nil {
                        pacingToggle(for: item.chapter)
                        postponeRow(chapter: item.chapter, projectId: item.project.id)   // 5.34
                        if expandedPacing.contains(item.chapter.id) {
                            PacingSimulatorView(store: store, chapter: item.chapter, projectId: item.project.id)
                                .padding(.top, 8)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                  }
                }
            }
        }
    }

    private func pacingToggle(for chapter: Chapter) -> some View {
        let open = expandedPacing.contains(chapter.id)
        return Button {
            withAppAnimation(.easeInOut(duration: 0.2)) {
                if open { expandedPacing.remove(chapter.id) } else { expandedPacing.insert(chapter.id) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: chapter.pacing?.profile?.symbol ?? "chart.xyaxis.line")
                    .font(.system(size: AppLook.fs(10)))
                Text(chapter.pacing?.profile.map { "Rythme : \($0.label)" } ?? "Choisir un rythme")
                    .font(.system(size: AppLook.fs(11), weight: .medium))
                Image(systemName: open ? "chevron.up" : "chevron.down")
                    .font(.system(size: AppLook.fs(10), weight: .semibold))
            }
            .foregroundColor(AppLook.tiles ? .primary : .accentWarm)
            // 5.34 — un vrai bouton (c'était un lien discret)
            .padding(.horizontal, AppLook.tiles ? 12 : 0)
            .frame(height: AppLook.tiles ? 28 : nil)
            .overlay(Capsule().stroke(AppLook.tiles ? Color.cardBorder : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .padding(.top, 8)
        .padding(.leading, 32)
    }

    // 5.34 — une échéance dépassée ne reste plus en tête sans issue : on la reporte en un clic
    // (ou on coche le chapitre, à gauche, pour la clore).
    @ViewBuilder
    private func postponeRow(chapter: Chapter, projectId: UUID) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        if !chapter.isCompleted, let date = chapter.deadline.flatMap(DataStore.parseDate), date < today {
            HStack(spacing: 8) {
                Text("Échéance dépassée :")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)
                postponeButton("Reporter d'une semaine", days: 7, chapterId: chapter.id, projectId: projectId)
                postponeButton("d'un mois", days: 30, chapterId: chapter.id, projectId: projectId)
            }
            .padding(.top, 8)
            .padding(.leading, 32)
        }
    }

    private func postponeButton(_ title: String, days: Int, chapterId: UUID, projectId: UUID) -> some View {
        Button {
            guard let p = store.data.projects.firstIndex(where: { $0.id == projectId }),
                  let c = store.data.projects[p].chapters.firstIndex(where: { $0.id == chapterId }),
                  let target = Calendar.current.date(byAdding: .day, value: days, to: Date()) else { return }
            store.data.projects[p].chapters[c].deadline = DataStore.dateString(from: target)
            store.save()
        } label: {
            Text(title)
                .font(.system(size: AppLook.fs(11), weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .help("Nouvelle échéance : dans \(days) jours à compter d'aujourd'hui")
    }

    private func pagesSuffix(latest: Int, goal: Int) -> String {
        guard let written = store.pagesNumber(latest) else { return "" }
        if goal > 0, let total = store.pagesNumber(goal, digits: 0) { return " · ≈ \(written) / \(total) p." }
        return " · ≈ \(written) p."
    }

    // MARK: - Jalons tab

    private var milestonesSection: some View {
        VStack(spacing: 8) {
            let all = store.allMilestonesSorted
            if all.isEmpty {
                emptyMilestones
            } else {
                ForEach(all, id: \.milestone.id) { item in
                    milestoneCard(item)
                }
            }
        }
    }

    private func milestoneCard(_ item: (project: Project, milestone: Milestone)) -> some View {
        let milestoneDate = DataStore.parseDate(item.milestone.date) ?? Date()
        let isOverdue = !item.milestone.isCompleted && milestoneDate < Calendar.current.startOfDay(for: Date())
        let color: Color = item.milestone.isCompleted ? .accentGreen : statusColor(for: milestoneDate)

        return GlassCard {
            HStack(alignment: .top, spacing: 14) {
                // Toggle completion
                Button {
                    store.toggleMilestone(item.milestone.id, in: item.project.id)
                } label: {
                    ZStack {
                        Circle()
                            .stroke(color, lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        if item.milestone.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: AppLook.fs(10), weight: .bold))
                                .foregroundColor(.accentGreen)
                        }
                    }
                }
                .buttonStyle(.pressable)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.milestone.title)
                            .font(.system(size: 14, weight: .semibold))
                            .strikethrough(item.milestone.isCompleted, color: .labelMuted)
                            .foregroundColor(item.milestone.isCompleted ? .labelMuted : .primary)
                        Spacer()
                        // Badge date
                        Text(statusText(for: milestoneDate, completed: item.milestone.isCompleted))
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                            .foregroundColor(color)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(color.opacity(0.12)))
                    }

                    HStack(spacing: 4) {
                        if let type = item.project.projectType {
                            Image(systemName: type.icon).font(.system(size: AppLook.fs(10)))
                        }
                        Text(item.project.name)
                            .font(.system(size: AppLook.fs(11)))
                    }
                    .foregroundColor(.labelMuted)

                    Text(DataStore.formatDate(milestoneDate))
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(isOverdue ? .red.opacity(0.8) : .labelMuted)

                    if let notes = item.milestone.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                            .lineLimit(2)
                    }
                    // Badges row
                    HStack(spacing: 6) {
                        // #44 — badge statut
                        if item.milestone.milestoneStatus != .pending {
                            let st = item.milestone.milestoneStatus
                            HStack(spacing: 4) {
                                Image(systemName: st.icon)
                                    .font(.system(size: AppLook.fs(10)))
                                Text(st.label)
                                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                            }
                            .foregroundColor(st.color)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(st.color.opacity(0.10))
                            .clipShape(Capsule())
                        }

                        // #43 — badge chapitre lié
                        if let cid = item.milestone.linkedChapterId,
                           let ch = item.project.chapters.first(where: { $0.id == cid }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: AppLook.fs(10)))
                                Text(ch.name)
                                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accentGreen)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentGreen.opacity(0.08))
                            .clipShape(Capsule())
                        }

                        // #28 — badge récurrence
                        if let recurrence = item.milestone.recurrence {
                            HStack(spacing: 4) {
                                Image(systemName: recurrence.icon)
                                    .font(.system(size: AppLook.fs(10)))
                                Text(recurrence.label)
                                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                            }
                            .foregroundColor(.accent)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accent.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }

                // #26 — Edit button
                Button {
                    editingMilestone = item
                    showEditMilestone = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                        .padding(6)
                        .background(Color.cardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .padding(.top, 1)
                .help("Modifier le jalon")
                .accessibilityLabel("Modifier le jalon")

                // Delete
                Button {
                    withAppAnimation { store.deleteMilestone(item.milestone.id, from: item.project.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.5))
                        .padding(6)
                        .background(Color.red.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.pressable)
                .padding(.top, 1)
                .help("Supprimer le jalon")
                .accessibilityLabel("Supprimer le jalon")
            }
        }
    }

    // MARK: - #46 Vue "Chemin critique"

    private var critiqueSection: some View {
        let milestones = store.criticalPathMilestones
        return VStack(spacing: 12) {
            if milestones.isEmpty {
                GlassCard {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.accentGreen)
                        Text("Aucun jalon bloquant")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Tous vos jalons sont sous contrôle ou au-delà de 30 jours.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                // Legend
                HStack(spacing: 16) {
                    ForEach([DataStore.CriticalUrgency.urgent, .high, .medium, .low], id: \.rawValue) { u in
                        HStack(spacing: 5) {
                            Circle().fill(u.color).frame(width: 8, height: 8)
                            Text(u.label).font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                ForEach(milestones) { cm in
                    critiqueMilestoneCard(cm)
                }
            }
        }
    }

    private func critiqueMilestoneCard(_ cm: DataStore.CriticalMilestone) -> some View {
        let u = cm.urgency
        return GlassCard {
            HStack(alignment: .top, spacing: 14) {
                // Urgency icon
                ZStack {
                    Circle()
                        .fill(u.color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: u.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(u.color)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(cm.milestone.title)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        // Days badge
                        let daysText = cm.daysLeft < 0
                            ? "\(abs(cm.daysLeft)) j de retard"
                            : (cm.daysLeft == 0 ? "Aujourd'hui" : "dans \(cm.daysLeft) j")
                        Text(daysText)
                            .font(.system(size: AppLook.fs(11), weight: .bold, design: .monospaced))
                            .foregroundColor(u.color)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(u.color.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }

                    HStack(spacing: 4) {
                        if let type = cm.project.projectType {
                            Image(systemName: type.icon).font(.system(size: AppLook.fs(10)))
                        }
                        Text(cm.project.name)
                        Text("·")
                        Text(DataStore.formatDate(DataStore.parseDate(cm.milestone.date) ?? Date()))
                    }
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)

                    HStack(spacing: 8) {
                        // Urgency label
                        Text(u.label)
                            .font(.system(size: AppLook.fs(10), weight: .semibold))
                            .foregroundColor(u.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(u.color.opacity(0.08))
                            .clipShape(Capsule())

                        // Status badge (#44)
                        if cm.milestone.milestoneStatus != .pending {
                            let st = cm.milestone.milestoneStatus
                            HStack(spacing: 3) {
                                Image(systemName: st.icon).font(.system(size: AppLook.fs(10)))
                                Text(st.label).font(.system(size: AppLook.fs(10), weight: .semibold))
                            }
                            .foregroundColor(st.color)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(st.color.opacity(0.08))
                            .clipShape(Capsule())
                        }

                        // Blocking indicator
                        if cm.isBlocking {
                            HStack(spacing: 3) {
                                Image(systemName: "link").font(.system(size: AppLook.fs(10)))
                                Text("Bloquant").font(.system(size: AppLook.fs(10), weight: .semibold))
                            }
                            .foregroundColor(.red.opacity(0.7))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.06))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Quick-edit button
                Button {
                    editingMilestone = (project: cm.project, milestone: cm.milestone)
                    showEditMilestone = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                        .padding(6)
                        .background(Color.cardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .padding(.top, 1)
                .help("Modifier le jalon")
                .accessibilityLabel("Modifier le jalon")
            }
        }
    }

    private var emptyMilestones: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucun jalon pour l'instant")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
                Text("Utilisez le bouton + pour ajouter des étapes clés à vos projets.")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Helpers (shared)

    private var overdueCount: Int {
        items.filter {
            guard let deadline = $0.chapter.deadline.flatMap(DataStore.parseDate), !$0.chapter.isCompleted else { return false }
            return Calendar.current.startOfDay(for: deadline) < Calendar.current.startOfDay(for: Date())
        }.count
    }

    private var dueThisWeekCount: Int {
        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: Date()) else { return 0 }
        return items.filter {
            guard let deadline = $0.chapter.deadline.flatMap(DataStore.parseDate), !$0.chapter.isCompleted else { return false }
            return deadline >= Date() && deadline <= weekEnd
        }.count
    }

    private var completedCount: Int { items.filter { $0.chapter.isCompleted }.count }

    private func statusColor(for date: Date) -> Color {
        let today = Calendar.current.startOfDay(for: Date())
        let days = Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<0:    return Color(red: 0.929, green: 0.259, blue: 0.259)
        case 0...2:   return Color(red: 0.961, green: 0.329, blue: 0.184)
        case 3...7:   return Color.semAmber
        case 8...14:  return Color(red: 0.898, green: 0.773, blue: 0.118)
        default:      return Color.semGreen
        }
    }

    private func daysRemaining(for date: Date) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        return Calendar.current.dateComponents([.day], from: today, to: Calendar.current.startOfDay(for: date)).day ?? 0
    }

    private func statusText(for date: Date, completed: Bool) -> String {
        if completed { return "Terminé" }
        let days = daysRemaining(for: date)
        if days < 0  { return "En retard \(abs(days))j" }
        if days == 0 { return "Aujourd'hui !" }
        if days == 1 { return "Demain" }
        return "Dans \(days) j"
    }

    private func progressLabel(latest: Int, goal: Int, useWordCount: Bool = false) -> String {
        let unit = useWordCount ? "mots" : "signes"
        let l = useWordCount ? latest / 5 : latest
        let g = useWordCount ? goal / 5   : goal
        guard goal > 0 else { return "\(DataStore.formatNumber(l)) \(unit)" }
        return "\(DataStore.formatNumber(l)) / \(DataStore.formatNumber(g)) \(unit)"
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucune échéance pour l'instant")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    // MARK: - #22 Vue "prochaines 72h"

    private var next72hSection: some View {
        let horizon = Date().addingTimeInterval(72 * 3600)
        let cal = Calendar.current

        // Chapitres dans les 72h
        let urgentChapters = items.filter {
            guard let d = store.effectiveDeadlineDate(for: $0.chapter.deadline),
                  !$0.chapter.isCompleted else { return false }
            return d <= horizon
        }
        // Jalons dans les 72h
        let urgentMilestones = store.allMilestonesSorted.filter {
            guard let d = DataStore.parseDate($0.milestone.date),
                  !$0.milestone.isCompleted else { return false }
            return cal.startOfDay(for: d) <= cal.startOfDay(for: horizon)
        }

        return Group {
            if urgentChapters.isEmpty && urgentMilestones.isEmpty {
                GlassCard {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.accentGreen)
                        Text("Rien d'urgent dans les 72 heures !")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                        Text("Profites-en pour avancer sur tes objectifs à long terme.")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            } else {
                VStack(spacing: 16) {
                    if !urgentChapters.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CHAPITRES")
                                .font(.system(size: AppLook.fs(10), weight: .bold))
                                .foregroundColor(.labelMuted).kerning(1)
                            deadlineListCards(items: urgentChapters)
                        }
                    }
                    if !urgentMilestones.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("JALONS")
                                .font(.system(size: AppLook.fs(10), weight: .bold))
                                .foregroundColor(.labelMuted).kerning(1)
                            ForEach(urgentMilestones, id: \.milestone.id) { item in
                                milestoneCard(item)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - #25 Export .ics

    private func exportICS() {
        let ics = store.generateICS()
        let panel = NSSavePanel()
        panel.title = "Exporter le planning (.ics)"
        panel.nameFieldStringValue = "thesistracker-planning.ics"
        panel.allowedContentTypes = [.init(filenameExtension: "ics") ?? .data]
        panel.canCreateDirectories = true
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? ics.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Gantt

extension DeadlineBoardView {

    // ── Constantes ──────────────────────────────────────────────────────────
    private var dayW:      CGFloat { 11 }
    private var rowH:      CGFloat { 40 }
    private var labelColW: CGFloat { 162 }
    private var axisH:     CGFloat { 22 }

    // ── Modèle interne ──────────────────────────────────────────────────────
    private struct GanttRow {
        let label:       String
        let sub:         String
        let barStart:    Date?   // nil → milestone (pas de barre)
        let barEnd:      Date
        let isMilestone: Bool
        let isCompleted: Bool
        let accentColor: Color
        // #26 — identifiants pour rendre les barres interactives
        let projectId:   UUID
        let itemId:      UUID   // chapterId ou milestoneId
    }

    private var ganttRows: [GanttRow] {
        var rows: [GanttRow] = []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // Chapitres avec deadline
        for item in items {
            guard let deadlineDate = store.effectiveDeadlineDate(for: item.chapter.deadline) else { continue }
            let firstEntryDate = item.chapter.entries.map(\.date)
                .compactMap(DataStore.parseDate).min()
            rows.append(GanttRow(
                label:       item.chapter.name,
                sub:         item.project.name,
                barStart:    firstEntryDate ?? cal.date(byAdding: .day, value: -7, to: today),
                barEnd:      deadlineDate,
                isMilestone: false,
                isCompleted: item.chapter.isCompleted,
                accentColor: item.chapter.isCompleted ? .accentGreen : statusColor(for: deadlineDate),
                projectId:   item.project.id,
                itemId:      item.chapter.id
            ))
        }

        // Jalons
        for item in store.allMilestonesSorted {
            guard let d = DataStore.parseDate(item.milestone.date) else { continue }
            rows.append(GanttRow(
                label:       item.milestone.title,
                sub:         item.project.name,
                barStart:    nil,
                barEnd:      d,
                isMilestone: true,
                isCompleted: item.milestone.isCompleted,
                accentColor: item.milestone.isCompleted ? .accentGreen : statusColor(for: d),
                projectId:   item.project.id,
                itemId:      item.milestone.id
            ))
        }

        return rows.sorted { $0.barEnd < $1.barEnd }
    }

    private var ganttStart: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let allDates = ganttRows.compactMap { $0.barStart ?? (ganttRows.isEmpty ? nil : $0.barEnd) }
        let earliest = allDates.min() ?? today
        return cal.date(byAdding: .day, value: -7, to: min(earliest, today))!
    }

    private var ganttEnd: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let latest = ganttRows.map(\.barEnd).max() ?? today
        return cal.date(byAdding: .day, value: 18, to: latest)!
    }

    private var ganttTotalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: ganttStart, to: ganttEnd).day ?? 60)
    }

    private func gx(_ date: Date) -> CGFloat {
        let d = Calendar.current.dateComponents([.day], from: ganttStart, to: date).day ?? 0
        return CGFloat(max(0, d)) * dayW
    }

    // ── Vue principale ──────────────────────────────────────────────────────
    var ganttSection: some View {
        Group {
            if ganttRows.isEmpty {
                GlassCard {
                    VStack(spacing: 10) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 32)).foregroundColor(.labelMuted)
                        Text("Aucune échéance ou jalon à afficher")
                            .font(.system(size: 13)).foregroundColor(.labelMuted)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 32)
                }
            } else {
                VStack(spacing: 0) {
                    ganttHeader
                    Divider()
                    ganttBody
                }
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20)))
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(14, 20)).stroke(Color.cardBorder, lineWidth: 1))
            }
        }
    }

    // Axe des mois (fixe à gauche, scrollable à droite)
    private var ganttHeader: some View {
        HStack(spacing: 0) {
            // Colonne labels — vide, juste pour l'alignement
            Color.clear.frame(width: labelColW, height: axisH)

            // Mois dans la zone scrollable — alignés avec le corps
            ScrollView(.horizontal, showsIndicators: false) {
                ganttMonthAxis
                    .frame(width: CGFloat(ganttTotalDays) * dayW, height: axisH)
            }
            .disabled(true) // l'axe suit le défilement du corps via offset partagé
        }
    }

    private var ganttMonthAxis: some View {
        ZStack(alignment: .leading) {
            let cal = Calendar.current
            let months = monthsInRange()
            ForEach(months, id: \.self) { monthStart in
                let x = gx(monthStart)
                VStack(spacing: 0) {
                    Text(monthLabel(monthStart))
                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .kerning(0.5)
                        .frame(height: axisH, alignment: .center)
                }
                .offset(x: x + 3)

                // Trait vertical léger
                Rectangle()
                    .fill(Color.cardBorder)
                    .frame(width: 1, height: axisH)
                    .offset(x: x)
            }
            // Marque "aujourd'hui"
            let todayX = gx(cal.startOfDay(for: Date()))
            Text("auj.")
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.red.opacity(0.7))
                .offset(x: todayX - 10, y: 0)
        }
    }

    // Corps du Gantt
    private var ganttBody: some View {
        HStack(spacing: 0) {
            // Colonne labels fixe
            VStack(spacing: 0) {
                ForEach(Array(ganttRows.enumerated()), id: \.offset) { idx, row in
                    ganttLabelCell(row, isEven: idx % 2 == 0)
                    if idx < ganttRows.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .frame(width: labelColW)

            Divider()

            // Zone scrollable
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Bandes de fond alternées + traits de mois
                    ganttBackground

                    // Ligne "aujourd'hui"
                    let todayX = gx(Calendar.current.startOfDay(for: Date()))
                    Rectangle()
                        .fill(Color.red.opacity(0.45))
                        .frame(width: 1.5, height: CGFloat(ganttRows.count) * rowH)
                        .offset(x: todayX)

                    // Barres et marqueurs
                    VStack(spacing: 0) {
                        ForEach(Array(ganttRows.enumerated()), id: \.offset) { idx, row in
                            ganttRowBar(row)
                                .frame(height: rowH)
                            if idx < ganttRows.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
                .frame(
                    width:  CGFloat(ganttTotalDays) * dayW,
                    height: CGFloat(ganttRows.count) * rowH + CGFloat(max(0, ganttRows.count - 1))
                )
            }
        }
        .frame(maxHeight: min(CGFloat(ganttRows.count) * (rowH + 1) + 8, 380))
    }

    // Cellule label — #26 cliquable
    private func ganttLabelCell(_ row: GanttRow, isEven: Bool) -> some View {
        Button {
            ganttRowTapped(row)
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(row.isCompleted ? .labelMuted : .primary)
                        .lineLimit(1)
                    Text(row.sub)
                        .font(.system(size: AppLook.fs(10)))
                        .foregroundColor(.labelMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: row.isMilestone ? "flag.fill" : "doc.text")
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted.opacity(0.5))
                    .padding(.trailing, 4)
            }
            .frame(width: labelColW, height: rowH, alignment: .leading)
            .padding(.leading, 12)
            .background(isEven ? Color.clear : Color.black.opacity(0.018))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(row.isMilestone ? "Modifier ce jalon" : "Voir ce chapitre dans l'onglet Chapitres")
    }

    private func ganttRowTapped(_ row: GanttRow) {
        if row.isMilestone {
            // #26 — ouvrir le formulaire d'édition du jalon
            if let project = store.data.projects.first(where: { $0.id == row.projectId }),
               let milestone = project.milestones.first(where: { $0.id == row.itemId }) {
                editingMilestone = (project: project, milestone: milestone)
                showEditMilestone = true
            }
        } else {
            // #26 — naviguer vers l'onglet chapitres
            withAppAnimation(.easeInOut(duration: 0.15)) { selectedTab = .chapitres }
        }
    }

    // Barre ou marqueur d'un item
    private func ganttRowBar(_ row: GanttRow) -> some View {
        ZStack(alignment: .leading) {
            Color.clear

            if row.isMilestone {
                // Losange à la date
                let x = gx(row.barEnd)
                Image(systemName: row.isCompleted ? "diamond.fill" : "diamond")
                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                    .foregroundColor(row.accentColor)
                    .frame(width: 14, height: 14)
                    .offset(x: x - 7, y: (rowH - 14) / 2)
            } else if let barStart = row.barStart {
                let x0    = gx(barStart)
                let x1    = max(x0 + dayW, gx(row.barEnd))
                let barW  = x1 - x0

                // Barre principale
                RoundedRectangle(cornerRadius: 4)
                    .fill(row.accentColor.opacity(row.isCompleted ? 0.45 : 0.70))
                    .frame(width: barW, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(row.accentColor, lineWidth: 1)
                    )
                    .offset(x: x0, y: (rowH - 14) / 2)

                // Marqueur deadline (triangle)
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(row.accentColor)
                    .rotationEffect(.degrees(180))
                    .offset(x: x1 - 4, y: rowH / 2 + 5)
            }
        }
    }

    // Fond du Gantt (bandes alternées + traits de mois)
    private var ganttBackground: some View {
        ZStack(alignment: .topLeading) {
            // Bandes paires/impaires par rangée
            VStack(spacing: 0) {
                ForEach(Array(ganttRows.enumerated()), id: \.offset) { idx, _ in
                    Rectangle()
                        .fill(idx % 2 == 0 ? Color.clear : Color.black.opacity(0.018))
                        .frame(height: rowH)
                    if idx < ganttRows.count - 1 { Divider().opacity(0) }
                }
            }
            // Traits verticaux de mois
            ForEach(monthsInRange(), id: \.self) { monthStart in
                Rectangle()
                    .fill(Color.cardBorder.opacity(0.8))
                    .frame(width: 1, height: CGFloat(ganttRows.count) * rowH)
                    .offset(x: gx(monthStart))
            }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private func monthsInRange() -> [Date] {
        let cal = Calendar.current
        var months: [Date] = []
        var cursor = cal.date(
            from: cal.dateComponents([.year, .month], from: ganttStart))!
        while cursor <= ganttEnd {
            if cursor > ganttStart { months.append(cursor) }
            cursor = cal.date(byAdding: .month, value: 1, to: cursor)!
        }
        return months
    }

    private func monthLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMM yy"
        return fmt.string(from: date).capitalized
    }
}

// MARK: - Formulaire Jalon (nouveau ou édition)

struct MilestoneFormView: View {
    @ObservedObject var store: DataStore
    let project: Project
    var existing: Milestone? = nil   // #26/#28 — nil = nouveau jalon

    @Environment(\.dismiss) var dismiss

    @State private var title: String = ""
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var recurrence: MilestoneRecurrence? = nil  // #28
    // #42 — rappels personnalisables
    @State private var reminderDays: Int = 7
    @State private var reminderHour: Int = 9
    // #43 — lien chapitre
    @State private var linkedChapterId: UUID? = nil
    // #44 — statut enrichi
    @State private var milestoneStatus: MilestoneStatus = .pending

    private var isEditing: Bool { existing != nil }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {

                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isEditing ? "Modifier le jalon" : "Nouveau jalon")
                            .font(TypeScale.pageTitle)
                        HStack(spacing: 4) {
                            if let type = project.projectType {
                                Image(systemName: type.icon)
                                    .font(.system(size: AppLook.fs(10)))
                            }
                            Text(project.name)
                                .font(.system(size: 12))
                        }
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

                // Champs
                VStack(spacing: 0) {
                    // Titre
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "flag.fill")
                                .font(.system(size: 13)).foregroundColor(.accent)
                        }
                        TextField("Titre du jalon…", text: $title)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                    }
                    .padding(14)

                    Divider().padding(.leading, 48)

                    // Date
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "calendar")
                                .font(.system(size: 13)).foregroundColor(.accentWarm)
                        }
                        Text("Date cible")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .accentColor(.accent)
                    }
                    .padding(14)

                    Divider().padding(.leading, 48)

                    // #28 — Récurrence
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.purple.opacity(0.10)).frame(width: 34, height: 34)
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13)).foregroundColor(.purple)
                        }
                        Text("Récurrence")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $recurrence) {
                            Text("Aucune").tag(MilestoneRecurrence?.none)
                            ForEach(MilestoneRecurrence.allCases, id: \.self) { r in
                                Text(r.label).tag(MilestoneRecurrence?.some(r))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    .padding(14)

                    Divider().padding(.leading, 48)

                    // #44 — Statut enrichi
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(milestoneStatus.color.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: milestoneStatus.icon)
                                .font(.system(size: 13)).foregroundColor(milestoneStatus.color)
                        }
                        Text("Statut")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $milestoneStatus) {
                            ForEach(MilestoneStatus.allCases) { s in
                                Label(s.label, systemImage: s.icon).tag(s)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    .padding(14)

                    Divider().padding(.leading, 48)

                    // #42 — Rappels personnalisables
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.accent.opacity(0.10)).frame(width: 34, height: 34)
                                Image(systemName: "bell.badge")
                                    .font(.system(size: 13)).foregroundColor(.accent)
                            }
                            Text("Rappel")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Stepper("\(reminderDays) j avant", value: $reminderDays, in: 1...90)
                                .font(.system(size: 12))
                                .frame(width: 160)
                        }
                        .padding(14)

                        HStack(spacing: 14) {
                            Color.clear.frame(width: 34, height: 20)
                            Text("Heure")
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Picker("", selection: $reminderHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02dh00", h)).tag(h)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                        .padding(.horizontal, 14).padding(.bottom, 14)
                    }

                    Divider().padding(.leading, 48)

                    // #43 — Lien chapitre
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentGreen.opacity(0.10)).frame(width: 34, height: 34)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 13)).foregroundColor(.accentGreen)
                        }
                        Text("Chapitre lié")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Picker("", selection: $linkedChapterId) {
                            Text("Aucun").tag(UUID?.none)
                            ForEach(project.chapters) { ch in
                                Text(ch.name).tag(UUID?.some(ch.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    .padding(14)

                    Divider().padding(.leading, 48)

                    // Notes
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Color.labelMuted.opacity(0.10)).frame(width: 34, height: 34)
                            Image(systemName: "note.text")
                                .font(.system(size: 13)).foregroundColor(.labelMuted)
                        }
                        TextField("Notes (optionnel)…", text: $notes, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(3, reservesSpace: true)
                    }
                    .padding(14)
                }
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20)))
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(14, 20)).stroke(Color.cardBorder, lineWidth: 1))

                // Boutons
                HStack(spacing: 12) {
                    Button("Annuler") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.cardBg)
                        .clipShape(AppLook.buttonShape(10))
                        .overlay(AppLook.buttonShape(10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable)
                        .keyboardShortcut(.escape)

                    Spacer()

                    Button(isEditing ? "Enregistrer" : "Ajouter") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(title.trimmingCharacters(in: .whitespaces).isEmpty ? Color.accent.opacity(0.4) : Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                        .buttonStyle(.pressable)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 460)
        .onAppear {
            if let m = existing {
                title           = m.title
                date            = DataStore.parseDate(m.date) ?? Date()
                notes           = m.notes ?? ""
                recurrence      = m.recurrence
                reminderDays    = m.reminderDays
                reminderHour    = m.reminderHour
                linkedChapterId = m.linkedChapterId
                milestoneStatus = m.milestoneStatus
            }
        }
    }

    private func save() {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let notesVal = notes.trimmingCharacters(in: .whitespaces)
        let titleVal = title.trimmingCharacters(in: .whitespaces)

        if isEditing, let m = existing {
            let updated = Milestone(
                id: m.id,
                title: titleVal,
                date: fmt.string(from: date),
                isCompleted: m.isCompleted,
                notes: notesVal.isEmpty ? nil : notesVal,
                recurrence: recurrence,
                reminderDays: reminderDays,
                reminderHour: reminderHour,
                linkedChapterId: linkedChapterId,
                milestoneStatus: milestoneStatus
            )
            store.updateMilestone(updated, in: project.id)
        } else {
            let milestone = Milestone(
                id: UUID(),
                title: titleVal,
                date: fmt.string(from: date),
                isCompleted: false,
                notes: notesVal.isEmpty ? nil : notesVal,
                recurrence: recurrence,
                reminderDays: reminderDays,
                reminderHour: reminderHour,
                linkedChapterId: linkedChapterId,
                milestoneStatus: milestoneStatus
            )
            store.addMilestone(milestone, to: project.id)
        }
        dismiss()
    }
}
