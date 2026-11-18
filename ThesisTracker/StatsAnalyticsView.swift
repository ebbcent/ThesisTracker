import SwiftUI
import Charts

// MARK: - Statistiques & Analyse (#8–#14)
// Vue dédiée accessible depuis la nav (⌘ ou sidebar).
// Contient : Momentum 30j, Top 10, Semaine vs semaine,
//            Heure de pic, Prévision confiance, Distribution projets, Jours sans écriture.

// MARK: - #55 Chart zoom support

private enum ZoomedChart: String, Identifiable {
    case momentum        = "Momentum 30 jours"
    case weekComparison  = "Semaine en cours vs précédente"
    case consistency     = "Taux de consistance"
    case acceleration    = "Courbe d'accélération"
    case chapterCompar   = "Comparatif chapitres"
    case monthReview     = "Mois en revue"
    case rollingVelocity = "Vélocité glissante · 14j"
    case hourHeatmap     = "Heatmap horaire d'écriture"
    var id: String { rawValue }
}

struct StatsAnalyticsView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    // #55 — Zoom état
    @State private var zoomedChart: ZoomedChart? = nil

    // #56 — Tooltips riches
    @State private var momentumHover:     Date?   = nil
    @State private var velocityHoverStr:  String? = nil

    private let projectPalette: [Color] = [
        .accent, .accentGreen, .accentWarm,
        Color.semViolet,
        Color(red: 0.294, green: 0.686, blue: 0.961),
        Color(red: 0.961, green: 0.365, blue: 0.482)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── En-tête ──────────────────────────────────────
                HStack(spacing: 12) {
                    Button {
                        withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showSidebar ? .accentWarm : .labelMuted)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                    .fill(showSidebar ? Color.accentWarm.opacity(0.09) : Color.glassFill)
                                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                        .stroke(showSidebar ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.pressable)
                    .help("Afficher ou masquer la barre latérale")
                    .accessibilityLabel("Afficher ou masquer la barre latérale")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Statistiques & Analyse")
                            .font(TypeScale.pageTitle)
                            .foregroundColor(.primary)
                        Text("Patterns, tendances et prévisions d'écriture")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                }

                let hasData = store.dailyTotals().values.contains { $0 > 0 }

                if !hasData {
                    GlassCard {
                        EmptyStateView(
                            icon: "chart.bar.doc.horizontal",
                            title: "Pas encore de données",
                            message: "Les statistiques apparaîtront dès ta première session d'écriture."
                        )
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        // Colonne gauche
                        VStack(spacing: 16) {
                            momentumSection
                            weekComparisonSection
                            projectDistributionSection
                            // #26 — Projection de soutenance
                            defenseProjectionSection
                            // #31 — Vélocité glissante 14j
                            rollingVelocitySection
                        }
                        .frame(maxWidth: .infinity)

                        // Colonne droite
                        VStack(spacing: 16) {
                            top10Section
                            peakHourSection
                            projectionConfidenceSection
                            daysWithoutSection
                            // #27 — Taux de consistance
                            consistencySection
                            // #28 — Courbe d'accélération
                            accelerationSection
                            // #29 — Tableau comparatif chapitres
                            chapterComparisonSection
                        }
                        .frame(maxWidth: .infinity)
                    }
                    // #30 — Mois en revue (pleine largeur)
                    monthReviewSection
                    // #32 — Heatmap horaire (pleine largeur)
                    hourHeatmapSection
                }
            }
            .padding(20)
        }
        .background(AppBackdrop())
        // #55 — Zoom graphique
        .sheet(item: $zoomedChart) { _ in zoomedSheetContent }
        // #59 — Onboarding contextuel
        .onboardingTooltip(
            key: "stats_zoom",
            message: "Cliquez sur l'icône ↗ d'un graphique pour l'agrandir en plein écran.",
            icon: "arrow.up.left.and.arrow.down.right",
            alignment: .top
        )
    }

    // MARK: - #8 Momentum 30 jours

    private var momentumSection: some View {
        VStack(spacing: 10) {
            HStack { SectionHeader("Momentum 30 jours"); Spacer(); expandButton(.momentum) }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Vitesse glissante · fenêtre 7j")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Spacer()
                        let vel = store.velocity14Days
                        if vel > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill").font(.system(size: 10))
                                Text("\(store.formatCount(vel))/j moy.")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.accent)
                        }
                    }

                    let points: [VelocityPoint] = store
                        .rollingVelocityData(windowDays: 7, daysBack: 30)
                        .map { VelocityPoint(date: $0.date, velocity: $0.velocity) }

                    if points.contains(where: { $0.velocity > 0 }) {
                        Chart(points) { p in
                            AreaMark(
                                x: .value("Date", p.date),
                                y: .value("Vitesse", p.velocity)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accent.opacity(0.22), Color.accent.opacity(0.03)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            LineMark(
                                x: .value("Date", p.date),
                                y: .value("Vitesse", p.velocity)
                            )
                            .foregroundStyle(Color.accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.catmullRom)

                            // #56 — Tooltip rule
                            if let hovered = momentumHover,
                               let match = points.min(by: { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }) {
                                RuleMark(x: .value("Date", match.date))
                                    .foregroundStyle(Color.accent.opacity(0.4))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                                        chartTooltipBubble(
                                            date: match.date,
                                            label: store.formatCount(match.velocity) + "/j"
                                        )
                                    }
                                PointMark(x: .value("Date", match.date), y: .value("Vitesse", match.velocity))
                                    .foregroundStyle(Color.accent)
                                    .symbolSize(30)
                            }
                        }
                        .chartXSelection(value: $momentumHover)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.labelMuted)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { val in
                                AxisGridLine().foregroundStyle(Color.cardBorder.opacity(0.5))
                                if let v = val.as(Int.self) {
                                    AxisValueLabel {
                                        Text(store.formatCount(v))
                                            .font(.system(size: 10))
                                            .foregroundStyle(Color.labelMuted)
                                    }
                                }
                            }
                        }
                        .frame(height: 110)

                        // Tendance
                        if let t = momentumTrend(points) {
                            HStack(spacing: 4) {
                                Image(systemName: t.up ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10))
                                Text(t.label).font(.system(size: 10))
                            }
                            .foregroundColor(t.up ? .accentGreen : .accentWarm)
                        }
                    } else {
                        Text("Données insuffisantes pour la courbe")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                    }
                }
            }
        }
    }

    private func momentumTrend(_ pts: [VelocityPoint]) -> (label: String, up: Bool)? {
        let active = pts.filter { $0.velocity > 0 }
        guard active.count >= 8 else { return nil }
        let half = active.count / 2
        let avg1 = active.prefix(half).map(\.velocity).reduce(0, +) / half
        let avg2 = active.suffix(half).map(\.velocity).reduce(0, +) / half
        guard avg1 > 0 else { return nil }
        let delta = avg2 - avg1
        let pct = abs(delta * 100 / avg1)
        guard pct >= 5 else { return nil }
        let up = delta > 0
        return ("\(up ? "+" : "-")\(pct)% vs début de période", up)
    }

    // MARK: - #9 Top 10 meilleures sessions

    private var top10Section: some View {
        VStack(spacing: 10) {
            SectionHeader("Top 10 sessions")
            GlassCard {
                let top = store.top10Days
                if top.isEmpty {
                    Text("Aucune donnée").font(.system(size: 11)).foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(top.enumerated()), id: \.element.date) { idx, entry in
                            HStack(spacing: 8) {
                                // Rang
                                ZStack {
                                    if idx == 0 {
                                        Circle().fill(Color.yellow.opacity(0.15)).frame(width: 20, height: 20)
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 10)).foregroundColor(.semYellow)
                                    } else {
                                        Text("\(idx + 1)")
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .foregroundColor(.labelMuted)
                                    }
                                }
                                .frame(width: 20)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(shortDate(entry.date))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                    if let proj = entry.projectName {
                                        Text(proj)
                                            .font(.system(size: 10))
                                            .foregroundColor(.labelMuted)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                HStack(spacing: 3) {
                                    Text(store.formatCount(entry.total))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(idx == 0 ? .yellow : .primary)
                                    Text(store.data.useWordCount ? "mots" : "signes")
                                        .font(.system(size: 10))
                                        .foregroundColor(.labelMuted)
                                }
                            }
                            .padding(.vertical, 5)
                            if idx < top.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - #10 Semaine courante vs précédente

    private struct WeekDay {
        let letter: String
        let current: Int
        let previous: Int
        let isToday: Bool
        let isPast: Bool   // dans la semaine courante mais déjà passé
    }

    private var weekDays: [WeekDay] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let today = cal.startOfDay(for: Date())
        let totals = store.dailyTotals()
        let letters = ["L", "M", "M", "J", "V", "S", "D"]

        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return [] }

        return (0..<7).map { offset in
            let curr = cal.date(byAdding: .day, value: offset, to: weekStart)!
            let prev = cal.date(byAdding: .day, value: offset - 7, to: weekStart)!
            let currStr = DataStore.dateString(from: curr)
            let prevStr = DataStore.dateString(from: prev)
            return WeekDay(
                letter: letters[offset],
                current: totals[currStr] ?? 0,
                previous: totals[prevStr] ?? 0,
                isToday: currStr == DataStore.today,
                isPast: curr <= today
            )
        }
    }

    private var weekComparisonSection: some View {
        VStack(spacing: 10) {
            HStack { SectionHeader("Semaine en cours vs précédente"); Spacer(); expandButton(.weekComparison) }
            GlassCard {
                let days = weekDays
                let currTotal = days.reduce(0) { $0 + $1.current }
                let prevTotal = days.reduce(0) { $0 + $1.previous }
                let maxVal = max(days.map { max($0.current, $0.previous) }.max() ?? 0, 1)

                VStack(spacing: 10) {
                    // Légende
                    HStack {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.accent)
                                .frame(width: 12, height: 4)
                            Text("Cette semaine").font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2).fill(Color.labelMuted.opacity(0.35))
                                .frame(width: 12, height: 4)
                            Text("Semaine préc.").font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                    }

                    // Barres groupées
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(days.indices, id: \.self) { i in
                            let day = days[i]
                            let rCurr = CGFloat(day.current) / CGFloat(maxVal)
                            let rPrev = CGFloat(day.previous) / CGFloat(maxVal)
                            VStack(spacing: 2) {
                                GeometryReader { geo in
                                    let h = geo.size.height
                                    HStack(spacing: 1) {
                                        // Barre préc.
                                        VStack {
                                            Spacer(minLength: 0)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Color.labelMuted.opacity(0.25))
                                                .frame(height: max(2, h * rPrev))
                                        }
                                        // Barre courante
                                        VStack {
                                            Spacer(minLength: 0)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(day.isToday ? Color.accentGreen : (day.isPast ? Color.accent : Color.accent.opacity(0.25)))
                                                .frame(height: max(day.current > 0 ? 2 : 0, h * rCurr))
                                        }
                                    }
                                }
                                .frame(height: 60)
                                Text(day.letter)
                                    .font(.system(size: 10, weight: day.isToday ? .bold : .regular))
                                    .foregroundColor(day.isToday ? .accent : .labelMuted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    // Totaux
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.formatCount(currTotal))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                            Text("Cette semaine")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        if prevTotal > 0 {
                            let delta = currTotal - prevTotal
                            let pct = Int(abs(Double(delta) / Double(prevTotal) * 100))
                            HStack(spacing: 3) {
                                Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.system(size: 10))
                                Text("\(delta >= 0 ? "+" : "-")\(pct)%")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(delta >= 0 ? .accentGreen : .accentWarm)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(store.formatCount(prevTotal))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.labelMuted.opacity(0.7))
                            Text("Semaine préc.")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - #11 Heure de pic personnel

    private var peakHourSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Heure de pic personnel")
            GlassCard {
                let hourly = store.hourlyProductivity
                let total = hourly.reduce(0, +)
                guard total > 0 else {
                    return AnyView(
                        Text("Pas encore de données par heure")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity)
                    )
                }

                // Meilleure fenêtre de 3 heures consécutives
                var bestWindow = (start: 6, sum: 0)
                for h in 0..<22 {
                    let s = hourly[h] + hourly[h+1] + hourly[h+2]
                    if s > bestWindow.sum { bestWindow = (h, s) }
                }

                // Trouver le pic simple
                let peakHour = hourly.enumerated().max { $0.element < $1.element }!.offset
                let maxVal = max(hourly.max() ?? 1, 1)

                return AnyView(
                    VStack(alignment: .leading, spacing: 10) {
                        // Badge pic
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accentWarm)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Pic d'écriture")
                                    .font(.system(size: 10))
                                    .foregroundColor(.labelMuted)
                                Text("\(bestWindow.start)h–\(bestWindow.start + 3)h")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("Pic unique")
                                    .font(.system(size: 10))
                                    .foregroundColor(.labelMuted)
                                Text("\(peakHour)h\(peakHour < 12 ? " (matin)" : peakHour < 18 ? " (après-midi)" : " (soir)")")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.accentWarm)
                            }
                        }
                        .padding(10)
                        .background(Color.accentWarm.opacity(0.06))
                        .clipShape(AppLook.buttonShape(8))

                        // Mini histogramme 6h–24h
                        let workHours = Array(6...23)
                        HStack(alignment: .bottom, spacing: 2) {
                            ForEach(workHours, id: \.self) { h in
                                let val = hourly[h]
                                let ratio = CGFloat(val) / CGFloat(maxVal)
                                let isPeak = (h >= bestWindow.start && h < bestWindow.start + 3)
                                VStack(spacing: 2) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(isPeak ? Color.accentWarm : Color.accent.opacity(0.4))
                                        .frame(height: max(2, 44 * ratio))
                                    if h % 3 == 0 {
                                        Text("\(h)h")
                                            .font(.system(size: 7))
                                            .foregroundColor(.labelMuted)
                                    } else {
                                        Text("").font(.system(size: 7))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        .frame(height: 60)
                    }
                )
            }
        }
    }

    // MARK: - #12 Prévision avec intervalle de confiance

    private var projectionConfidenceSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Prévision — intervalle de confiance")
            GlassCard {
                let stats = store.velocityStats14Days
                guard stats.avg > 0 else {
                    return AnyView(
                        Text("Rythme insuffisant pour projeter")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity)
                    )
                }
                let remaining = store.thesisRemainingChars
                guard remaining > 0 else {
                    return AnyView(
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentGreen)
                            Text("Tous les objectifs atteints !")
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.accentGreen)
                        }
                        .frame(maxWidth: .infinity)
                    )
                }

                let daysAvg  = Int(ceil(Double(remaining) / Double(stats.avg)))
                let daysBest = stats.max > 0 ? Int(ceil(Double(remaining) / Double(stats.max))) : daysAvg
                let daysWorse = stats.min > 0 ? Int(ceil(Double(remaining) / Double(stats.min))) : daysAvg * 2

                let cal = Calendar(identifier: .gregorian)
                let dateAvg   = cal.date(byAdding: .day, value: daysAvg,   to: Date())
                let dateBest  = cal.date(byAdding: .day, value: daysBest,  to: Date())
                let dateWorse = cal.date(byAdding: .day, value: daysWorse, to: Date())

                return AnyView(
                    VStack(spacing: 8) {
                        confidenceRow(icon: "arrow.up.right.circle.fill",
                                      color: .accentGreen,
                                      label: "Optimiste",
                                      days: daysBest,
                                      date: dateBest,
                                      vel: stats.max)
                        Divider()
                        confidenceRow(icon: "minus.circle.fill",
                                      color: .accent,
                                      label: "Attendu",
                                      days: daysAvg,
                                      date: dateAvg,
                                      vel: stats.avg)
                        Divider()
                        confidenceRow(icon: "arrow.down.right.circle.fill",
                                      color: .accentWarm,
                                      label: "Pessimiste",
                                      days: daysWorse,
                                      date: dateWorse,
                                      vel: stats.min)

                        HStack(spacing: 4) {
                            Image(systemName: "info.circle").font(.system(size: 10))
                            Text("Basé sur \(store.formatCount(remaining)) restants · rythme sur 14 j")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.labelMuted.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                )
            }
        }
    }

    private func confidenceRow(icon: String, color: Color, label: String,
                                days: Int, date: Date?, vel: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(date.map { DataStore.formatDate($0) } ?? "—")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text("\(days) j · \(store.formatCount(vel))/j")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    // MARK: - #13 Distribution par projet (30 jours)

    private var projectDistributionSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Distribution par projet · 30 jours")
            GlassCard {
                let shares = store.projectDistribution30Days
                if shares.isEmpty {
                    Text("Pas d'activité sur 30 jours")
                        .font(.system(size: 11)).foregroundColor(.labelMuted).frame(maxWidth: .infinity)
                } else {
                    let grandTotal = shares.reduce(0) { $0 + $1.total }
                    VStack(spacing: 10) {
                        ForEach(shares.indices, id: \.self) { i in
                            let share = shares[i]
                            let ratio = grandTotal > 0 ? Double(share.total) / Double(grandTotal) : 0
                            let color = projectPalette[share.colorIndex % projectPalette.count]
                            VStack(spacing: 4) {
                                HStack {
                                    HStack(spacing: 6) {
                                        Circle().fill(color).frame(width: 7, height: 7)
                                        Text(share.name)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text(store.formatCount(share.total))
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(color)
                                        Text("(\(Int(ratio * 100))%)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.labelMuted)
                                    }
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.cardBorder)
                                            .frame(height: 5)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(color)
                                            .frame(width: geo.size.width * CGFloat(ratio), height: 5)
                                            .appAnimation(Motion.progress, value: ratio)
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        // Total
                        Divider()
                        HStack {
                            Text("Total 30 jours")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            Text(store.formatCount(grandTotal))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            Text(store.data.useWordCount ? "mots" : "signes")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                    }
                }
            }
        }
    }

    // MARK: - #14 Jours sans écriture ce mois

    private var daysWithoutSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Régularité ce mois-ci")
            GlassCard {
                let written  = store.daysWrittenThisMonth
                let without  = store.daysWithoutWritingThisMonth
                let total    = store.daysInCurrentMonth
                let cal      = Calendar(identifier: .gregorian)
                let dayOfMonth = cal.component(.day, from: Date())

                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        // Jours écrits
                        statPill(
                            value: written,
                            label: "jours écrits",
                            color: .accentGreen,
                            icon: "checkmark.circle.fill"
                        )
                        Spacer()
                        // Jours sans écriture
                        statPill(
                            value: without,
                            label: "jours sans écriture",
                            color: without > 7 ? Color.semRed : .accentWarm,
                            icon: without > 7 ? "exclamationmark.circle.fill" : "minus.circle.fill"
                        )
                        Spacer()
                        // Jours restants
                        let remaining = total - dayOfMonth
                        statPill(
                            value: remaining,
                            label: "jours restants",
                            color: .labelMuted,
                            icon: "calendar"
                        )
                    }

                    // Barre mensuelle
                    VStack(spacing: 4) {
                        GeometryReader { geo in
                            let elapsed = max(0, dayOfMonth - (store.dailyTotals()[DataStore.today] ?? 0 > 0 ? 0 : 1))
                            let writtenRatio = elapsed > 0 ? CGFloat(written) / CGFloat(max(elapsed, 1)) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3).fill(Color.cardBorder).frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(LinearGradient(
                                        colors: written > 0 ? [.accentGreen, .accent] : [.cardBorder],
                                        startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(0, geo.size.width * writtenRatio), height: 6)
                                    .appAnimation(Motion.progress, value: writtenRatio)
                            }
                        }
                        .frame(height: 6)
                        Text("\(written) / \(dayOfMonth > 0 ? dayOfMonth : total) jours actifs · \(total - dayOfMonth) à venir")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }

                    if without > 7 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                            Text("Plus de 7 jours sans écriture ce mois — essaie de viser 15 min/jour.")
                                .font(.system(size: 10))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundColor(Color.semRed)
                        .padding(8)
                        .background(Color.semRed.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                    }
                }
            }
        }
    }

    private func statPill(value: Int, label: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 20, weight: .bold, design: AppLook.fontDesign))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - #26 Projection de soutenance

    private var defenseProjectionSection: some View {
        let proj = store.defenseProjection
        return VStack(spacing: 10) {
            SectionHeader("Projection de fin")
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: AppLook.r(8, 12)).fill(Color.accent.opacity(0.12)).frame(width: 28, height: 28)
                            Image(systemName: "calendar.badge.clock").font(.system(size: 12, weight: .semibold)).foregroundColor(.accent)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fin estimée du projet")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(DataStore.formatNumber(proj.totalWritten)) / \(DataStore.formatNumber(proj.totalGoal)) car. écrits")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        if let days = proj.daysRemainingRealistic {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("dans \(days) j")
                                    .font(.system(size: 16, weight: .bold, design: AppLook.fontDesign))
                                    .foregroundColor(.accent)
                                Text("au rythme actuel")
                                    .font(.system(size: 10))
                                    .foregroundColor(.labelMuted)
                            }
                        }
                    }

                    if proj.totalGoal > 0 {
                        let ratio = min(1.0, Double(proj.totalWritten) / Double(proj.totalGoal))
                        VStack(alignment: .leading, spacing: 3) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3).fill(Color.cardBorder).frame(height: 5)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(LinearGradient(colors: [.accent, .accentGreen], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: geo.size.width * ratio, height: 5)
                                }
                            }.frame(height: 5)
                            Text("\(Int(ratio * 100))% de l'objectif global atteint")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                    }

                    HStack(spacing: 0) {
                        projDatePill(label: "Optimiste", date: proj.optimisticDate, color: .accentGreen)
                        Spacer()
                        projDatePill(label: "Réaliste",  date: proj.realisticDate,  color: .accent)
                        Spacer()
                        projDatePill(label: "Pessimiste", date: proj.pessimisticDate, color: .accentWarm)
                    }
                }
            }
        }
    }

    private func projDatePill(label: String, date: Date?, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(.labelMuted).textCase(.uppercase).tracking(0.3)
            Text(date.map { fmtMonthYear($0) } ?? "—")
                .font(.system(size: 12, weight: .bold, design: AppLook.fontDesign))
                .foregroundColor(date != nil ? color : .labelMuted)
        }
    }

    private func fmtMonthYear(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMM yyyy"
        return f.string(from: date)
    }

    // MARK: - #27 Taux de consistance

    private var consistencySection: some View {
        VStack(spacing: 10) {
            HStack { SectionHeader("Taux de consistance"); Spacer(); expandButton(.consistency) }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        ForEach([30, 60, 90], id: \.self) { days in
                            let rate = store.consistencyRate(days: days)
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle().stroke(Color.cardBorder, lineWidth: 4).frame(width: 48, height: 48)
                                    Circle()
                                        .trim(from: 0, to: rate)
                                        .stroke(consistencyColor(rate), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                        .frame(width: 48, height: 48)
                                        .rotationEffect(.degrees(-90))
                                    Text("\(Int(rate * 100))%")
                                        .font(.system(size: 11, weight: .bold, design: AppLook.fontDesign))
                                        .foregroundColor(consistencyColor(rate))
                                }
                                Text("\(days)j")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.labelMuted)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Text("Jours avec au moins une saisie d'écriture")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
            }
        }
    }

    private func consistencyColor(_ rate: Double) -> Color {
        if rate >= 0.7 { return .accentGreen }
        if rate >= 0.4 { return .accent }
        return .accentWarm
    }

    // MARK: - #28 Courbe d'accélération

    private var accelerationSection: some View {
        let data = store.accelerationData
        let isAccel = data.trend > 0.05
        let isDecel = data.trend < -0.05
        let trendColor: Color = isAccel ? .accentGreen : isDecel ? .accentWarm : .labelMuted
        return VStack(spacing: 10) {
            HStack { SectionHeader("Courbe d'accélération"); Spacer(); expandButton(.acceleration) }
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: isAccel ? "arrow.up.right" : isDecel ? "arrow.down.right" : "minus")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(trendColor)
                                Text(isAccel ? "En accélération" : isDecel ? "En ralentissement" : "Stable")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(trendColor)
                            }
                            Text("fenêtre 14 jours vs 14 jours précédents")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(store.formatCount(data.recentAvg))/j")
                                .font(.system(size: 14, weight: .bold, design: AppLook.fontDesign))
                            Text("vs \(store.formatCount(data.priorAvg))/j")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                    }

                    if data.last14Increments.contains(where: { $0 > 0 }) {
                        let vals = data.last14Increments.map { Double($0) }
                        let maxVal = vals.max() ?? 1
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(vals.enumerated()), id: \.offset) { i, v in
                                let h = maxVal > 0 ? v / maxVal : 0
                                let dayLabel = "J-\(14 - i)"
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(v > 0 ? trendColor.opacity(0.7 + 0.3 * h) : Color.cardBorder)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(3, CGFloat(h) * 48))
                                    .help("\(dayLabel) · \(store.formatCount(Int(v)))") // #56
                            }
                        }
                        .frame(height: 52)
                    }

                    if abs(data.trend) >= 0.05 {
                        let pct = Int(abs(data.trend) * 100)
                        Text(isAccel ? "↑ +\(pct)% par rapport aux 14 jours précédents"
                             : "↓ -\(pct)% — pense à identifier les blocages")
                            .font(.system(size: 10))
                            .foregroundColor(trendColor)
                    }
                }
            }
        }
    }

    // MARK: - #29 Tableau comparatif chapitres

    private var chapterComparisonSection: some View {
        let rows = store.chapterComparisonRows
        return VStack(spacing: 10) {
            HStack { SectionHeader("Comparatif chapitres"); Spacer(); expandButton(.chapterCompar) }
            GlassCard {
                if rows.isEmpty {
                    Text("Aucun chapitre actif")
                        .font(.system(size: 11)).foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Header
                        HStack(spacing: 0) {
                            Text("Chapitre").font(.system(size: 10, weight: .semibold)).foregroundColor(.labelMuted).frame(maxWidth: .infinity, alignment: .leading)
                            Text("%").font(.system(size: 10, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 36, alignment: .trailing)
                            Text("Moy/j").font(.system(size: 10, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 52, alignment: .trailing)
                            Text("Jours").font(.system(size: 10, weight: .semibold)).foregroundColor(.labelMuted).frame(width: 40, alignment: .trailing)
                        }
                        .padding(.bottom, 6)
                        Divider()
                        ForEach(rows.prefix(8)) { row in
                            HStack(spacing: 0) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.chapterName).font(.system(size: 11, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                                    Text(row.projectName).font(.system(size: 10)).foregroundColor(.labelMuted).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                let pctColor: Color = row.isCompleted ? .accentGreen : (row.progressPct >= 75 ? .accentGreen : row.progressPct >= 50 ? .accent : .accentWarm)
                                Text(row.isCompleted ? "✓" : "\(row.progressPct)%")
                                    .font(.system(size: 11, weight: .bold, design: AppLook.fontDesign))
                                    .foregroundColor(pctColor)
                                    .frame(width: 36, alignment: .trailing)
                                Text(row.avgCharsPerDay > 0 ? store.formatCount(row.avgCharsPerDay) : "—")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                                    .frame(width: 52, alignment: .trailing)
                                if let d = row.estimatedDaysRemaining {
                                    Text("J-\(d)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(d <= 30 ? .accentWarm : .accent)
                                } else {
                                    Text(row.isCompleted ? "—" : row.goal == 0 ? "∞" : "—")
                                        .font(.system(size: 11)).foregroundColor(.labelMuted)
                                }
                                Divider().frame(width: 40)
                            }
                            .padding(.vertical, 5)
                            if row.id != rows.prefix(8).last?.id { Divider() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - #30 Mois en revue

    private var monthReviewSection: some View {
        let review = store.currentMonthReview
        return VStack(spacing: 10) {
            HStack { SectionHeader("Mois en revue — \(review.monthLabel)"); Spacer(); expandButton(.monthReview) }
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        reviewMetric(value: store.formatCount(review.totalChars),
                                     label: "total ce mois", icon: "text.cursor", color: .accent)
                        Divider().frame(height: 40)
                        reviewMetric(value: "\(review.activeDays)j",
                                     label: "jours actifs", icon: "calendar.badge.checkmark", color: .accentGreen)
                        Divider().frame(height: 40)
                        reviewMetric(value: review.activeDays > 0 ? store.formatCount(review.totalChars / review.activeDays) : "—",
                                     label: "moyenne/jour actif", icon: "chart.line.uptrend.xyaxis", color: .accent)
                        Divider().frame(height: 40)
                        let growthColor: Color = review.growthPct >= 0 ? .accentGreen : .accentWarm
                        VStack(spacing: 3) {
                            HStack(spacing: 2) {
                                Image(systemName: review.growthPct >= 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(review.growthPct >= 0 ? "+" : "")\(Int(review.growthPct))%")
                                    .font(.system(size: 14, weight: .bold, design: AppLook.fontDesign))
                            }
                            .foregroundColor(growthColor)
                            Text("vs mois dernier").font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if !review.bestDayDate.isEmpty && review.bestDayChars > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.accentWarm)
                            Text("Meilleur jour · \(shortDate(review.bestDayDate)) — \(store.formatCount(review.bestDayChars)) car.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.accentWarm.opacity(0.06))
                        .clipShape(AppLook.buttonShape(7))
                    }
                }
            }
        }
    }

    private func reviewMetric(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            Text(value).font(.system(size: 14, weight: .bold, design: AppLook.fontDesign)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(.labelMuted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - #31 Vélocité glissante 14j

    private var rollingVelocitySection: some View {
        let points = store.rollingVelocity14
        let hasData = points.contains { $0.rollingAvg > 0 }
        return VStack(spacing: 10) {
            HStack { SectionHeader("Vélocité glissante · 14j"); Spacer(); expandButton(.rollingVelocity) }
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    if hasData {
                        Chart(points) { p in
                            AreaMark(x: .value("Date", p.dateStr), y: .value("Avg", p.rollingAvg))
                                .foregroundStyle(LinearGradient(
                                    colors: [Color.accentGreen.opacity(0.18), Color.accentGreen.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Date", p.dateStr), y: .value("Avg", p.rollingAvg))
                                .foregroundStyle(Color.accentGreen)
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.catmullRom)

                            // #56 — Tooltip rule
                            if let hs = velocityHoverStr,
                               let match = points.min(by: {
                                   abs(($0.dateStr).compare(hs).rawValue) < abs(($1.dateStr).compare(hs).rawValue)
                               }) {
                                RuleMark(x: .value("Date", match.dateStr))
                                    .foregroundStyle(Color.accentGreen.opacity(0.4))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                                    .annotation(position: .top, alignment: .leading, spacing: 4) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(match.dateStr).font(.system(size: 10)).foregroundColor(.labelMuted)
                                            Text(store.formatCount(Int(match.rollingAvg)) + "/j")
                                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.primary)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                                .fill(Color.glassFill)
                                                .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                                    .stroke(Color.cardBorder, lineWidth: 0.5))
                                        )
                                    }
                                PointMark(x: .value("Date", match.dateStr), y: .value("Avg", match.rollingAvg))
                                    .foregroundStyle(Color.accentGreen).symbolSize(30)
                            }
                        }
                        .chartXSelection(value: $velocityHoverStr)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day, count: 14)) { _ in
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                    .font(.system(size: 10)).foregroundStyle(Color.labelMuted)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { val in
                                AxisGridLine().foregroundStyle(Color.cardBorder.opacity(0.4))
                                if let v = val.as(Double.self) {
                                    AxisValueLabel {
                                        Text(store.formatCount(Int(v)))
                                            .font(.system(size: 10)).foregroundStyle(Color.labelMuted)
                                    }
                                }
                            }
                        }
                        .frame(height: 100)
                        Text("Moyenne glissante sur 14 jours consécutifs")
                            .font(.system(size: 10)).foregroundColor(.labelMuted)
                    } else {
                        Text("Données insuffisantes (14j minimum requis)")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity).frame(height: 60)
                    }
                }
            }
        }
    }

    // MARK: - #32 Heatmap horaire d'écriture

    private var hourHeatmapSection: some View {
        let entries = store.hourHeatmapData
        let maxChars = entries.map(\.totalChars).max() ?? 1
        let hasAny = entries.contains { $0.totalChars > 0 }
        return VStack(spacing: 10) {
            HStack { SectionHeader("Heatmap horaire d'écriture"); Spacer(); expandButton(.hourHeatmap) }
            GlassCard {
                if !hasAny {
                    Text("Aucune donnée horaire disponible — saisie via l'horodatage")
                        .font(.system(size: 11)).foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        // Grid 24 heures
                        GeometryReader { geo in
                            let cellW = (geo.size.width - 23 * 2) / 24
                            HStack(alignment: .bottom, spacing: 2) {
                                ForEach(entries) { e in
                                    let ratio = maxChars > 0 ? CGFloat(e.totalChars) / CGFloat(maxChars) : 0
                                    VStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(heatColor(ratio: ratio))
                                            .frame(width: cellW, height: max(4, ratio * 60))
                                        if e.hour % 6 == 0 {
                                            Text("\(e.hour)h")
                                                .font(.system(size: 7))
                                                .foregroundColor(.labelMuted)
                                        } else {
                                            Color.clear.frame(width: cellW, height: 10)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(height: 80)

                        // Pic et résumé
                        if let peak = entries.max(by: { $0.totalChars < $1.totalChars }), peak.totalChars > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "sun.max.fill").font(.system(size: 10)).foregroundColor(.accentWarm)
                                Text("Pic d'écriture · \(peak.hour)h–\(peak.hour + 1)h (\(store.formatCount(peak.totalChars)) car. cumulés)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func heatColor(ratio: CGFloat) -> Color {
        if ratio <= 0    { return Color.cardBorder }
        if ratio < 0.25  { return Color.accent.opacity(0.2) }
        if ratio < 0.5   { return Color.accent.opacity(0.45) }
        if ratio < 0.75  { return Color.accent.opacity(0.70) }
        return Color.accent
    }

    // MARK: - #56 Tooltip helper

    /// Compact bubble shown when hovering a chart point.
    private func chartTooltipBubble(date: Date, label: String) -> some View {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMM"
        return VStack(alignment: .leading, spacing: 2) {
            Text(df.string(from: date))
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                .fill(Color.glassFill)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: 0.5))
        )
    }

    // MARK: - #55 Zoom helpers

    /// Small expand button injected next to each chart section header.
    private func expandButton(_ chart: ZoomedChart) -> some View {
        Button {
            zoomedChart = chart
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.labelMuted)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.glassFill)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.cardBorder, lineWidth: 0.5))
                )
        }
        .buttonStyle(.pressable)
        .help("Agrandir ce graphique")
        .accessibilityLabel("Agrandir ce graphique")
    }

    /// Full-screen sheet content for zoomed chart.
    @ViewBuilder private var zoomedSheetContent: some View {
        if let chart = zoomedChart {
            ScrollView {
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Text(chart.rawValue.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .kerning(0.8)
                        Spacer()
                        Button { zoomedChart = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.labelMuted)
                        }
                        .buttonStyle(.pressable)
                        .keyboardShortcut(.escape, modifiers: [])
                        .help("Fermer")
                        .accessibilityLabel("Fermer")
                    }
                    .padding(.horizontal, 20).padding(.top, 20)

                    Divider().padding(.horizontal, 20)

                    // Chart content (re-uses the existing section vars, scaled up)
                    Group {
                        switch chart {
                        case .momentum:        momentumSection
                        case .weekComparison:  weekComparisonSection
                        case .consistency:     consistencySection
                        case .acceleration:    accelerationSection
                        case .chapterCompar:   chapterComparisonSection
                        case .monthReview:     monthReviewSection
                        case .rollingVelocity: rollingVelocitySection
                        case .hourHeatmap:     hourHeatmapSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .scaleEffect(1.0) // already fills width; charts auto-expand
                }
                .padding(.bottom, 20)
            }
            .background(AppBackdrop())
            .frame(minWidth: 700, minHeight: 500)
        }
    }

    // MARK: - Helpers

    private func shortDate(_ dateStr: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "d MMM yyyy"
        return out.string(from: d)
    }
}
