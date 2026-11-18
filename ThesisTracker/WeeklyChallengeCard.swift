import SwiftUI

// MARK: - Weekly Challenge Card (Dashboard widget)

struct WeeklyChallengeCard: View {
    @ObservedObject var store: DataStore

    private var challenge: WeeklyChallenge? { store.currentWeekChallenge }
    private var progress: Int { challenge.map { store.challengeProgress($0) } ?? 0 }
    private var ratio: Double {
        guard let c = challenge, c.target > 0 else { return 0 }
        return min(1.0, Double(progress) / Double(c.target))
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(challengeColor.opacity(0.15))
                            .frame(width: 30, height: 30)
                        Image(systemName: challenge?.kind.icon ?? "target")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(challengeColor)
                    }
                    Text("Défi de la semaine")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    if let c = challenge, c.isCompleted {
                        Label("Relevé", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.semGreen)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.semGreen.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if let c = challenge {
                    // Description
                    Text(challengeDescription(c))
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)

                    // Progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(progress) / \(c.target) \(c.kind.unit)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(Int(ratio * 100))%")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(challengeColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(challengeColor.opacity(0.15))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(
                                        LinearGradient(
                                            colors: [challengeColor.opacity(0.8), challengeColor],
                                            startPoint: .leading, endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * ratio, height: 6)
                                    .appAnimation(Motion.progress, value: ratio)
                            }
                        }
                        .frame(height: 6)
                    }

                    // Week range
                    Text(weekRangeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted.opacity(0.7))
                } else {
                    Text("Aucun défi cette semaine")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                    Text("Lance une session d'écriture pour générer ton défi.")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted.opacity(0.7))
                }
            }
        }
    }

    // MARK: - Helpers

    private var challengeColor: Color {
        guard let c = challenge else { return .accent }
        if c.isCompleted { return Color.semGreen }
        switch c.kind {
        case .words:             return .accent
        case .streak:            return Color.semOrange
        case .sessions:          return Color.semSky
        case .daysWritten:       return Color.semViolet
        case .chapterCompletion: return .accentGreen
        case .chaptersAdvanced:  return Color.semSky
        }
    }

    private func challengeDescription(_ c: WeeklyChallenge) -> String {
        switch c.kind {
        case .words:
            return "Écrire \(store.formatCount(c.target)) caractères cette semaine"
        case .streak:
            return "Atteindre une série de \(c.target) jours consécutifs"
        case .sessions:
            return "Compléter \(c.target) sessions Pomodoro cette semaine"
        case .daysWritten:
            return "Écrire sur \(c.target) jours différents cette semaine"
        case .chapterCompletion:
            return "Terminer \(c.target) chapitre\(c.target > 1 ? "s" : "") cette semaine"
        case .chaptersAdvanced:
            return "Faire avancer \(c.target) chapitre\(c.target > 1 ? "s" : "") cette semaine"
        }
    }

    private static let weekRangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()
    private var weekRangeLabel: String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return "" }
        let end = cal.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
        return "\(Self.weekRangeFormatter.string(from: interval.start)) – \(Self.weekRangeFormatter.string(from: end))"
    }
}
