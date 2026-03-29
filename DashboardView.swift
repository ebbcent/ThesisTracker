import SwiftUI

struct DashboardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var inputText: String = ""
    @State private var noteText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showSettings = false
    @State private var savedConfirmation = false
    @State private var showDeleteConfirm = false
    @State private var streakPulse = false
    @AppStorage("lastStreakMilestone") private var lastStreakMilestone: Int = 0
    @FocusState private var countFieldFocused: Bool

    private var activeProject: Project? { store.activeProject }
    private var activeChapter: Chapter? { store.activeChapter }
    private var selectedDateStr: String { DataStore.dateString(from: selectedDate) }
    private var isToday: Bool { selectedDateStr == DataStore.today }
    private var hasExistingEntry: Bool { activeChapter?.entryForDate(selectedDateStr) != nil }

    private var todayIncrement: Int {
        let todayStr = DataStore.today
        return activeProject?.chapters.reduce(0) { $0 + $1.increment(for: todayStr) } ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerView

                HStack(alignment: .top, spacing: 16) {
                    // Colonne gauche — saisie + calendrier
                    VStack(spacing: 16) {
                        projectChapterSelector
                        if activeChapter != nil {
                            entryCard
                            recentEntriesSection
                        } else {
                            emptyState
                        }
                        weekCalendarSection
                    }
                    .frame(maxWidth: .infinity)

                    // Colonne droite — statistiques
                    VStack(spacing: 16) {
                        miniChartSection
                        DailySessionCard(store: store)   // V3.3 — boucle quotidienne
                        if activeChapter != nil {
                            progressSection
                            planningSection
                        }
                        insightsSection
                        WeeklyChallengeCard(store: store)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .onAppear {
            refreshInput()
            if activeChapter != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    countFieldFocused = true
                }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .alert("Effacer cette entrée ?", isPresented: $showDeleteConfirm) {
            Button("Effacer", role: .destructive) {
                if let chapter = activeChapter, let project = activeProject {
                    withAnimation { store.deleteEntry(for: chapter.id, in: project.id, date: selectedDateStr) }
                    inputText = ""
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'entrée du \(formattedSelectedDate) sera supprimée définitivement.")
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
                Text("Tableau de bord")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                HStack(spacing: 8) {
                    Text(formattedDate)
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                    if store.currentStreak > 0 {
                        streakBadge
                    }
                    momentumBadge
                }
            }

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.glassFill)
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var streakBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("\(store.currentStreak) j")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.accentWarm)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.accentWarm.opacity(0.12))
                .overlay(
                    Capsule().stroke(Color.accentWarm.opacity(0.22), lineWidth: 1)
                )
        )
        .scaleEffect(streakPulse ? 1.18 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.5), value: streakPulse)
    }

    private var momentumBadge: some View {
        let score = store.momentumScore
        let color: Color = score >= 70 ? .accentGreen : score >= 40 ? .orange : .red
        return HStack(spacing: 5) {
            Text("⚡")
                .font(.system(size: 10))
            Text("\(score)")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        )
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
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar = true }
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
                    .buttonStyle(.plain)
                }

                if let project = activeProject, !project.chapters.isEmpty {
                    Divider()

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
                }
            }
        }
    }

    // MARK: - Entry card

    private var entryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Saisie")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(0.8)
                    Spacer()
                    HStack(spacing: 8) {
                        if !isToday {
                            Label("Passé", systemImage: "clock.arrow.circlepath")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(Color.orange.opacity(0.12))
                                    .overlay(Capsule().stroke(Color.orange.opacity(0.20), lineWidth: 1)))
                                .transition(.scale.combined(with: .opacity))
                        }
                        if hasExistingEntry {
                            Button { showDeleteConfirm = true } label: {
                                Label("Effacer", systemImage: "trash")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.destructiveRed)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(Capsule().fill(Color.red.opacity(0.10))
                                        .overlay(Capsule().stroke(Color.red.opacity(0.20), lineWidth: 1)))
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: hasExistingEntry)
                    .animation(.spring(response: 0.3), value: isToday)
                }
                .padding(.bottom, 16)

                HStack(spacing: 10) {
                    CompactDatePicker(date: $selectedDate, maxDate: Date())
                        .onChange(of: selectedDate) { _, _ in refreshInput() }
                    Spacer()
                    if isToday && todayIncrement > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.accentGreen)
                            Text("+\(store.formatCount(todayIncrement)) ajoutés")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentGreen)
                        }
                        .transition(.opacity.combined(with: .scale))
                        .animation(.spring(response: 0.3), value: todayIncrement)
                    }
                }
                .padding(.bottom, 14)

                Divider().padding(.bottom, 14)

                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.123")
                            .foregroundColor(.labelMuted)
                            .font(.system(size: 13))
                        TextField("ex: 15 340", text: $inputText)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .textFieldStyle(.plain)
                            .focused($countFieldFocused)
                            .onSubmit { saveEntry() }
                        Text("car.")
                            .foregroundColor(.labelMuted)
                            .font(.system(size: 13))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.fieldBg)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.cardBorder, lineWidth: 1))
                    )

                    Button(action: saveEntry) {
                        HStack(spacing: 6) {
                            Image(systemName: savedConfirmation ? "checkmark" : "arrow.down.circle.fill")
                                .font(.system(size: 13))
                            Text(savedConfirmation ? "Enregistré" : "Sauvegarder")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(savedConfirmation ? Color.accentGreen : Color.accent)
                                .shadow(color: (savedConfirmation ? Color.accentGreen : Color.accent).opacity(0.35),
                                        radius: 8, x: 0, y: 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(inputInt == nil)
                    .animation(.easeInOut(duration: 0.25), value: savedConfirmation)
                }

                // Note du jour
                Divider().padding(.top, 4)
                HStack(spacing: 8) {
                    Image(systemName: "note.text").foregroundColor(.labelMuted).font(.system(size: 12))
                    TextField("Note du jour (optionnel)…", text: $noteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .onSubmit { saveNote() }
                        .onChange(of: noteText) { _, _ in
                            // Auto-save la note après saisie (seulement si une entrée existe)
                            if hasExistingEntry { saveNote() }
                        }
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Dernières saisies

    private var recentChapterEntries: [(dateLabel: String, delta: Int, total: Int)] {
        guard let chapter = activeChapter else { return [] }
        let sorted = chapter.entries.sorted { $0.date > $1.date }
        let shortFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.dateFormat = "EEE d MMM"
            return f
        }()
        return sorted.prefix(3).compactMap { entry -> (String, Int, Int)? in
            guard let date = DataStore.parseDate(entry.date) else { return nil }
            let label = shortFormatter.string(from: date).capitalized
            let delta = chapter.increment(for: entry.date)
            return (label, delta, entry.totalCount)
        }
    }

    @ViewBuilder
    private var recentEntriesSection: some View {
        if activeChapter != nil {
            let entries = recentChapterEntries
            if !entries.isEmpty {
                VStack(spacing: 10) {
                    SectionHeader("Dernières saisies")
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(entries.indices, id: \.self) { i in
                                if i > 0 { Divider().padding(.vertical, 8) }
                                HStack(spacing: 8) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 11))
                                        .foregroundColor(.labelMuted)
                                    Text(entries[i].dateLabel)
                                        .font(.system(size: 12))
                                        .foregroundColor(.labelMuted)
                                    Spacer()
                                    Text("+\(store.formatCount(entries[i].delta))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accentGreen)
                                    Text(store.formatCount(entries[i].total))
                                        .font(.system(size: 11))
                                        .foregroundColor(.labelMuted)
                                }
                            }
                        }
                    }
                }
            }
        }
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
        return (0..<14).reversed().map { offset -> Int in
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { return 0 }
            let dateStr = DataStore.dateString(from: date)
            return project.chapters.reduce(0) { $0 + $1.increment(for: dateStr) }
        }
    }

    // MARK: - Progress section

    private var progressSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Progression")
            GlassCard {
                VStack(spacing: 0) {
                    ProgressBarView(
                        label: "Aujourd'hui",
                        icon: "sun.max.fill",
                        value: store.dailyProgress,
                        goal: store.data.dailyGoal,
                        color: Color.accent,
                        trackColor: Color.accent.opacity(0.12)
                    )
                    if let ddg = store.deadlineDailyGoal, store.deadlineDailyGoalDiffers {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 9)).foregroundColor(.urgentRed)
                            Text("Deadline : \(store.formatCount(ddg)) / jour pour finir le chapitre")
                                .font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.urgentRed.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.urgentRed.opacity(0.15), lineWidth: 1))
                        .padding(.top, 4)
                    } else if store.adaptedDailyGoalDiffers {
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9)).foregroundColor(.accentWarm)
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
                    }
                }
            }
        }
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
                            subtitle: chapter.deadline.flatMap(DataStore.parseDate).map { "Deadline \(DataStore.formatDate($0))" } ?? "Sans deadline"
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
        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        var increments: [Int] = []
        for offset in 1...14 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let ds = DataStore.dateString(from: date)
            let total = (store.activeProject?.chapters ?? []).reduce(0) { $0 + $1.increment(for: ds) }
            if total > 0 { increments.append(total) }
        }
        guard !increments.isEmpty else { return 0 }
        return increments.reduce(0, +) / increments.count
    }

    private var chapterRequiredVelocity: Int {
        guard let chapter = activeChapter,
              let project = activeProject,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr) else { return 0 }
        let cal = Calendar(identifier: .gregorian)
        let daysLeft = cal.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        guard daysLeft > 0 else { return 0 }
        let latest = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
        let remaining = max(0, chapter.goal - latest)
        guard remaining > 0 else { return 0 }
        return Int(ceil(Double(remaining) / Double(daysLeft)))
    }

    private var daysToChapterDeadline: Int? {
        guard let chapter = activeChapter,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
        return days >= 0 ? days : nil
    }

    @ViewBuilder
    private func velocityRow(chapter: Chapter) -> some View {
        let vel = currentVelocity
        let req = chapterRequiredVelocity
        let daysLeft = daysToChapterDeadline

        VStack(spacing: 8) {
            HStack(spacing: 0) {
                Text("À MON RYTHME")
                    .font(.system(size: 9, weight: .bold))
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
                        Text("Objectif deadline")
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
                            .foregroundColor(days < 7 ? .urgentRed : .primary)
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
                    .font(.system(size: 9, weight: .bold))
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
                                .onTapGesture {
                                    guard !days[i].isFuture else { return }
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        selectedDate = days[i].date
                                    }
                                    countFieldFocused = true
                                }
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

    private var currentWeekData: [WeekDayData] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2   // Lundi
        let today = Date()
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let todayStr = DataStore.today
        let allChapters = store.data.projects.flatMap { $0.chapters }
        let letters = ["D", "L", "M", "M", "J", "V", "S"]
        var result: [WeekDayData] = []
        var current = weekInterval.start
        for _ in 0..<7 {
            let dateStr = DataStore.dateString(from: current)
            let written  = allChapters.reduce(0) { $0 + $1.increment(for: dateStr) }
            let weekday  = cal.component(.weekday, from: current)
            result.append(WeekDayData(
                date:      current,
                dateStr:   dateStr,
                written:   written,
                isToday:   dateStr == todayStr,
                isFuture:  current > today,
                letter:    letters[weekday - 1],
                dayNumber: cal.component(.day, from: current)
            ))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return result
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
                        .font(.system(size: 9, weight: .bold)).foregroundColor(.white)
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
                            color: .insightPurple,
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

    // MARK: - Insights computed data

    private var insightBestWeekday: (name: String, avg: Int) {
        let totals = store.dailyTotals()
        let cal = Calendar(identifier: .gregorian)
        let frenchDays = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"]
        var byWeekday: [Int: [Int]] = [:]
        for (dateStr, val) in totals {
            guard val > 0, let date = DataStore.parseDate(dateStr) else { continue }
            let wd = cal.component(.weekday, from: date)
            byWeekday[wd, default: []].append(val)
        }
        guard !byWeekday.isEmpty else { return ("—", 0) }
        let best = byWeekday.max { lhs, rhs in
            (lhs.value.reduce(0, +) / lhs.value.count) < (rhs.value.reduce(0, +) / rhs.value.count)
        }!
        let avg = best.value.reduce(0, +) / best.value.count
        return (frenchDays[best.key - 1], avg)
    }

    private var insightGoalDays: Int {
        guard store.data.dailyGoal > 0 else { return 0 }
        let cal = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()
        var count = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            if (totals[DataStore.dateString(from: date)] ?? 0) >= store.data.dailyGoal { count += 1 }
        }
        return count
    }

    private var insightGoalRate: Int {
        Int(Double(insightGoalDays) / 30.0 * 100)
    }

    private var insightRecord: (chars: Int, label: String) {
        let totals = store.dailyTotals()
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return (0, "") }
        let label = DataStore.parseDate(best.key).map { DataStore.formatDate($0) } ?? best.key
        return (best.value, label)
    }

    private var insightActiveDays30: Int {
        let cal = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()
        var count = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            if (totals[DataStore.dateString(from: date)] ?? 0) > 0 { count += 1 }
        }
        return count
    }

    private var insightAvg30: Int {
        guard insightActiveDays30 > 0 else { return 0 }
        let cal = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()
        var total = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            total += totals[DataStore.dateString(from: date)] ?? 0
        }
        return total / insightActiveDays30
    }

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
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar = true }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accent)
                    .shadow(color: Color.accent.opacity(0.35), radius: 8, x: 0, y: 3))
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Helpers

    private var inputInt: Int? {
        Int(inputText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private var formattedDate: String {
        DataStore.formatLongDate(Date(), capitalize: true)
    }

    private var formattedSelectedDate: String {
        DataStore.formatDate(selectedDate)
    }

    private func saveEntry() {
        guard let count = inputInt,
              let chapter = activeChapter,
              let project = activeProject else { return }
        withAnimation { store.setTotalForDate(count, for: chapter.id, in: project.id, date: selectedDateStr) }
        withAnimation(.spring(response: 0.3)) { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.spring(response: 0.3)) { savedConfirmation = false }
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

    private func saveNote() {
        guard let chapter = activeChapter, let project = activeProject, hasExistingEntry else { return }
        store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: selectedDateStr)
    }

    private func refreshInput() {
        guard let chapter = activeChapter else { inputText = ""; noteText = ""; return }
        let entry = chapter.entryForDate(selectedDateStr)
        inputText = entry.map { "\($0.totalCount)" } ?? ""
        noteText = entry?.note ?? ""
    }
}

// MARK: - Mini bar chart

private struct MiniBarChartView: View {
    let data: [Int]
    let color: Color
    let goal: Int

    private var maxVal: CGFloat { CGFloat(max(data.max() ?? 0, goal > 0 ? goal : 0, 1)) }

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
                                    color.opacity(max(0.18, ratio * 0.80))
                                )
                                .frame(height: max(2, geo.size.height * ratio))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
