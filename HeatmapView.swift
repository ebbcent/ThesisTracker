import SwiftUI

struct HeatmapView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var hoveredDate: String?
    @State private var selectedProjectId: UUID?

    // ── Cached expensive computations ─────────────────────────────────────────
    @State private var cachedTotals: [String: Int] = [:]
    @State private var cachedWeeks: [[Date?]] = []
    @State private var cachedLabels: [(col: Int, name: String)] = []
    @State private var cachedMetrics: ActivityMetrics = ActivityMetrics(totals: [:])

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        return formatter
    }()

    private let cellSize: CGFloat = 13
    private let cellGap: CGFloat = 3

    private let cal: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerView(metrics: cachedMetrics)
                if !store.data.projects.isEmpty {
                    scopeRow
                }
                statsRow(metrics: cachedMetrics)
                heatmapCard(totals: cachedTotals, weeks: cachedWeeks, monthLabels: cachedLabels)
                legendRow
            }
            .padding(20)
        }
        .onAppear { rebuildCache() }
        .onChange(of: selectedProjectId) { rebuildCache() }
        .onReceive(store.$data) { _ in rebuildCache() }
    }

    // ── Cache rebuild ──────────────────────────────────────────────────────────

    private func rebuildCache() {
        let totals = store.dailyTotals(projectId: selectedProjectId)
        let weeks = makeWeeks()
        cachedTotals = totals
        cachedWeeks = weeks
        cachedLabels = monthLabels(for: weeks)
        cachedMetrics = ActivityMetrics(totals: totals)
    }

    // ── Header ────────────────────────────────────────────────────────────────

    private func headerView(metrics: ActivityMetrics) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(showSidebar ? Color.accent.opacity(0.15) : Color.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(showSidebar ? Color.accent.opacity(0.4) : Color.glassBorder, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Activite")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("365 derniers jours · \(metrics.activeDays) jour(s) actif(s)")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }

            Spacer()
        }
    }

    // ── Scope row ─────────────────────────────────────────────────────────────

    private var scopeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                heatmapChip(id: nil, name: "Tous les projets")
                ForEach(store.data.projects) { project in
                    heatmapChip(id: project.id, name: project.name)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func heatmapChip(id: UUID?, name: String) -> some View {
        let isSelected = selectedProjectId == id
        return Button {
            selectedProjectId = id
        } label: {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .labelMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // ── Stats row ─────────────────────────────────────────────────────────────

    private func statsRow(metrics: ActivityMetrics) -> some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "Total 1 an", value: fmt(metrics.totalChars), unit: "car.", color: .accent)
            MiniStatCard(label: "Jours actifs", value: "\(metrics.activeDays)", unit: "j", color: .accentWarm)
            MiniStatCard(label: "Moy./seance", value: fmt(metrics.averagePerActiveDay), unit: "car.", color: .accentGreen)
            MiniStatCard(label: "Meilleur jour", value: fmt(metrics.bestDayCount), unit: "car.", color: .accentGold)
        }
    }

    // ── Heatmap card ──────────────────────────────────────────────────────────

    private func heatmapCard(totals: [String: Int], weeks: [[Date?]], monthLabels: [(col: Int, name: String)]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    Color.clear.frame(height: 16)
                    ForEach(monthLabels, id: \.col) { item in
                        Text(item.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.labelMuted)
                            .offset(x: CGFloat(item.col) * (cellSize + cellGap) + 28)
                    }
                }

                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: cellGap) {
                        ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { day in
                            Text(day)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.labelMuted)
                                .frame(width: 24, height: cellSize, alignment: .trailing)
                        }
                    }
                    .padding(.trailing, 4)

                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: cellGap) {
                            ForEach(0..<weeks.count, id: \.self) { col in
                                VStack(spacing: cellGap) {
                                    ForEach(0..<7, id: \.self) { row in
                                        if let date = weeks[col][row] {
                                            let dateString = DataStore.dateString(from: date)
                                            let level = intensity(totals[dateString] ?? 0)
                                            HeatmapCell(
                                                dateString: dateString,
                                                level: level,
                                                isHovered: hoveredDate == dateString,
                                                cellSize: cellSize,
                                                onHoverChange: { isHovering in
                                                    hoveredDate = isHovering ? dateString
                                                        : hoveredDate == dateString ? nil : hoveredDate
                                                },
                                                onTap: { hoveredDate = dateString }
                                            )
                                        } else {
                                            Color.clear.frame(width: cellSize, height: cellSize)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                if let hoveredDate {
                    tooltipRow(for: hoveredDate, totals: totals)
                        .transition(.opacity)
                }
            }
        }
    }

    // ── Tooltip ───────────────────────────────────────────────────────────────

    private func tooltipRow(for dateString: String, totals: [String: Int]) -> some View {
        let count = totals[dateString] ?? 0
        let displayDate = DataStore.parseDate(dateString).map { DataStore.formatLongDate($0, capitalize: true) } ?? dateString

        return HStack(spacing: 10) {
            Circle()
                .fill(count > 0 ? Color.accent : Color.white.opacity(0.15))
                .frame(width: 7, height: 7)

            Text(displayDate)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            if count > 0 {
                Text(fmt(count) + " car. ecrits")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.accent)
            } else {
                Text("Aucune ecriture")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
    }

    // ── Legend ────────────────────────────────────────────────────────────────

    private var legendRow: some View {
        HStack(spacing: 8) {
            Text("Moins")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)

            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 3)
                    .fill(cellColor(level))
                    .frame(width: cellSize, height: cellSize)
            }

            Text("Plus")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)

            Spacer()

            Text("1 carre = 1 jour")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func makeWeeks() -> [[Date?]] {
        let today = Date()
        guard let startDate = cal.date(byAdding: .day, value: -364, to: today) else { return [] }

        let weekday = cal.component(.weekday, from: startDate)
        let daysFromMonday = (weekday + 5) % 7
        guard let firstMonday = cal.date(byAdding: .day, value: -daysFromMonday, to: startDate) else { return [] }

        var result: [[Date?]] = []
        var weekStart = firstMonday

        while weekStart <= today {
            var week: [Date?] = []
            for offset in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else {
                    week.append(nil); continue
                }
                week.append(day <= today ? day : nil)
            }
            result.append(week)
            guard let nextWeek = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = nextWeek
        }

        return result
    }

    private func monthLabels(for weeks: [[Date?]]) -> [(col: Int, name: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for (column, week) in weeks.enumerated() {
            guard let date = week.compactMap({ $0 }).first else { continue }
            let month = cal.component(.month, from: date)
            guard month != lastMonth else { continue }

            let shortName = Self.monthFormatter.string(from: date)
            let capitalized = shortName.prefix(1).uppercased() + shortName.dropFirst()
            labels.append((column, capitalized))
            lastMonth = month
        }

        return labels
    }

    private func intensity(_ value: Int) -> Int {
        if value == 0 { return 0 }
        if value < 400 { return 1 }
        if value < 1200 { return 2 }
        if value < 2500 { return 3 }
        return 4
    }

    private func cellColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.07)
        case 1: return Color.accent.opacity(0.28)
        case 2: return Color.accent.opacity(0.55)
        case 3: return Color.accent.opacity(0.78)
        default: return Color.accent
        }
    }

    private func fmt(_ value: Int) -> String {
        Self.numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - HeatmapCell (isolated struct — only re-renders when its own props change)

private struct HeatmapCell: View {
    let dateString: String
    let level: Int
    let isHovered: Bool
    let cellSize: CGFloat
    let onHoverChange: (Bool) -> Void
    let onTap: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(isHovered ? Color.white.opacity(0.9) : cellColor(level))
            .frame(width: cellSize, height: cellSize)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovered ? Color.accent : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { onHoverChange($0) }
            .onTapGesture { onTap() }
    }

    private func cellColor(_ level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.07)
        case 1: return Color.accent.opacity(0.28)
        case 2: return Color.accent.opacity(0.55)
        case 3: return Color.accent.opacity(0.78)
        default: return Color.accent
        }
    }
}

// MARK: - ActivityMetrics

private struct ActivityMetrics {
    let totalChars: Int
    let activeDays: Int
    let averagePerActiveDay: Int
    let bestDayCount: Int

    init(totals: [String: Int]) {
        totalChars = totals.values.reduce(0, +)
        activeDays = totals.values.filter { $0 > 0 }.count
        averagePerActiveDay = activeDays > 0 ? totalChars / activeDays : 0
        bestDayCount = totals.values.max() ?? 0
    }
}
