import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct HeatmapView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var hoveredDate: String?
    @State private var selectedProjectId: UUID?
    @State private var pngExportSuccess: Bool = false

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
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                            .fill(showSidebar ? Color.accent.opacity(0.15) : Color.glassFill)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                                    .stroke(showSidebar ? Color.accent.opacity(0.4) : Color.glassBorder, lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 2) {
                Text("Activite")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("365 derniers jours · \(metrics.activeDays) jour(s) actif(s)")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }

            Spacer()

            // #33 — Export heatmap PNG
            Button { exportHeatmapAsPNG(metrics: metrics) } label: {
                HStack(spacing: 5) {
                    Image(systemName: pngExportSuccess ? "checkmark" : "photo.on.rectangle")
                        .font(.system(size: 12))
                        .foregroundColor(pngExportSuccess ? .accentGreen : .labelMuted)
                    Text(pngExportSuccess ? "Sauvegardé" : "PNG")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(pngExportSuccess ? .accentGreen : .labelMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.glassFill)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(
                    pngExportSuccess ? Color.accentGreen.opacity(0.4) : Color.glassBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
            }
            .buttonStyle(.pressable)
            .appAnimation(.easeInOut(duration: 0.2), value: pngExportSuccess)
            .help("Exporter la heatmap en image PNG")
        }
    }

    private func exportHeatmapAsPNG(metrics: ActivityMetrics) {
        let totals = cachedTotals
        let snapshot = HeatmapSnapshotView(totals: totals, activeDays: metrics.activeDays)
        let host = NSHostingView(rootView: snapshot)
        let size = NSSize(width: 900, height: 200)
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        guard let bitmapRep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmapRep)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(bitmapRep)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [.compressionFactor: 0.9]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        panel.nameFieldStringValue = "heatmap_\(dateTag).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? pngData.write(to: url)
            pngExportSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pngExportSuccess = false }
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
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .labelMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // ── Stats row ─────────────────────────────────────────────────────────────

    private func statsRow(metrics: ActivityMetrics) -> some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "Total 1 an", value: fmt(metrics.totalChars), unit: "car.", color: .accent)
            MiniStatCard(label: "Jours actifs", value: "\(metrics.activeDays)", unit: "j", color: .accentWarm)
            MiniStatCard(label: "Moy./seance", value: fmt(metrics.averagePerActiveDay), unit: "car.", color: .accentGreen)
            MiniStatCard(label: "Meilleur jour", value: fmt(metrics.bestDayCount), unit: "car.", color: Color(red: 0.843, green: 0.700, blue: 0.125))
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
                                .font(.system(size: 10, weight: .medium))
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
                Text("Aucune écriture")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(8, 12))
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

// MARK: - Heatmap Snapshot for PNG export (#33)

struct HeatmapSnapshotView: View {
    let totals: [String: Int]
    let activeDays: Int

    private let cellSize: CGFloat = 11
    private let cellGap: CGFloat = 2
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c
    }()

    private var weeks: [[Date?]] {
        let today = Date()
        let startDate = cal.date(byAdding: .day, value: -364, to: today) ?? today
        var current = cal.startOfDay(for: startDate)
        var result: [[Date?]] = []
        var week: [Date?] = Array(repeating: nil, count: cal.component(.weekday, from: current) - cal.firstWeekday)
        while current <= today {
            week.append(current)
            if week.count == 7 { result.append(week); week = [] }
            current = cal.date(byAdding: .day, value: 1, to: current) ?? today + 1
        }
        if !week.isEmpty { result.append(week) }
        return result
    }

    private func intensity(for date: Date) -> Double {
        let str = DataStore.dateString(from: date)
        let val = totals[str] ?? 0
        let max = totals.values.max() ?? 1
        return max > 0 ? Double(val) / Double(max) : 0
    }

    private func cellColor(for date: Date) -> Color {
        let str = DataStore.dateString(from: date)
        let val = totals[str] ?? 0
        if val == 0 { return Color.white.opacity(0.06) }
        let ratio = intensity(for: date)
        return Color.semBlue.opacity(0.2 + 0.8 * ratio)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Heatmap d'activité — 365 jours")
                        .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("\(activeDays) jours actifs · \(DataStore.formatNumber(totals.values.reduce(0, +))) car. au total")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Text(DataStore.today)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 20).padding(.vertical, 14)

            // Heatmap grid
            HStack(alignment: .top, spacing: cellGap) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: cellGap) {
                        ForEach(0..<7, id: \.self) { dayIdx in
                            if dayIdx < week.count, let date = week[dayIdx] {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(cellColor(for: date))
                                    .frame(width: cellSize, height: cellSize)
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.10))
        .frame(width: 900)
    }
}
