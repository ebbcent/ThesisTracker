import SwiftUI

// MARK: - Intention et bilan de concentration des sessions (5.11)

enum FocusQualityLevel: Int, CaseIterable {
    case distracted = 1
    case neutral = 2
    case focused = 3

    var label: String {
        switch self {
        case .distracted: return "Distrait"
        case .neutral:    return "Neutre"
        case .focused:    return "Concentré"
        }
    }

    var icon: String {
        switch self {
        case .distracted: return "cloud.drizzle"
        case .neutral:    return "cloud.sun"
        case .focused:    return "sun.max.fill"
        }
    }

    var color: Color {
        switch self {
        case .distracted: return Color(red: 0.929, green: 0.329, blue: 0.329)
        case .neutral:    return .accentWarm
        case .focused:    return .accentGreen
        }
    }
}

struct FocusQualityWeek: Identifiable, Equatable {
    let weekStart: Date
    var distracted = 0
    var neutral = 0
    var focused = 0

    var id: Date { weekStart }
    var total: Int { distracted + neutral + focused }

    func count(_ level: FocusQualityLevel) -> Int {
        switch level {
        case .distracted: return distracted
        case .neutral:    return neutral
        case .focused:    return focused
        }
    }
}

enum FocusQualityStats {
    static var isoCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    /// Répartition des bilans par semaine (lundi → dimanche), de la plus ancienne à la courante.
    static func weekly(sessions: [PomodoroSessionRecord], weeks: Int = 4, now: Date = .now) -> [FocusQualityWeek] {
        let cal = isoCalendar
        guard weeks > 0, let currentStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var result: [FocusQualityWeek] = (0..<weeks).reversed().compactMap { offset in
            cal.date(byAdding: .weekOfYear, value: -offset, to: currentStart).map { FocusQualityWeek(weekStart: $0) }
        }
        for session in sessions where session.kind == .focus {
            guard let quality = session.focusQuality.flatMap(FocusQualityLevel.init(rawValue:)),
                  let start = cal.dateInterval(of: .weekOfYear, for: session.startedAt)?.start,
                  let index = result.firstIndex(where: { $0.weekStart == start }) else { continue }
            switch quality {
            case .distracted: result[index].distracted += 1
            case .neutral:    result[index].neutral += 1
            case .focused:    result[index].focused += 1
            }
        }
        return result
    }

    /// Dernières intentions distinctes, de la plus récente à la plus ancienne.
    static func recentIntentions(sessions: [PomodoroSessionRecord], limit: Int = 5) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            guard let text = session.intention?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            result.append(text)
            if result.count == limit { break }
        }
        return result
    }
}

/// Champ « Intention » au-dessus des boutons du minuteur.
struct PomodoroIntentionField: View {
    @EnvironmentObject private var controller: PomodoroAppController

    private var isRunningFocus: Bool {
        controller.timerSnapshot.phase.activeMode == .focus
    }

    var body: some View {
        if isRunningFocus, let intention = controller.activeIntention {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .foregroundColor(.accent)
                Text(intention)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundColor(.labelMuted)
                TextField("Intention de la session (facultatif)", text: $controller.intentionDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                let recents = FocusQualityStats.recentIntentions(sessions: controller.data.sessions)
                if !recents.isEmpty {
                    Menu {
                        ForEach(recents, id: \.self) { text in
                            Button(text) { controller.intentionDraft = text }
                        }
                        Divider()
                        Button("Effacer") { controller.intentionDraft = "" }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Intentions récentes")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }
}

/// Trois boutons dans la feuille de fin de session.
struct FocusQualityPicker: View {
    @Binding var quality: Int?

    var body: some View {
        HStack(spacing: 8) {
            Text("Concentration")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(FocusQualityLevel.allCases, id: \.rawValue) { level in
                let selected = quality == level.rawValue
                Button {
                    quality = selected ? nil : level.rawValue
                } label: {
                    Label(level.label, systemImage: level.icon)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                        .foregroundColor(selected ? .white : level.color)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(selected ? level.color : level.color.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Statistiques du minuteur : bilans des 4 dernières semaines.
struct FocusQualityCard: View {
    @EnvironmentObject private var controller: PomodoroAppController

    private static let weekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM"
        return f
    }()

    var body: some View {
        let weeks = FocusQualityStats.weekly(sessions: controller.data.sessions)
        InfoCard(title: "Qualité de concentration — 4 semaines", systemImage: "sun.max") {
            if weeks.allSatisfy({ $0.total == 0 }) {
                Text("Note ta concentration à la fin d'une session pour voir apparaître ce bilan.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(weeks) { week in
                        HStack(spacing: 10) {
                            Text("Sem. du \(Self.weekFormatter.string(from: week.weekStart))")
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            GeometryReader { geo in
                                HStack(spacing: 2) {
                                    ForEach(FocusQualityLevel.allCases, id: \.rawValue) { level in
                                        let count = week.count(level)
                                        if count > 0 {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(level.color.opacity(0.85))
                                                .frame(width: max(4, geo.size.width * CGFloat(count) / CGFloat(max(week.total, 1)) - 2))
                                                .help("\(level.label) : \(count)")
                                        }
                                    }
                                }
                            }
                            .frame(height: 12)
                            Text("\(week.total)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .frame(width: 24, alignment: .trailing)
                        }
                    }
                    HStack(spacing: 14) {
                        ForEach(FocusQualityLevel.allCases, id: \.rawValue) { level in
                            HStack(spacing: 4) {
                                Circle().fill(level.color).frame(width: 7, height: 7)
                                Text(level.label).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
