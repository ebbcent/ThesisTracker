import SwiftUI

extension Notification.Name {
    static let navigateToTimer = Notification.Name("navigateToTimer")   // 5.19
}

// MARK: - 5.19 Raccourci Pomodoro du tableau de bord
//
// Un seul contrôle, qui change avec l'état du minuteur :
// - au repos : « Pomodoro · 25 min » lance un bloc sur le chapitre affiché ;
// - en cours : anneau + temps restant, clic = pause / reprise ;
// - pause proposée : « Pause · 5 min » lance la pause recommandée.
// Menu contextuel (clic droit) et menu ▾ : arrêter, passer, ouvrir le minuteur.

struct PomodoroQuickControl: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var controller: PomodoroAppController

    private var snap: PomodoroTimerSnapshot { controller.timerSnapshot }

    private var progress: Double {
        guard snap.totalDuration > 0 else { return 0 }
        return min(1, max(0, 1 - snap.remainingTime / snap.totalDuration))
    }

    private var tint: Color {
        switch snap.phase.activeMode ?? controller.pendingNextMode {
        case .focus?:      return .accent
        case .shortBreak?: return CockpitTheme.success
        case .longBreak?:  return CockpitTheme.glow
        case nil:          return .accent
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: primaryAction) {
                HStack(spacing: 6) {
                    leadingGlyph
                    Text(primaryLabel)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(isActive ? tint : .primary.opacity(0.85))
                .padding(.leading, 9).padding(.trailing, 7)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .disabled(controller.isExternalFocusActive)
            .help(primaryHelp)
            .accessibilityLabel(primaryHelp)
            .accessibilityValue(isActive ? "\(controller.formattedDuration(snap.remainingTime)) restantes" : "")

            Rectangle().fill(Color.cardBorder).frame(width: 1, height: 16)

            Menu {
                menuItems
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Plus d'options du minuteur")
            .accessibilityLabel("Options du minuteur")
        }
        .background(
            RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                .fill(isActive ? tint.opacity(0.09) : Color.glassFill)
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                    .stroke(isActive ? tint.opacity(0.28) : Color.cardBorder, lineWidth: 1))
        )
        .contextMenu { menuItems }
        .appAnimation(Motion.quick, value: isActive)
    }

    // MARK: Contenu

    private var isActive: Bool { snap.phase != .idle }

    @ViewBuilder private var leadingGlyph: some View {
        if isActive {
            ZStack {
                Circle().stroke(tint.opacity(0.22), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(0.001, progress))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .appAnimation(.linear(duration: 0.9), value: progress)
                Image(systemName: snap.phase.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 5.5, weight: .black))
            }
            .frame(width: 13, height: 13)
        } else if controller.pendingNextMode != nil && controller.pendingNextMode != .focus {
            Image(systemName: "cup.and.saucer.fill").font(.system(size: 11))
        } else {
            Image(systemName: "timer").font(.system(size: 11, weight: .medium))
        }
    }

    private var focusMinutes: Int { Int(controller.data.settings.focusDuration / 60) }

    private var primaryLabel: String {
        if isActive {
            let t = controller.formattedDuration(snap.remainingTime)
            return snap.phase.isPaused ? "\(t) · en pause" : t
        }
        if let next = controller.pendingNextMode, next != .focus {
            let d = next == .longBreak ? controller.data.settings.longBreakDuration : controller.data.settings.shortBreakDuration
            return "Pause · \(Int(d / 60)) min"
        }
        return "Pomodoro · \(focusMinutes) min"
    }

    private var primaryHelp: String { primaryHelpBase + " (⌃⌥P, depuis n'importe quelle app)" }

    private var primaryHelpBase: String {
        if controller.isExternalFocusActive { return "Une séance Sanctuaire est en cours" }
        if isActive { return snap.phase.isPaused ? "Reprendre le minuteur" : "Mettre le minuteur en pause" }
        if let next = controller.pendingNextMode, next != .focus { return "Lancer la pause proposée" }
        if let ch = store.activeChapter { return "Lancer un bloc de \(focusMinutes) min sur « \(ch.name) »" }
        return "Lancer un bloc de \(focusMinutes) min"
    }

    @ViewBuilder private var menuItems: some View {
        if isActive {
            Button(snap.phase.isPaused ? "Reprendre" : "Pause") { controller.pauseOrResume() }
            Button("Arrêter le bloc", role: .destructive) { controller.stopTimer() }
        } else {
            Button("Lancer un bloc de \(focusMinutes) min") { startFocus() }
                .disabled(!controller.canStartSession)
            if let next = controller.pendingNextMode, next != .focus {
                Button("Passer la pause") { controller.skipPendingPhase() }
            }
            Divider()
            Menu("Durée du bloc") {
                ForEach([25, 45, 50, 90], id: \.self) { m in
                    Button {
                        controller.data.settings.focusDuration = TimeInterval(m * 60)
                        controller.saveSettings()
                    } label: {
                        if m == focusMinutes { Label("\(m) min", systemImage: "checkmark") } else { Text("\(m) min") }
                    }
                }
            }
        }
        Divider()
        Button("Ouvrir le minuteur") {
            NotificationCenter.default.post(name: .navigateToTimer, object: nil)
        }
    }

    // MARK: Actions

    private func primaryAction() {
        if isActive {
            controller.pauseOrResume()
        } else if let next = controller.pendingNextMode, next != .focus {
            controller.startRecommendedSession()
        } else {
            startFocus()
        }
    }

    /// Le bloc est rattaché au chapitre affiché sur le tableau de bord.
    private func startFocus() {
        if let p = store.activeProject, let c = store.activeChapter {
            controller.selectedWritingProjectId = p.id
            controller.selectedWritingChapterId = c.id
        }
        controller.startFocusSession()
    }
}
