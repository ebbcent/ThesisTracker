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
        .background(Color.appBg)   // 5.19 : fond uni, comme le reste de l'app
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
                    .font(TypeScale.pageTitle)
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
                statusChip(title: "Série", value: "\(controller.currentStreak) j")
                statusChip(title: "Cycle", value: "\(controller.timerSnapshot.completedFocusCountInCycle)")
                statusChip(title: "Catégorie", value: controller.categoryName(for: controller.selectedCategoryID))
                statusChip(title: "Projet", value: controller.projectName(for: controller.selectedProjectID))
            }
        }
    }

    // MARK: - Timer card

    private var timerCard: some View {
        InfoCard(title: "Minuteur", systemImage: "timer", emphasized: true) {
            VStack(alignment: .center, spacing: 18) {
                sessionCompletionBurst(dial: TimerDialView(
                    title: controller.timerSnapshot.phase.activeMode?.displayName ?? (pendingBreak != nil ? "Pause proposée" : "Prêt"),
                    timeText: controller.formattedDuration(controller.timerSnapshot.remainingTime),
                    progress: controller.timerSnapshot.phase == .idle ? 0 : progress,
                    accentColor: tintColor,
                    size: 220,
                    detail: dialDetail,
                    isPaused: controller.timerSnapshot.phase.isPaused
                ))
                .frame(maxWidth: .infinity, alignment: .center)

                // 5.19 : une commande principale qui suit l'état, et des commandes secondaires rondes
                HStack(spacing: 12) {
                    circleButton("stop.fill", help: "Arrêter le bloc", enabled: controller.timerSnapshot.phase != .idle) {
                        controller.stopTimer()
                    }
                    Button(action: primaryAction) {
                        Label(primaryTitle, systemImage: primaryIcon)
                            .font(.system(size: 14, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.white)
                            .frame(minWidth: 170, minHeight: 40)
                            .background(Capsule().fill(primaryEnabled ? tintColorForButton : Color.labelMuted.opacity(0.35)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!primaryEnabled)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .help("\(primaryTitle) (⌘↩)")
                    circleButton("forward.end.fill", help: "Passer la pause proposée", enabled: pendingBreak != nil) {
                        controller.skipPendingPhase()
                    }
                }
                .frame(maxWidth: .infinity)

                if controller.timerSnapshot.phase == .idle && pendingBreak == nil {
                    durationPresets
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        categoryPicker
                        projectPicker
                    }
                    if hasWritingChapters {
                        writingChapterPicker
                    }
                    PomodoroIntentionField()
                }
            }
        }
    }

    // MARK: - 5.19 Commandes du minuteur

    private var pendingBreak: ActiveTimerMode? {
        guard controller.timerSnapshot.phase == .idle,
              let next = controller.pendingNextMode, next != .focus else { return nil }
        return next
    }

    private var primaryEnabled: Bool {
        switch controller.timerSnapshot.phase {
        case .idle: return controller.canStartSession
        default:    return true
        }
    }

    private var primaryTitle: String {
        switch controller.timerSnapshot.phase {
        case .running: return "Pause"
        case .paused:  return "Reprendre"
        case .idle:    return pendingBreak != nil ? "Lancer la pause" : "Démarrer"
        }
    }

    private var primaryIcon: String {
        switch controller.timerSnapshot.phase {
        case .running: return "pause.fill"
        case .paused:  return "play.fill"
        case .idle:    return pendingBreak != nil ? "cup.and.saucer.fill" : "play.fill"
        }
    }

    private func primaryAction() {
        switch controller.timerSnapshot.phase {
        case .running, .paused: controller.pauseOrResume()
        case .idle:
            if pendingBreak != nil { controller.startRecommendedSession() } else { controller.startFocusSession() }
        }
    }

    private var tintColorForButton: Color {
        if let b = pendingBreak { return b == .longBreak ? CockpitTheme.glow : CockpitTheme.success }
        return controller.timerSnapshot.phase == .idle ? Color.accent : tintColor
    }

    private var dialDetail: String {
        let snap = controller.timerSnapshot
        switch snap.phase {
        case .running:
            guard let end = snap.expectedEndDate else { return "" }
            return "fin à " + end.formatted(date: .omitted, time: .shortened)
        case .paused:
            return "en pause"
        case .idle:
            if let b = pendingBreak {
                let d = b == .longBreak ? controller.data.settings.longBreakDuration : controller.data.settings.shortBreakDuration
                return "\(Int(d / 60)) min de pause"
            }
            let done = snap.completedFocusCountInCycle
            return done > 0 ? "\(done) bloc\(done > 1 ? "s" : "") dans ce cycle" : ""
        }
    }

    private func circleButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                .frame(width: 36, height: 36)
                .background(Circle().fill(CockpitTheme.overlayFill(for: colorScheme)))
                .overlay(Circle().stroke(CockpitTheme.stroke(for: colorScheme), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    private var durationPresets: some View {
        let current = Int(controller.data.settings.focusDuration / 60)
        return HStack(spacing: 6) {
            ForEach([25, 45, 50, 90], id: \.self) { m in
                let on = m == current
                Button {
                    controller.data.settings.focusDuration = TimeInterval(m * 60)
                    controller.saveSettings()
                } label: {
                    Text("\(m) min")
                        .font(.system(size: 11, weight: on ? .semibold : .medium).monospacedDigit())
                        .foregroundStyle(on ? Color.accent : CockpitTheme.textSecondary(for: colorScheme))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(on ? Color.accent.opacity(0.12) : Color.clear))
                        .overlay(Capsule().stroke(on ? Color.accent.opacity(0.3) : CockpitTheme.stroke(for: colorScheme), lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .help("Durée des blocs de concentration")
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
                    compactMetric(title: store.data.useWordCount ? "Mots écrits" : "Signes écrits", value: store.formatCountShort(todayWords), color: CockpitTheme.glow)
                }
            }
            if wordsGoal > 0 {
                let completedFocus = snap.completedSessions
                let sessionTarget = completedFocus * wordsGoal
                let wordRatio = sessionTarget > 0 ? min(1.0, Double(todayWords) / Double(sessionTarget)) : 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(store.data.useWordCount ? "Mots / objectif des blocs" : "Signes / objectif des blocs")
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
            // 5.19 : sans historique, une phrase plutôt que des « 0 % »
            if p.probableWeekMinutes == 0 && p.bestFocusHours.isEmpty {
                Text("Pas encore assez de blocs terminés pour une prévision. Elle apparaît après quelques jours de minuteur.")
                    .font(.system(size: 12))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
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
        }
        .frame(maxWidth: .infinity)
    }

    private var dailyTimelineCard: some View {
        InfoCard(title: "Fil de la journée", systemImage: "calendar.day.timeline.left", emphasized: true) {
            if controller.selectedDayTimeline.isEmpty {
                Text("Aucun bloc sur cette journée. Lance-en un avec « Démarrer » ou depuis le tableau de bord.")
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

    /// 5.19 : fin de bloc = un sceau qui apparaît (léger rebond, absent si « Réduire les animations »),
    /// au lieu d'étoiles qui jaillissaient de rien.
    private func sessionCompletionBurst(dial: TimerDialView) -> some View {
        dial.overlay(alignment: .top) {
            if controller.focusSessionJustCompleted {
                Label("Bloc terminé", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CockpitTheme.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(CockpitTheme.success.opacity(0.12)))
                    .offset(y: -6)
                    .transition(Motion.reduce ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .appAnimation(Motion.celebrate, value: controller.focusSessionJustCompleted)
    }

    private func compactMetric(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.18))
                .frame(width: 4, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded).monospacedDigit())
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
            Text(title)   // 5.19 : casse normale, comme les titres de section
                .font(.system(size: 10, weight: .semibold, design: .rounded))
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
        return "\(ch.shortLabel) · \(proj.name)"
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
            title: "Catégorie",
            value: controller.categoryName(for: controller.selectedCategoryID),
            icon: "tag",
            accent: CockpitTheme.warning,
            items: [PremiumMenuItem(title: "Aucune catégorie", action: { controller.selectedCategoryID = nil })] +
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
