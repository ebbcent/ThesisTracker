import SwiftUI

// MARK: - Sprint d'écriture (V5 — amélioration #5)
// Overlay plein écran : minuteur compte-à-rebours + objectif de sprint.
// Raccourci : ⌘⇧T

struct WritingSprintView: View {
    @ObservedObject var store: DataStore
    let onClose: () -> Void

    // ── Réglages ─────────────────────────────────────────────────
    @State private var durationMinutes: Int = 25
    @State private var targetText: String = ""
    @FocusState private var targetFocused: Bool

    // ── État minuteur ─────────────────────────────────────────────
    enum SprintPhase { case setup, running, paused, finished }
    @State private var phase: SprintPhase = .setup
    @State private var secondsRemaining: Int = 0
    @State private var timerRef: Timer? = nil
    /// Fin prévue du sprint : le temps restant est recalculé à partir de cette date (pas de dérive)
    @State private var endDate: Date? = nil

    // ── Snapshot écriture ─────────────────────────────────────────
    @State private var startCount: Int = 0
    @State private var pulseAmount: CGFloat = 1.0

    private let presets = [10, 15, 25, 45]

    private var activeChapter: Chapter? { store.activeChapter }
    private var todayStr: String { DataStore.today }

    private var currentTotal: Int {
        activeChapter?.entryForDate(todayStr)?.totalCount ?? 0
    }
    private var sprintDelta: Int { max(0, currentTotal - startCount) }

