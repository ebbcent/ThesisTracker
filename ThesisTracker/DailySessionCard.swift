import SwiftUI

// MARK: - V3.3 · Boucle quotidienne structurée
// Fichier isolé — ne modifie aucun composant existant.
// Insertion dans DashboardView (colonne droite, au-dessus de progressSection).

// ─────────────────────────────────────────────
// MARK: - DailySessionCard
// ─────────────────────────────────────────────

struct DailySessionCard: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoroController: PomodoroAppController

    // #44 — objectif sessions Pomodoro par semaine
    @AppStorage("weeklyPomodoroGoal") private var weeklyPomodoroGoal: Int = 5

    /// Empêche le toast de se déclencher plusieurs fois dans la même journée
    @AppStorage("v33_goalReachedDate") private var goalReachedDate: String = ""
    @State private var showGoalReached = false

    // ── Données calculées ──────────────────────

    private var smartGoal: Int   { store.todaySmartGoal }
    private var progress: Int    { store.dailyProgress }
    private var catchUp: Int     { store.catchUpAmount }
    private var missedYesterday: Bool { store.yesterdayProgress == 0 && store.data.dailyGoal > 0 }

    private var ratio: Double {
        guard smartGoal > 0 else { return 0 }
        return min(1.0, Double(progress) / Double(smartGoal))
    }

    // #44 — sessions focus terminées cette semaine
    private var weeklyFocusSessions: Int {
        let cal = Calendar(identifier: .gregorian)
        var calMon = cal; calMon.firstWeekday = 2
        let now = Date()
        guard let weekStart = calMon.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        return pomodoroController.data.sessions.filter {
            $0.kind == .focus &&
            $0.completionState == .completed &&
            $0.startedAt >= weekStart
        }.count
    }

    private var isGoalReached: Bool { smartGoal > 0 && progress >= smartGoal }
    private var hasCatchUp: Bool    { catchUp > 0 && missedYesterday }

    // ── Messages contextuels ───────────────────

    private var statusMessage: String {
        guard smartGoal > 0 else {
            if store.isTodayPlannedOff { return "Jour sans écriture prévue — pas d'objectif." }
            return "Définis un objectif journalier dans les réglages."
        }
        if isGoalReached  { return "Objectif atteint — excellente session !" }
        if progress == 0 && hasCatchUp { return "Tu n'as pas écrit hier. Un petit rattrapage aujourd'hui ?" }
        if progress == 0  { return "Prêt à écrire ? Lance ta session !" }
        let left = smartGoal - progress
        return "Plus que \(store.formatCount(left)) pour atteindre l'objectif."
    }

    private var statusColor: Color {
        if isGoalReached           { return .accentGreen }
        if hasCatchUp && progress == 0 { return .accentWarm }
        return .accent
    }

    // ── Body ──────────────────────────────────

    var body: some View {
        VStack(spacing: 10) {
            SectionHeader("Session du jour")
            GlassCard {
                VStack(spacing: 14) {
                    topRow
                    if smartGoal > 0 { progressBar }
                    bottomRow
                    // #44 — sessions Pomodoro de la semaine
                    if weeklyPomodoroGoal > 0 {
                        Divider()
                        weeklySessionsRow
                    }
                }
            }
        }
        // Toast unique par jour
        .onChange(of: isGoalReached) { reached in
            guard reached, goalReachedDate != DataStore.today else { return }
            goalReachedDate = DataStore.today
            withAppAnimation(Motion.celebrate) {
                showGoalReached = true
            }
        }
        .overlay(alignment: .top) {
            if showGoalReached {
                GoalReachedToast()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                            withAppAnimation(Motion.quick) { showGoalReached = false }
                        }
                    }
            }
        }
    }

    // ── Sous-vues ─────────────────────────────

    private var topRow: some View {
        HStack(alignment: .center, spacing: 12) {
            // Chiffres gauche
            VStack(alignment: .leading, spacing: 3) {
                Text("AUJOURD'HUI")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1)

                if smartGoal > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(store.formatCount(progress))
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(isGoalReached ? .accentGreen : .primary)
                            .contentTransition(.numericText())
                            .appAnimation(Motion.progress, value: progress)

                        Text("/ \(store.formatCount(smartGoal))")
                            .font(.system(size: 13))
                            .foregroundColor(.labelMuted)
                    }
                } else {
                    Text("—")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.labelMuted)
                }

                // Badge de rattrapage
                if hasCatchUp && !isGoalReached {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("+\(store.formatCount(catchUp)) rattrapage")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.accentWarm)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.accentWarm.opacity(0.10))
                    .clipShape(Capsule())
                }
            }

            Spacer(minLength: 8)

            // Indicateur circulaire (ou checkmark si terminé)
            if isGoalReached {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.accentGreen)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            } else if smartGoal > 0 {
                SessionRingView(ratio: ratio, color: statusColor)
                    .frame(width: 48, height: 48)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(statusColor.opacity(0.12))
                    .frame(height: 7)

                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [statusColor.opacity(0.75), statusColor],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * ratio), height: 7)
                    .appAnimation(Motion.progress, value: ratio)
            }
        }
        .frame(height: 7)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Image(systemName: isGoalReached
                  ? "checkmark.circle.fill"
                  : (hasCatchUp && progress == 0 ? "arrow.uturn.right.circle.fill" : "pencil.circle.fill"))
                .font(.system(size: 10))
                .foregroundColor(statusColor)

            Text(statusMessage)
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // #44 — indicateur sessions Pomodoro cette semaine
    private var weeklySessionsRow: some View {
        let count = weeklyFocusSessions
        let goal = weeklyPomodoroGoal
        let done = count >= goal
        let ratio = goal > 0 ? min(1.0, Double(count) / Double(goal)) : 0.0
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: done ? "timer.badge.checkmark" : "timer")
                    .font(.system(size: 10))
                    .foregroundColor(done ? .accentGreen : .labelMuted.opacity(0.7))
                Text("Sessions cette semaine")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                Spacer()
                Text("\(count) / \(goal)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(done ? .accentGreen : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done ? Color.accentGreen.opacity(0.12) : Color.primary.opacity(0.07))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done ? Color.accentGreen : Color.accent.opacity(0.7))
                        .frame(width: geo.size.width * ratio, height: 4)
                        .appAnimation(Motion.progress, value: ratio)
                }
            }
            .frame(height: 4)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - SessionRingView
// Anneau de progression circulaire minimaliste
// ─────────────────────────────────────────────

struct SessionRingView: View {
    let ratio: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 5)

            Circle()
                .trim(from: 0, to: ratio)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .appAnimation(Motion.progress, value: ratio)

            Text("\(Int(ratio * 100))%")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
        }
    }
}

// ─────────────────────────────────────────────
// MARK: - GoalReachedToast
// Affiché une seule fois par jour (piloté par AppStorage)
// ─────────────────────────────────────────────

struct GoalReachedToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("🎉")
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text("Objectif du jour atteint !")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Continue sur ta lancée.")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.glassFill)
                .overlay(Capsule().stroke(Color.accentGreen.opacity(0.4), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
        .padding(.top, 8)
    }
}
