import SwiftUI

// MARK: - Feature #70 : Défi mensuel

struct MonthlyChallengeCard: View {
    @ObservedObject var store: DataStore
    @State private var animatedRatio: Double = 0

    private var goal:     Int    { store.data.monthlyGoal }
    private var progress: Int    { store.currentCalendarMonthProgress }
    private var ratio:    Double { goal > 0 ? min(1.0, Double(progress) / Double(goal)) : 0 }
    private var pct:      Int    { Int(ratio * 100) }

    private var activeDays:    Int { store.activeDaysThisMonth }
    private var daysRemaining: Int { store.daysRemainingInMonth }

    private var ringColor: Color {
        if ratio >= 1.0 { return .accentGreen }
        if ratio >= 0.6 { return Color(hex: "#F5C518") }
        return Color.accent
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {

                // Header
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(ringColor.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: ratio >= 1.0 ? "trophy.fill" : "calendar.badge.clock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(ringColor)
                    }
                    Text("Défi du mois")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(monthLabel)
                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                        .foregroundColor(ringColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(ringColor.opacity(0.10))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(ringColor.opacity(0.25), lineWidth: 1))
                }

                // Anneau + stats
                HStack(spacing: 16) {
                    gaugeRing
                    VStack(alignment: .leading, spacing: 6) {
                        Text(ratio >= 1.0 ? "Objectif atteint ! 🎉" : progressLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        statLine(icon: "pencil.and.outline",
                                 text: "\(activeDays) jour\(activeDays > 1 ? "s" : "") d'écriture")
                        statLine(icon: "hourglass",
                                 text: daysRemaining > 0
                                       ? "\(daysRemaining) jour\(daysRemaining > 1 ? "s" : "") restant\(daysRemaining > 1 ? "s" : "")"
                                       : "Dernier jour !")
                        if goal > 0 && ratio < 1.0 {
                            let remaining = goal - progress
                            statLine(icon: "textformat.abc",
                                     text: "\(DataStore.formatNumber(remaining)) signes restants")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Barre de progression
                progressBar
            }
        }
        .onAppear {
            withAppAnimation(Motion.progress.delay(0.1)) {
                animatedRatio = ratio
            }
        }
        .onChange(of: ratio) { _, newRatio in
            withAppAnimation(.easeOut(duration: 0.5)) {
                animatedRatio = newRatio
            }
        }
    }

    // MARK: - Sub-views

    private var gaugeRing: some View {
        ZStack {
            Circle()
                .stroke(Color.cardBorder, lineWidth: 6)
                .frame(width: 62, height: 62)
            Circle()
                .trim(from: 0, to: animatedRatio)
                .stroke(
                    LinearGradient(colors: [ringColor.opacity(0.7), ringColor],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(pct)")
                    .font(.system(size: 17, weight: .bold, design: AppLook.fontDesign))
                    .foregroundColor(.primary)
                Text("%")
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.cardBorder)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [ringColor.opacity(0.7), ringColor],
                                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * animatedRatio, height: 6)
            }
        }
        .frame(height: 6)
    }

    private func statLine(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted.opacity(0.6))
                .frame(width: 12)
            Text(text)
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
        }
    }

    // MARK: - Helpers

    private var progressLabel: String {
        guard goal > 0 else { return "Aucun objectif mensuel défini" }
        return "\(DataStore.formatNumber(progress)) / \(DataStore.formatNumber(goal)) signes"
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()
    private var monthLabel: String {
        Self.monthFormatter.string(from: Date()).capitalized
    }
}