    private var targetInt: Int? {
        Int(targetText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private var sprintProgress: Double {
        guard let t = targetInt, t > 0, phase != .setup else { return 0 }
        return min(1.0, Double(sprintDelta) / Double(t))
    }

    private var timerRatio: Double {
        let total = durationMinutes * 60
        guard total > 0, phase != .setup else { return 0 }
        return 1.0 - Double(secondsRemaining) / Double(total)
    }

    private var timeString: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    // ─────────────────────────────────────────────────────────────

    var body: some View {
        ZStack {
            Color.black.opacity(0.93).ignoresSafeArea()

            // Barre de progression du minuteur (haut de l'écran)
            VStack(spacing: 0) {
                if phase != .setup {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Color.white.opacity(0.06).frame(height: 3)
                            Color.accent.opacity(0.8)
                                .frame(width: geo.size.width * timerRatio, height: 3)
                                .animation(.linear(duration: 1), value: timerRatio)
                        }
                    }
                    .frame(height: 3)
                }
                Spacer()
            }

            // Contenu principal
            VStack(spacing: 0) {
                Spacer()
                Group {
                    switch phase {
                    case .setup:             setupView
                    case .running, .paused:  runningView
                    case .finished:          finishedView
                    }
                }
                Spacer()
            }

            // Bouton fermer
            VStack {
                HStack {
                    Spacer()
                    Button(action: { stopTimer(); onClose() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    .keyboardShortcut(.escape, modifiers: [])
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { targetFocused = true }
        }
        .onDisappear { stopTimer() }
    }

    // ── Vue de configuration ──────────────────────────────────────

    private var setupView: some View {
        VStack(spacing: 40) {

            // Titre
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.accent)
                    Text("Sprint d'écriture")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text("Un objectif court. Un effort intense.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Sélecteur de durée
            VStack(spacing: 12) {
                Text("DURÉE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                HStack(spacing: 10) {
                    ForEach(presets, id: \.self) { min in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { durationMinutes = min }
                        } label: {
                            Text("\(min) min")
                                .font(.system(size: 13,
                                             weight: durationMinutes == min ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundColor(durationMinutes == min ? .black : .white.opacity(0.6))
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(durationMinutes == min
                                              ? Color.accent
                                              : Color.white.opacity(0.08))
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: durationMinutes)
                    }
                }
            }

            // Objectif de sprint (optionnel)
            VStack(spacing: 12) {
                Text("OBJECTIF DE SPRINT (optionnel)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                HStack(spacing: 8) {
                    Image(systemName: "textformat.123")
                        .foregroundColor(.white.opacity(0.35))
                        .font(.system(size: 14))
                    TextField("ex. 300", text: $targetText)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .textFieldStyle(.plain)
                        .frame(width: 80)
                        .focused($targetFocused)
                        .onSubmit { startSprint() }
                    Text(store.data.useWordCount ? "mots" : "car.")
                        .foregroundColor(.white.opacity(0.35))
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(targetFocused ? Color.accent.opacity(0.5) : Color.white.opacity(0.12),
                                lineWidth: 1)
                )
            }

            // Bouton démarrer
            Button(action: startSprint) {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(size: 13))
                    Text("Démarrer le sprint")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 32).padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [.accent, .accentWarm],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing))
                )
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 48)
    }

    // ── Vue en cours / pause ──────────────────────────────────────

    private var runningView: some View {
        let isPaused = (phase == .paused)
        return VStack(spacing: 36) {

            // Chapitre actif
            if let ch = activeChapter {
                Text(ch.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.35))
            }

            // Grand minuteur
            VStack(spacing: 4) {
                Text(timeString)
                    .font(.system(size: 80, weight: .bold, design: .monospaced))
                    .foregroundColor(isPaused ? .white.opacity(0.3) : .white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: secondsRemaining)
                Text(isPaused ? "En pause" : "\(durationMinutes) min")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
            }
            .scaleEffect(pulseAmount)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pulseAmount)

            // Delta écrit pendant le sprint
            VStack(spacing: 10) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("+\(DataStore.formatNumber(sprintDelta))")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundColor(sprintDelta > 0 ? .accentGreen : .white.opacity(0.3))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4), value: sprintDelta)
                    Text(store.data.useWordCount ? "mots" : "car.")
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.bottom, 6)
                }

                if let target = targetInt, target > 0 {
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.08)).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(sprintProgress >= 1 ? Color.accentGreen : Color.accent)
                                    .frame(width: max(0, geo.size.width * sprintProgress), height: 4)
                                    .animation(.spring(response: 0.5), value: sprintProgress)
                            }
                        }
                        .frame(width: 280, height: 4)
                        Text("Objectif sprint : \(Int(sprintProgress * 100))% · \(DataStore.formatNumber(target)) \(store.data.useWordCount ? "mots" : "car.")")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            // Contrôles Pause / Terminer
            HStack(spacing: 12) {
                Button(action: isPaused ? resumeTimer : pauseTimer) {
                    HStack(spacing: 6) {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 13))
                        Text(isPaused ? "Reprendre" : "Pause")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [.accent, .accentWarm],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: endSprint) {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill").font(.system(size: 12))
                        Text("Terminer")
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 48)
    }

    // ── Vue résultat ──────────────────────────────────────────────

    private var finishedView: some View {
        let goalReached = targetInt.map { sprintDelta >= $0 } ?? false
        return VStack(spacing: 32) {

            VStack(spacing: 12) {
                Image(systemName: goalReached ? "star.fill" : "checkmark.circle.fill")
                    .font(.system(size: 52))
                    .foregroundColor(goalReached ? .yellow : .accentGreen)
                Text(goalReached ? "Objectif atteint !" : "Sprint terminé !")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                HStack(spacing: 4) {
                    Text("+\(DataStore.formatNumber(sprintDelta))")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.accentGreen)
                    Text("\(store.data.useWordCount ? "mots" : "caractères") en \(durationMinutes) min")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.45))
                }
            }

            HStack(spacing: 12) {
                Button(action: resetForNewSprint) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                        Text("Nouveau sprint")
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(colors: [.accent, .accentWarm],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)

                Button(action: onClose) {
                    Text("Fermer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 48)
    }

    // ── Logique minuteur ──────────────────────────────────────────

    private func startSprint() {
        startCount = currentTotal
        secondsRemaining = durationMinutes * 60
        endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        phase = .running
        fireTimer()
    }

    private func fireTimer() {
        timerRef?.invalidate()
        // Mode .common : le décompte continue pendant le suivi d'un menu / d'un défilement
        let timer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                updateRemaining()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timerRef = timer
    }

    /// Recalcule le temps restant depuis la date de fin (robuste aux retards du timer et à la veille)
    private func updateRemaining() {
        guard phase == .running, let endDate else { return }
        let remaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        if remaining != secondsRemaining {
            secondsRemaining = remaining
            // Légère pulsation toutes les 5 minutes
            if remaining > 0 && remaining % 300 == 0 {
                pulseAmount = 1.04
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pulseAmount = 1.0 }
            }
        }
        if remaining <= 0 {
            secondsRemaining = 0
            endSprint()
        }
    }

    private func pauseTimer() {
        if let endDate {
            secondsRemaining = max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
        }
        endDate = nil
        timerRef?.invalidate()
        timerRef = nil
        phase = .paused
    }
    private func resumeTimer() {
        endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
        phase = .running
        fireTimer()
    }
    private func stopTimer()       { timerRef?.invalidate(); timerRef = nil }
    private func endSprint()       { stopTimer(); endDate = nil; withAnimation { phase = .finished } }
    private func resetForNewSprint() { phase = .setup; secondsRemaining = 0; startCount = 0; endDate = nil }
}
