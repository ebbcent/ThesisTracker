import SwiftUI

// MARK: - V3.4 · Stats enrichies pour OverviewView
// Fichier isolé — 3 cartes indépendantes insérées après thesisPipeline.

// ─────────────────────────────────────────────────────────
// MARK: - ThesisProjectionCard
// ─────────────────────────────────────────────────────────

struct ThesisProjectionCard: View {
    @ObservedObject var store: DataStore

    private var remaining: Int   { store.thesisRemainingChars }
    private var velocity: Int    { store.velocity14Days }
    private var days: Int?       { store.thesisProjectedDays }

    private var chaptersWithoutGoal: Int {
        store.data.projects.flatMap { $0.chapters }
            .filter { !$0.isCompleted && $0.goal == 0 && $0.countsInThesisTotal }.count
    }

    private var chaptersExcluded: Int {
        store.data.projects.flatMap { $0.chapters }.filter { !$0.countsInThesisTotal }.count
    }

    private var projectedDate: String? {
        guard let d = days, d > 0 else { return nil }
        guard let target = Calendar(identifier: .gregorian)
                .date(byAdding: .day, value: d, to: Date()) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: target).capitalized
    }

    private var statusColor: Color {
        guard let d = days, d > 0 else { return .accentGreen }
        if d < 90  { return .accentGreen }
        if d < 365 { return .accentWarm }
        return Color.semRed
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {

                // ── Header ──────────────────────────
                HStack(spacing: 0) {
                    Label("Projection finale", systemImage: "flag.checkered")
                        .font(.system(size: 13, weight: .semibold, design: AppLook.fontDesign))
                        .foregroundColor(.primary)
                    Spacer()
                    if velocity > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.accent)
                            Text(store.formatCountShort(velocity) + "/j · 14j")
                                .font(.system(size: AppLook.fs(11), weight: .medium))
                                .foregroundColor(.accent)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accent.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }

                Divider()

                // ── Stats ────────────────────────────
                HStack(alignment: .top, spacing: 0) {

                    if remaining <= 0 {
                        projStat(label: "Restant", value: "✓",
                                 subtitle: "Tous les objectifs\natteints", color: .accentGreen)
                    } else {
                        projStat(label: "Restant",
                                 value: store.formatCountShort(remaining),
                                 subtitle: store.pagesLabel(remaining).map { "à écrire · \($0)" } ?? "à écrire",
                                 color: .primary)
                    }

                    if let d = days, remaining > 0 {
                        statDivider()
                        projStat(label: "Durée estimée",
                                 value: formatDays(d),
                                 subtitle: "à ce rythme", color: statusColor)

                        if let dateStr = projectedDate {
                            statDivider()
                            projStat(label: "Fin prévue",
                                     value: dateStr,
                                     subtitle: "projection", color: statusColor)
                        }
                    } else if velocity == 0 && remaining > 0 {
                        statDivider()
                        projStat(label: "Projection", value: "—",
                                 subtitle: "Pas encore assez\nde données", color: .labelMuted)
                    }

                    Spacer(minLength: 0)
                }

                if chaptersExcluded > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "tray.full")
                            .font(.system(size: AppLook.fs(10)))
                            .foregroundColor(.labelMuted)
                        Text("\(chaptersExcluded) chapitre(s) hors total (annexes…) non compté(s) ici.")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // ── Avertissement chapitres sans objectif ──
                if chaptersWithoutGoal > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: AppLook.fs(10)))
                            .foregroundColor(.labelMuted)
                        Text("\(chaptersWithoutGoal) chapitre(s) sans objectif — projection partielle.")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func projStat(label: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
            Text(value)
                .font(TypeScale.pageTitle)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(subtitle)
                .font(.system(size: AppLook.fs(10)))
                .foregroundColor(.labelMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 8)
    }

    private func statDivider() -> some View {
        Divider().frame(height: 48).padding(.horizontal, 8)
    }

    private func formatDays(_ d: Int) -> String {
        if d < 7   { return "\(d) j" }
        if d < 30  { return "\(d / 7) sem." }
        if d < 365 { return "\(d / 30) mois" }
        return String(format: "%.1f an(s)", Double(d) / 365)
    }
}

// ─────────────────────────────────────────────────────────
// MARK: - MonthlyMiniChart
// Tous les mois — scroll horizontal (style Netflix)
// ─────────────────────────────────────────────────────────

struct MonthlyMiniChart: View {
    @ObservedObject var store: DataStore

    private let barWidth:   CGFloat = 54
    private let barMaxH:    CGFloat = 72
    private let spacing:    CGFloat = 8

