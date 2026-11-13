import SwiftUI

// MARK: - Mode "Aujourd'hui" plein écran (#8)

/// Vue d'accueil minimaliste : date, chapitre actif, prochaine action,
/// boutons de démarrage rapide. Idéal pour démarrer la journée sans
/// scanner le dashboard complet.
struct TodayModeView: View {
    @ObservedObject var store: DataStore
    let onDismiss: () -> Void
    let onStartFocus: () -> Void
    let onOpenDashboard: () -> Void

    private var chapter: Chapter? { store.activeChapter }
    private var project: Project? { store.activeProject }
    private var isRest: Bool { store.isRestDay(DataStore.today) }
    private var todayProgress: Int { store.dailyProgress }
    private var todayGoal: Int { store.effectiveDailyGoal }
    private var ratio: Double {
        guard todayGoal > 0 else { return 0 }
        return min(1.0, Double(todayProgress) / Double(todayGoal))
    }

    var body: some View {
        ZStack {
            // Fond
            Color.appBg
                .ignoresSafeArea()

            VStack(spacing: 32) {
                topBar
                Spacer(minLength: 0)
                heroBlock
                if !isRest { progressRing }
                actions
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 60).padding(.vertical, 32)
            .frame(maxWidth: 720, maxHeight: .infinity)
        }
        .transition(.opacity)
    }

    // MARK: -

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(longDateString)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.labelMuted)
                Text("Bonjour.")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.labelMuted.opacity(0.6))
            }
            .buttonStyle(.pressable)
            .help("Fermer (Esc)")
            .accessibilityLabel("Fermer (Esc)")
        }
    }

    private var heroBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let project, let chapter {
                Text(project.name.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.4)
                Text(chapter.name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                if let nextStep = chapter.nextStep?.trimmingCharacters(in: .whitespacesAndNewlines), !nextStep.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.accent)
                        Text(nextStep)
                            .font(.system(size: 17))
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("Pas de prochaine action définie.")
                        .font(.system(size: 13))
                        .foregroundColor(.labelMuted)
                }
            } else {
                Text("Aucun chapitre actif")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.labelMuted)
                Text("Ouvre le dashboard pour en sélectionner un.")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressRing: some View {
        HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.cardBorder, lineWidth: 8)
                    .frame(width: 90, height: 90)
                Circle()
                    .trim(from: 0, to: ratio)
                    .stroke(
                        LinearGradient(colors: [Color.accent.opacity(0.7), Color.accent],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(ratio * 100))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("%")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Objectif du jour")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.8)
                Text("\(todayProgress.formatted()) / \(todayGoal.formatted())")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                let streak = store.currentStreak
                if streak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.accentWarm)
                        Text("Série · \(streak) j")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accentWarm)
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isRest {
            HStack(spacing: 10) {
                Image(systemName: "moon.fill").font(.system(size: 14)).foregroundColor(.accentWarm)
                Text("Jour de repos planifié — pas d'objectif aujourd'hui.")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentWarm.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            HStack(spacing: 10) {
                Button {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onStartFocus()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Lancer une session")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(chapter == nil)

                Button {
                    onDismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        onOpenDashboard()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2")
                        Text("Ouvrir le dashboard")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.labelMuted)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.glassFill)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "keyboard")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text("Esc pour fermer · ⏎ pour démarrer")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted.opacity(0.5))
        }
    }

    private static let longFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private var longDateString: String {
        let s = Self.longFmt.string(from: Date())
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
