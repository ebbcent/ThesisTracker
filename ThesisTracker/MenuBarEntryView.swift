import SwiftUI

struct MenuBarEntryView: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoroController: PomodoroAppController

    @State private var inputText: String = ""
    @State private var savedConfirmation = false
    @State private var selectedDate: Date = Date()

    private var today: String { DataStore.today }
    private var selectedDateStr: String { DataStore.dateString(from: selectedDate) }
    private var isToday: Bool { selectedDateStr == today }
    private var activeProject: Project? { store.activeProject }
    private var activeChapter: Chapter? { store.activeChapter }

    private var inputInt: Int? {
        Int(inputText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private var todayProgress: Int { store.dailyProgress }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .foregroundColor(.accent).font(.system(size: 13, weight: .semibold))
                Text("Writing Process")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Spacer()
                if store.currentStreak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10)).foregroundColor(Color.semOrange)
                        Text("\(store.currentStreak)j")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.semOrange)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            Divider()

            if store.data.projects.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.labelMuted.opacity(0.7))
                    Text("Aucun projet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.labelMuted)
                    Text("Crée ton premier projet dans la fenêtre principale pour commencer à suivre ton écriture.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.labelMuted.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                    Button("Ouvrir Writing Process") { openMainWindow() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accent)
                        .clipShape(Capsule())
                        .buttonStyle(.pressable)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .accessibilityElement(children: .contain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    // Sélecteurs
                    projectChapterSelectors

                    Divider()

                    // Date toggle
                    dateToggle

                    Divider()

                    // Entrée chiffre
                    HStack(spacing: 8) {
                        TextField(
                            activeChapter.map { "\($0.entryForDate(selectedDateStr)?.totalCount ?? 0)" } ?? "0",
                            text: $inputText
                        )
                        .font(.system(size: 18, weight: .bold))
                        .textFieldStyle(.plain)
                        .foregroundColor(.primary)
                        .onSubmit { saveEntry() }
                        .onAppear { refreshInput() }
                        .accessibilityLabel(store.data.useWordCount ? "Total de mots pour \(activeChapter?.name ?? "ce chapitre")" : "Total de caractères pour \(activeChapter?.name ?? "ce chapitre")")

                        Text(store.data.useWordCount ? "mots" : "car.")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)

                        Spacer()

                        Button(action: saveEntry) {
                            Image(systemName: savedConfirmation ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(savedConfirmation ? .accentGreen : .accent)
                        }
                        .buttonStyle(.pressable)
                        .disabled(inputInt == nil)
                        .accessibilityLabel(savedConfirmation ? "Saisie enregistrée" : "Enregistrer la saisie")
                    }

                    // Progress aujourd'hui
                    if store.effectiveDailyGoal > 0 {
                        progressBar
                    }

                    // Mini-sparkline 7 derniers jours
                    sevenDaySparkline
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }

            Divider()

            // Pomodoro timer section
            pomodoroSection

            Divider()

            // Footer
            HStack(spacing: 10) {
                Button("Ouvrir l'app") { openMainWindow() }
                    .font(.system(size: 11)).foregroundColor(.accent).buttonStyle(.pressable)
                Button {
                    QuickEntryPanelManager.shared.show(store: store)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 10))
                        Text("Saisie rapide")
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.accentWarm)
                }
                .buttonStyle(.pressable)
                .help("Ouvrir le panneau de saisie rapide (⌃⌥N)")
                Spacer()
                if todayProgress > 0 {
                    Text("+\(store.formatCountShort(todayProgress)) aujourd'hui")
                        .font(.system(size: 10)).foregroundColor(.labelMuted)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Pomodoro section

    // 5.20 — même cadran et mêmes commandes que l'onglet Minuteur (5.19)
    private var pomodoroSection: some View {
        let snap = pomodoroController.timerSnapshot
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                TimerDialView(
                    title: snap.phase.activeMode?.displayName ?? (menuPendingBreak != nil ? "Pause" : "Prêt"),
                    timeText: pomodoroController.formattedDuration(snap.remainingTime),
                    progress: snap.phase == .idle ? 0 : menuProgress,
                    accentColor: menuTint,
                    size: 112,
                    detail: "",
                    isPaused: snap.phase.isPaused
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text(menuDetail)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: menuPrimaryAction) {
                        Label(menuPrimaryTitle, systemImage: menuPrimaryIcon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(Capsule().fill(menuPrimaryEnabled ? menuButtonTint : Color.labelMuted.opacity(0.35)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(!menuPrimaryEnabled)

                    HStack(spacing: 8) {
                        menuCircleButton("stop.fill", help: "Arrêter le bloc", enabled: snap.phase != .idle) {
                            pomodoroController.stopTimer()
                        }
                        menuCircleButton("forward.end.fill", help: "Passer la pause proposée", enabled: menuPendingBreak != nil) {
                            pomodoroController.skipPendingPhase()
                        }
                        Spacer(minLength: 0)
                        if snap.completedFocusCountInCycle > 0 {
                            HStack(spacing: 3) {
                                ForEach(0..<max(1, pomodoroController.data.settings.sessionsBeforeLongBreak), id: \.self) { i in
                                    Circle()
                                        .fill(i < snap.completedFocusCountInCycle ? menuTint : Color.glassBorder)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .help("\(snap.completedFocusCountInCycle) bloc(s) dans ce cycle")
                        }
                    }
                }
            }

            // Intention du bloc en cours
            if snap.phase.activeMode == .focus, let intention = pomodoroController.activeIntention {
                Label(intention, systemImage: "scope")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Durées rapides, au repos
            if snap.phase == .idle && menuPendingBreak == nil {
                let current = Int(pomodoroController.data.settings.focusDuration / 60)
                HStack(spacing: 5) {
                    ForEach([25, 45, 50, 90], id: \.self) { m in
                        let on = m == current
                        Button {
                            pomodoroController.data.settings.focusDuration = TimeInterval(m * 60)
                            pomodoroController.saveSettings()
                        } label: {
                            Text("\(m) min")
                                .font(.system(size: 10, weight: on ? .semibold : .medium).monospacedDigit())
                                .foregroundStyle(on ? Color.accent : Color.secondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(on ? Color.accent.opacity(0.12) : Color.clear))
                                .overlay(Capsule().stroke(on ? Color.accent.opacity(0.3) : Color.glassBorder, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity)
                .help("Durée des blocs de concentration")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var menuPendingBreak: ActiveTimerMode? {
        guard pomodoroController.timerSnapshot.phase == .idle,
              let next = pomodoroController.pendingNextMode, next != .focus else { return nil }
        return next
    }

    private var menuProgress: Double {
        let snap = pomodoroController.timerSnapshot
        guard snap.totalDuration > 0 else { return 0 }
        return min(1, max(0, 1 - snap.remainingTime / snap.totalDuration))
    }

    private var menuTint: Color {
        switch pomodoroController.timerSnapshot.phase.activeMode ?? menuPendingBreak {
        case .shortBreak?: return CockpitTheme.success
        case .longBreak?:  return CockpitTheme.glow
        default:           return .accent
        }
    }

    private var menuButtonTint: Color { menuTint }

    private var menuPrimaryEnabled: Bool {
        pomodoroController.timerSnapshot.phase != .idle || pomodoroController.canStartSession
    }

    private var menuPrimaryTitle: String {
        switch pomodoroController.timerSnapshot.phase {
        case .running: return "Pause"
        case .paused:  return "Reprendre"
        case .idle:    return menuPendingBreak != nil ? "Lancer la pause" : "Démarrer"
        }
    }

    private var menuPrimaryIcon: String {
        switch pomodoroController.timerSnapshot.phase {
        case .running: return "pause.fill"
        case .paused:  return "play.fill"
        case .idle:    return menuPendingBreak != nil ? "cup.and.saucer.fill" : "play.fill"
        }
    }

    private var menuDetail: String {
        let snap = pomodoroController.timerSnapshot
        let settings = pomodoroController.data.settings
        switch snap.phase {
        case .running:
            guard let end = snap.expectedEndDate else { return "" }
            return "Fin à " + end.formatted(date: .omitted, time: .shortened)
        case .paused:
            return "En pause"
        case .idle:
            if let b = menuPendingBreak {
                let d = b == .longBreak ? settings.longBreakDuration : settings.shortBreakDuration
                return "Pause proposée · \(Int(d / 60)) min"
            }
            if let ch = store.activeChapter { return "Bloc de \(Int(settings.focusDuration / 60)) min · \(ch.shortLabel)" }
            return "Bloc de \(Int(settings.focusDuration / 60)) min"
        }
    }

    private func menuPrimaryAction() {
        switch pomodoroController.timerSnapshot.phase {
        case .running, .paused:
            pomodoroController.pauseOrResume()
        case .idle:
            if menuPendingBreak != nil {
                pomodoroController.startRecommendedSession()
            } else {
                // Comme le raccourci du tableau de bord : bloc rattaché au chapitre actif
                if let p = store.activeProject, let c = store.activeChapter {
                    pomodoroController.selectedWritingProjectId = p.id
                    pomodoroController.selectedWritingChapterId = c.id
                }
                pomodoroController.startFocusSession()
            }
        }
    }

    private func menuCircleButton(_ icon: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.glassFill))
                .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: - Selectors

    @ViewBuilder
    private var projectChapterSelectors: some View {
        if store.data.projects.count > 1 {
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
        }

        if let project = activeProject, project.chapters.count > 1 {
            CompactDropdownPicker(
                icon: "book.closed.fill",
                iconColor: .accentWarm,
                placeholder: "Choisir un chapitre",
                items: project.chapters.map { (id: $0.id, name: $0.name) },
                selectedId: project.activeChapterId
            ) { id in
                if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                    store.data.projects[idx].activeChapterId = id
                    store.save()
                    refreshInput()
                }
            }
        } else if let chapter = activeChapter {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11)).foregroundColor(.accentWarm)
                Text(chapter.name)
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Color.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.glassBorder, lineWidth: 1))
        }
    }

    // MARK: - Date toggle

    private var dateToggle: some View {
        HStack(spacing: 6) {
            dateChip("Aujourd'hui", isSelected: isToday) {
                selectedDate = Date()
                refreshInput()
            }
            dateChip("Hier", isSelected: !isToday) {
                let cal = Calendar(identifier: .gregorian)
                selectedDate = cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()
                refreshInput()
            }
            Spacer()
            if !isToday {
                Label("Entrée passée", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundColor(.semOrange)
            }
        }
    }

    private func dateChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .labelMuted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Cible : \(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Sparkline 7 jours

    private var sevenDaySparkline: some View {
        let totals = store.lastSevenDaysTotals
        let maxVal = max(1, totals.max() ?? 1)
        let avg = store.sevenDayAverage
        let bestIdx = totals.enumerated().max(by: { $0.element < $1.element })?.offset ?? -1
        let bestValue = totals.max() ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("7 derniers jours")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.labelMuted)
                Spacer()
                Text("Moy. \(store.formatCountShort(avg))/j")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted.opacity(0.75))
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(totals.enumerated()), id: \.offset) { idx, value in
                    let h = max(2, CGFloat(value) / CGFloat(maxVal) * 22)
                    let isToday = idx == totals.count - 1
                    let isBest = idx == bestIdx && bestValue > 0
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(value == 0 ? Color.labelMuted.opacity(0.2)
                              : isToday ? Color.accent
                              : isBest ? Color.accentGreen
                              : Color.accent.opacity(0.55))
                        .frame(height: h)
                        .help(sparklineTooltip(daysAgo: totals.count - 1 - idx, value: value, isBest: isBest))
                }
            }
            .frame(height: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Activité des 7 derniers jours")
            .accessibilityValue("Moyenne \(store.formatCount(avg)) par jour, meilleur jour \(store.formatCount(bestValue))")
            if bestValue > 0, bestIdx >= 0 {
                HStack(spacing: 3) {
                    Circle().fill(Color.accentGreen).frame(width: 5, height: 5)
                    Text("Meilleur jour : \(store.formatCountShort(bestValue))")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted.opacity(0.7))
                }
            }
        }
    }

    private func sparklineTooltip(daysAgo: Int, value: Int, isBest: Bool = false) -> String {
        let label: String
        switch daysAgo {
        case 0: label = "Aujourd'hui"
        case 1: label = "Hier"
        default: label = "Il y a \(daysAgo) jours"
        }
        let suffix = isBest && value > 0 ? " · 🏆 meilleur jour" : ""
        return "\(label) · \(store.formatCount(value))\(suffix)"
    }

    // MARK: - Progress

    private var progressBar: some View {
        let goal = store.effectiveDailyGoal
        let ratio = min(1.0, Double(todayProgress) / Double(goal))
        let color: Color = ratio >= 1 ? .accentGreen : .accent
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(color)
                        .frame(width: geo.size.width * ratio, height: 5)
                }
            }
            .frame(height: 5)
            Text("\(Int(ratio * 100))% de l'objectif journalier")
                .font(.system(size: 10)).foregroundColor(.labelMuted)
        }
    }

    // MARK: - Actions

    private func saveEntry() {
        guard let count = inputInt,
              let chapter = activeChapter,
              let project = activeProject else { return }
        store.setTotalForDate(count, for: chapter.id, in: project.id, date: selectedDateStr)
        withAppAnimation { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAppAnimation { savedConfirmation = false }
        }
    }

    private func refreshInput() {
        guard let chapter = activeChapter else { inputText = ""; return }
        inputText = chapter.entryForDate(selectedDateStr).map { "\($0.totalCount)" } ?? ""
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows { window.makeKeyAndOrderFront(nil) }
    }
}