    private var data:   [(label: String, chars: Int)] { store.allMonthlyStats }
    private var maxVal: Int { max(1, data.map { $0.chars }.max() ?? 1) }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {

                // Header
                HStack {
                    Label("Tendance mensuelle", systemImage: "chart.bar.fill")
                        .font(.system(size: 13, weight: .semibold, design: AppLook.fontDesign))
                        .foregroundColor(.primary)
                    Spacer()
                    if data.count > 1 {
                        HStack(spacing: 4) {
                            Image(systemName: "hand.point.left")
                                .font(.system(size: AppLook.fs(10)))
                            Text("Faire défiler")
                                .font(.system(size: AppLook.fs(10)))
                        }
                        .foregroundColor(.labelMuted)
                    }
                }

                if data.isEmpty || data.allSatisfy({ $0.chars == 0 }) {
                    Text("Commence à écrire pour voir l'évolution mensuelle.")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                        .padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: spacing) {
                            ForEach(data.indices, id: \.self) { idx in
                                let item    = data[idx]
                                let isLast  = idx == data.indices.last
                                let ratio   = CGFloat(item.chars) / CGFloat(maxVal)
                                let barH    = max(4, barMaxH * ratio)

                                VStack(spacing: 4) {
                                    // Valeur
                                    Group {
                                        if item.chars > 0 {
                                            Text(store.formatCountShort(item.chars))
                                                .font(.system(size: AppLook.fs(10), weight: .semibold))
                                                .foregroundColor(isLast ? .accent : .labelMuted)
                                        } else {
                                            Text("—")
                                                .font(.system(size: AppLook.fs(10)))
                                                .foregroundColor(.labelMuted.opacity(0.5))
                                        }
                                    }
                                    .frame(height: 11)

                                    // Espace vide au-dessus
                                    Spacer(minLength: 0)
                                        .frame(height: barMaxH - barH)

                                    // Barre
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(
                                            isLast
                                            ? Color.accent
                                            : (item.chars > 0
                                               ? Color.accent.opacity(0.32)
                                               : Color.primary.opacity(0.06))
                                        )
                                        .frame(width: barWidth, height: barH)

                                    // Label mois
                                    Text(item.label)
                                        .font(.system(size: AppLook.fs(10), weight: isLast ? .semibold : .regular))
                                        .foregroundColor(isLast ? .accent : .labelMuted)
                                        .lineLimit(1)
                                        .frame(width: barWidth)
                                }
                            }
                        }
                        .padding(.bottom, 2)
                    }
                    .frame(height: barMaxH + 11 + 4 + 14 + 4) // valeur + spacer + barre + label
                }
            }
        }
    }
}

// ─────────────────────────────────────────────────────────
// MARK: - WeekdayChart
// Productivité moyenne par jour de semaine (Lun–Dim)
// ─────────────────────────────────────────────────────────

struct WeekdayChart: View {
    @ObservedObject var store: DataStore

    private var data: [(day: String, avg: Int)] { store.weekdayAverages }
    private var maxAvg: Int { max(1, data.map { $0.avg }.max() ?? 1) }
    private var bestIdx: Int {
        data.enumerated()
            .filter { $0.element.avg > 0 }
            .max(by: { $0.element.avg < $1.element.avg })?.offset ?? -1
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Productivité par jour", systemImage: "chart.bar.xaxis.ascending")
                        .font(.system(size: 13, weight: .semibold, design: AppLook.fontDesign))
                        .foregroundColor(.primary)
                    Spacer()
                    // Badge meilleur jour
                    if bestIdx >= 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.accentWarm)
                            Text(data[bestIdx].day)
                                .font(.system(size: AppLook.fs(11), weight: .semibold))
                                .foregroundColor(.accentWarm)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accentWarm.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }

                if data.allSatisfy({ $0.avg == 0 }) {
                    Text("Écris quelques jours pour voir tes tendances.")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        HStack(alignment: .bottom, spacing: 6) {
                            ForEach(data.indices, id: \.self) { idx in
                                let item   = data[idx]
                                let isBest = idx == bestIdx
                                let ratio  = CGFloat(item.avg) / CGFloat(maxAvg)

                                VStack(spacing: 4) {
                                    GeometryReader { geo in
                                        VStack(spacing: 0) {
                                            Spacer()
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(isBest
                                                      ? Color.accentWarm
                                                      : Color.accent.opacity(0.28))
                                                .frame(height: max(4, geo.size.height * ratio))
                                        }
                                    }

                                    Text(item.day)
                                        .font(.system(size: AppLook.fs(10), weight: isBest ? .bold : .regular))
                                        .foregroundColor(isBest ? .accentWarm : .labelMuted)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 64)

                        HStack {
                            Spacer()
                            Text("moyenne · toute la période · jours actifs seulement")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.labelMuted)
                        }
                    }
                }
            }
        }
    }
}
