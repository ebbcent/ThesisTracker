import SwiftUI

struct PomodoroTodayView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var controller: PomodoroAppController
    @EnvironmentObject private var store: DataStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                HStack(alignment: .top, spacing: 20) {
                    VStack(spacing: 16) {
                        timerCard
                        predictionsCard
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 16) {
                        todaySummaryColumn
                        dailyTimelineCard
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(28)
        }
        .background(
            // Two RadialGradients approximate the previous "glow circles + blur(radius: 80/100)"
            // look at ~5% of the GPU cost — blur with radius >40 forces multiple Gaussian
            // passes per frame on Core Animation; radial gradients are essentially free.
            ZStack {
                LinearGradient(
                    colors: [CockpitTheme.backgroundTop(for: colorScheme), CockpitTheme.backgroundBottom(for: colorScheme)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [CockpitTheme.glow.opacity(0.10), .clear],
                    center: UnitPoint(x: 0.85, y: 0.15),
                    startRadius: 0,
                    endRadius: 320
                )
                RadialGradient(
                    colors: [CockpitTheme.accent.opacity(0.09), .clear],
                    center: UnitPoint(x: 0.10, y: 0.85),
                    startRadius: 0,
                    endRadius: 280
                )
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: $controller.isPresentingNoteEditor) {
            PomodoroSessionNoteSheet(store: store)
                .environmentObject(controller)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aujourd'hui")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                Text(controller.statusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                if let warning = controller.storageWarning {
                    Label(warning, systemImage: "exclamationmark.icloud")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            HStack(spacing: 10) {
                statusChip(title: "Streak", value: "\(controller.currentStreak) j")
                statusChip(title: "Cycle", value: "\(controller.timerSnapshot.completedFocusCountInCycle)")
                statusChip(title: "Catégorie", value: controller.categoryName(for: controller.selectedCategoryID))
                statusChip(title: "Projet", value: controller.projectName(for: controller.selectedProjectID))
            }
        }
    }

    // MARK: - Timer card

    private var timerCard: some View {
        InfoCard(title: "Minuteur", systemImage: "timer", emphasized: true) {
            VStack(alignment: .center, spacing: 16) {
                sessionCompletionBurst(dial: TimerDialView(
                    title: controller.timerSnapshot.phase.activeMode?.displayName ?? "Inactif",
                    timeText: controller.formattedDuration(controller.timerSnapshot.remainingTime),
                    progress: progress,
                    accentColor: tintColor,
                    size: 200
                ))
                .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 10) {
                    categoryPicker
                    projectPicker
                }

                if hasWritingChapters {
                    writingChapterPicker
                }

                PomodoroIntentionField()

                HStack(spacing: 10) {
                    Button("Démarrer") { controller.startFocusSession() }
                        .buttonStyle(CockpitButtonStyle(prominent: true))
                        .disabled(controller.timerSnapshot.phase != .idle || controller.isExternalFocusActive)
                    Button(controller.timerSnapshot.phase.isPaused ? "Reprendre" : "Pause") { controller.pauseOrResume() }
                        .buttonStyle(CockpitButtonStyle())
                        .disabled(controller.timerSnapshot.phase == .idle)
                    Button("Arrêter") { controller.stopTimer() }
                        .buttonStyle(CockpitButtonStyle())
                        .disabled(controller.timerSnapshot.phase == .idle)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Right column

    private var todaySummaryColumn: some View {
        VStack(spacing: 16) {
            todaysPerformanceCard
            goalsCard
            dailySummaryCard
        }
    }

    private var todaysPerformanceCard: some View {
        InfoCard(title: "Aujourd'hui", systemImage: "chart.bar.fill") {
            let snap = controller.todayOperationalSnapshot
            let todayWords = store.data.projects.flatMap { $0.chapters }
                .reduce(0) { $0 + $1.increment(for: DataStore.today) }
            let wordsGoal = controller.data.settings.wordsPerSessionGoal
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                compactMetric(title: "Terminées", value: "\(snap.completedSessions)", color: CockpitTheme.success)
                compactMetric(title: "Interrompues", value: "\(snap.interruptedSessions)", color: CockpitTheme.warning)
                compactMetric(title: "Concentration", value: "\(snap.focusMinutes) min", color: CockpitTheme.accent)
                compactMetric(title: "Objectif restant", value: "\(snap.remainingDailyMinutesGoal) min", color: CockpitTheme.glow)
                if todayWords > 0 {
                    compactMetric(title: "Mots écrits", value: store.formatCountShort(todayWords), color: CockpitTheme.glow)
                }
            }
            if wordsGoal > 0 {
                let completedFocus = snap.completedSessions
                let sessionTarget = completedFocus * wordsGoal
                let wordRatio = sessionTarget > 0 ? min(1.0, Double(todayWords) / Double(sessionTarget)) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Mots / objectif session")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                        Spacer()
                        Text("\(todayWords) / \(sessionTarget)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                    }
                    ProgressView(value: wordRatio)
                        .tint(wordRatio >= 1 ? CockpitTheme.success : CockpitTheme.glow)
                }
                .padding(.top, 4)
            }
            Text(snap.nextMilestoneText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                .padding(.top, 4)
        }
    }

    private var goalsCard: some View {
        InfoCard(title: "Objectifs", systemImage: "target") {
            VStack(spacing: 10) {
                ForEach(controller.goalProgress) { goal in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(goal.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                            Spacer()
                            Text(goal.description)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                        }
                        ProgressView(value: goal.progress)
                            .tint(CockpitTheme.glow)
                        Text(goal.remainingText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
                    }
                }
            }
        }
    }

    private var dailySummaryCard: some View {
        InfoCard(title: "Résumé", systemImage: "sun.max.fill") {
            let summary = controller.dailySummary
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.headline)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                Text(summary.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                ForEach(summary.highlights.prefix(3), id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(CockpitTheme.success)
                            .padding(.top, 5)
                        Text(item)
                            .font(.system(size: 12))
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    }
                }
            }
        }
    }

    private var predictionsCard: some View {
        InfoCard(title: "Prédictions", systemImage: "sparkles") {
            let p = controller.prediction
            VStack(alignment: .leading, spacing: 8) {
                predictionRow(label: "Productivité aujourd'hui", value: "\(p.probableTodayMinutes) min")
                predictionRow(label: "Productivité cette semaine", value: "\(p.probableWeekMinutes) min")
                predictionRow(label: "Objectif du jour", value: "\(Int(p.dailyGoalProbability * 100))%")
                predictionRow(label: "Objectif hebdomadaire", value: "\(Int(p.weeklyGoalProbability * 100))%")
                if !p.bestFocusHours.isEmpty {
                    predictionRow(
                        label: "Meilleures heures",
                        value: p.bestFocusHours.prefix(3).map { String(format: "%02d:00", $0) }.joined(separator: ", ")
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var dailyTimelineCard: some View {
        InfoCard(title: "Timeline de la journée", systemImage: "calendar.day.timeline.left", emphasized: true) {
            if controller.selectedDayTimeline.isEmpty {
                Text("Aucune session sur la journée sélectionnée.")
                    .font(.system(size: 13))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
            } else {
                VStack(spacing: 10) {
                    ForEach(controller.selectedDayTimeline) { segment in
                        HStack(alignment: .center, spacing: 10) {
                            Text(segment.startedAt.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
                                .frame(width: 52, alignment: .leading)
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(CockpitTheme.overlayFill(for: colorScheme))
                                        .frame(height: 28)
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color(hex: segment.colorHex).opacity(0.85))
                                        .frame(width: max(40, proxy.size.width * CGFloat(min(segment.durationHours / 6, 1))), height: 28)
                                    Text(segment.title)
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                }
                            }
                            .frame(height: 28)
                            Text(segment.subtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                                .frame(maxWidth: 180, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews helpers

    private func sessionCompletionBurst(dial: TimerDialView) -> some View {
        ZStack {
            dial
            if controller.focusSessionJustCompleted {
                ForEach(0..<8, id: \.self) { i in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CockpitTheme.glow)
                        .offset(burstOffset(index: i, radius: 110))
                        .scaleEffect(controller.focusSessionJustCompleted ? 1 : 0)
                        .opacity(controller.focusSessionJustCompleted ? 0 : 1)
                        .appAnimation(.easeOut(duration: 0.7).delay(Double(i) * 0.04), value: controller.focusSessionJustCompleted)
                }
            }
        }
    }

    private func burstOffset(index: Int, radius: CGFloat) -> CGSize {
        let angle = (Double(index) / 8.0) * 2 * .pi - .pi / 2
        return CGSize(width: Darwin.cos(angle) * radius, height: Darwin.sin(angle) * radius)
    }

    private func compactMetric(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.18))
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CockpitTheme.overlayFill(for: colorScheme))
        )
    }

    private func predictionRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CockpitTheme.panel(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(CockpitTheme.stroke(for: colorScheme), lineWidth: 1)
        )
    }

    private var hasWritingChapters: Bool {
        store.data.projects.contains { !$0.isArchived && !$0.chapters.isEmpty }
    }

    private var writingChapterCurrentLabel: String {
        guard let pid = controller.selectedWritingProjectId,
              let cid = controller.selectedWritingChapterId,
              let proj = store.data.projects.first(where: { $0.id == pid }),
              let ch   = proj.chapters.first(where: { $0.id == cid })
        else { return "Aucun" }
        return "\(ch.name) · \(proj.name)"
    }

    private var writingChapterPicker: some View {
        let chapterItems: [PremiumMenuItem] = store.data.projects
            .filter { !$0.isArchived }
            .flatMap { proj in
                proj.chapters.map { ch in
                    let pid = proj.id, cid = ch.id
                    return PremiumMenuItem(title: "\(ch.name) · \(proj.name)", action: {
                        controller.selectedWritingProjectId = pid
                        controller.selectedWritingChapterId = cid
                    })
                }
            }
        return PremiumMenuPicker(
            title: "Chapitre",
            value: writingChapterCurrentLabel,
            icon: "doc.text",
            accent: CockpitTheme.accent,
            items: [PremiumMenuItem(title: "Aucun chapitre", action: {
                controller.selectedWritingProjectId = nil
                controller.selectedWritingChapterId = nil
            })] + chapterItems
        )
    }

    private var categoryPicker: some View {
        PremiumMenuPicker(
            title: "Categorie",
            value: controller.categoryName(for: controller.selectedCategoryID),
            icon: "tag",
            accent: CockpitTheme.warning,
            items: [PremiumMenuItem(title: "Aucune categorie", action: { controller.selectedCategoryID = nil })] +
                controller.data.categories.map { cat in PremiumMenuItem(title: cat.name, action: { controller.selectedCategoryID = cat.id }) }
        )
    }

    private var projectPicker: some View {
        PremiumMenuPicker(
            title: "Projet",
            value: controller.projectName(for: controller.selectedProjectID),
            icon: "folder",
            accent: CockpitTheme.glow,
            items: [PremiumMenuItem(title: "Aucun projet", action: { controller.selectedProjectID = nil })] +
                controller.data.projects.map { proj in PremiumMenuItem(title: proj.name, action: { controller.selectedProjectID = proj.id }) }
        )
    }

    // MARK: - Computed

    private var progress: Double {
        guard controller.timerSnapshot.totalDuration > 0 else { return 1 }
        return 1 - (controller.timerSnapshot.remainingTime / controller.timerSnapshot.totalDuration)
    }

    private var tintColor: Color {
        switch controller.timerSnapshot.phase.activeMode {
        case .focus:      Color.accent          // #29 — suit la couleur d'accent de l'app
        case .shortBreak: CockpitTheme.success
        case .longBreak:  CockpitTheme.glow
        case .none:       CockpitTheme.textTertiary(for: colorScheme)
        }
    }
}
