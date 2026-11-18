import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers

enum ChartPeriod: String, CaseIterable, Identifiable {
    case week    = "7j"
    case month   = "30j"
    case quarter = "3m"
    case year    = "1an"
    case all     = "Tout"
    case custom  = "Dates"
    var id: String { rawValue }
}

enum ChartType: String, CaseIterable, Identifiable {
    case line       = "Courbe"
    case bar        = "Barres"
    case velocity   = "Vitesse"
    case cumulative = "Cumulé"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .line:       return "chart.line.uptrend.xyaxis"
        case .bar:        return "chart.bar.fill"
        case .velocity:   return "waveform.path.ecg"
        case .cumulative: return "chart.line.flattrend.xyaxis"
        }
    }
}

struct DayCount: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct ChapterDayCount: Identifiable {
    let id = UUID()
    let date: Date
    let chapterName: String
    let count: Int
}

struct ComparisonPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct VelocityPoint: Identifiable {
    let id = UUID()
    let date: Date
    let velocity: Int
}

struct CumulativePoint: Identifiable {
    let id = UUID()
    let date: Date
    let total: Int
    let isProjected: Bool
}

struct IdealPoint: Identifiable {
    let id = UUID()
    let date: Date
    let ideal: Int
}

struct MonthCount: Identifiable {
    let id = UUID()
    let month: Date   // premier jour du mois
    let count: Int
}

struct ChapterProgress: Identifiable {
    let id = UUID()
    let name: String
    let total: Int
    let goal: Int
    let color: Color
}

struct ChartView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var period: ChartPeriod = .week
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedChapterId: UUID? = nil
    @State private var chartType: ChartType = .line
    @State private var showComparison: Bool = false
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    @State private var customEnd: Date = Date()
    @State private var showMonthlyView: Bool = false
    @State private var showChapterComparison: Bool = false
    @State private var showProjection: Bool = false
    @State private var pngExportSuccess: Bool = false

    private let cal = Calendar(identifier: .gregorian)
    private var now: Date { Date() }

    private var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return store.data.projects.first(where: { $0.id == id })
    }

    // MARK: - Date range

    private var dateRange: (start: Date, end: Date) {
        switch period {
        case .week:
            return (cal.date(byAdding: .day, value: -6, to: now)!, now)
        case .month:
            return (cal.date(byAdding: .day, value: -29, to: now)!, now)
        case .quarter:
            return (cal.date(byAdding: .day, value: -89, to: now)!, now)
        case .year:
            return (cal.date(byAdding: .day, value: -364, to: now)!, now)
        case .all:
            return (store.earliestEntryDate, now)
        case .custom:
            let start = min(customStart, customEnd)
            let end   = max(customStart, customEnd)
            return (start, end)
        }
    }

    private var isComparisonAvailable: Bool {
        period != .custom && period != .all
    }

    private var daysInRange: [Date] {
        var days: [Date] = []
        var current = cal.startOfDay(for: dateRange.start)
        let end     = cal.startOfDay(for: dateRange.end)
        while current <= end {
            days.append(current)
            guard let next = cal.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return days
    }

    private var rangeDays: Int {
        cal.dateComponents([.day], from: dateRange.start, to: dateRange.end).day ?? 30
    }

    // MARK: - Data

    private var lineDataPoints: [DayCount] {
        let totals = store.writtenTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
        return daysInRange.map { date in
            let dateStr = DataStore.dateString(from: date)
            return DayCount(date: date, count: totals[dateStr] ?? 0)
        }
    }

    private var stackedDataPoints: [ChapterDayCount] {
        guard let project = selectedProject else { return [] }
        let chapters = selectedChapterId.flatMap { id in project.chapters.filter { $0.id == id } }
                        ?? project.chapters
        let totalsByChapter = Dictionary(uniqueKeysWithValues: chapters.map { chapter in
            (chapter.id, store.writtenTotals(projectId: project.id, chapterId: chapter.id))
        })
        return daysInRange.flatMap { date -> [ChapterDayCount] in
            let dateStr = DataStore.dateString(from: date)
            return chapters.map { chapter in
                let totals = totalsByChapter[chapter.id] ?? [:]
                return ChapterDayCount(date: date, chapterName: chapter.name, count: totals[dateStr] ?? 0)
            }
        }
    }


    /// Données de la période précédente (même durée, décalée)
    private var comparisonPoints: [ComparisonPoint] {
        guard showComparison, isComparisonAvailable else { return [] }
        let currentStart = cal.startOfDay(for: dateRange.start)
        let dayCount = max(1, daysInRange.count)
        guard let previousStart = cal.date(byAdding: .day, value: -dayCount, to: currentStart) else { return [] }

        let previousDates = (0..<dayCount).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: previousStart)
        }
        let totals = store.writtenTotals(projectId: selectedProjectId, chapterId: selectedChapterId)

        return zip(daysInRange, previousDates).map { currentDate, previousDate in
            let previousDateString = DataStore.dateString(from: previousDate)
            return ComparisonPoint(date: currentDate, count: totals[previousDateString] ?? 0)
        }
    }

    // MARK: - V5 Velocity & Cumulative data

    private var velocityDataPoints: [VelocityPoint] {
        let windowDays = 7
        let totals = store.writtenTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
        return daysInRange.map { date in
            var vals: [Int] = []
            for w in 1...windowDays {
                guard let wDay = cal.date(byAdding: .day, value: -w, to: date) else { continue }
                let v = totals[DataStore.dateString(from: wDay)] ?? 0
                if v > 0 { vals.append(v) }
            }
            let avg = vals.isEmpty ? 0 : vals.reduce(0, +) / vals.count
            return VelocityPoint(date: date, velocity: avg)
        }
    }

    /// Points de la courbe réelle (cumulé) + points projetés si deadline connue
    private var cumulativePoints: [CumulativePoint] {
        let base = store.cumulativeData(projectId: selectedProjectId, chapterId: selectedChapterId)
        let actual = base.map { CumulativePoint(date: $0.date, total: $0.total, isProjected: false) }

        // Projection si une deadline et un objectif sont disponibles
        guard showProjection,
              let projectId = selectedProjectId,
              let project   = store.data.projects.first(where: { $0.id == projectId })
        else { return actual }

        // Choisir la deadline et l'objectif selon le filtre chapitre
        let deadline: Date?
        let goal: Int
        if let chId = selectedChapterId,
           let ch   = project.chapters.first(where: { $0.id == chId }),
           let dl   = ch.deadline, let dlDate = DataStore.parseDate(dl) {
            deadline = dlDate
            goal = ch.goal
        } else {
            // Deadline la plus proche parmi les chapitres
            let nextDl = project.chapters
                .compactMap { $0.deadline.flatMap(DataStore.parseDate) }
                .filter { $0 > Date() }.sorted().first
            deadline = nextDl
            goal = project.chapters.reduce(0) { $0 + $1.goal }
        }

        guard let dl = deadline, goal > 0, let currentTotal = actual.last?.total else { return actual }
        let vel = store.velocity14Days
        guard vel > 0 else { return actual }

        var projected: [CumulativePoint] = []
        var cursor = cal.startOfDay(for: Date())
        let end    = cal.startOfDay(for: dl)
        var running = currentTotal
        while cursor <= end {
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor.addingTimeInterval(86400)
            running = min(goal, running + vel)
            projected.append(CumulativePoint(date: cursor, total: running, isProjected: true))
            if running >= goal { break }
        }
        return actual + projected
    }

    /// Trajectoire idéale linéaire (premier jour → deadline → objectif)
    private var idealTrajectoryPoints: [IdealPoint] {
        guard showProjection,
              let projectId = selectedProjectId,
              let project   = store.data.projects.first(where: { $0.id == projectId })
        else { return [] }

        let deadline: Date?
        let goal: Int
        if let chId = selectedChapterId,
           let ch   = project.chapters.first(where: { $0.id == chId }),
           let dl   = ch.deadline, let dlDate = DataStore.parseDate(dl) {
            deadline = dlDate; goal = ch.goal
        } else {
            let nextDl = project.chapters
                .compactMap { $0.deadline.flatMap(DataStore.parseDate) }
                .filter { $0 > Date() }.sorted().first
            deadline = nextDl
            goal = project.chapters.reduce(0) { $0 + $1.goal }
        }

        guard let dl = deadline, goal > 0 else { return [] }
        let base = store.cumulativeData(projectId: selectedProjectId, chapterId: selectedChapterId)
        guard let startDate = base.first?.date else { return [] }

        let totalDays = max(1, cal.dateComponents([.day], from: startDate, to: dl).day ?? 1)
        let end = cal.startOfDay(for: dl)
        var result: [IdealPoint] = []
        var cursor = cal.startOfDay(for: startDate)
        while cursor <= end {
            let dayOffset = cal.dateComponents([.day], from: startDate, to: cursor).day ?? 0
            let ideal = Int(Double(goal) * Double(dayOffset) / Double(totalDays))
            result.append(IdealPoint(date: cursor, ideal: ideal))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private var hasProjectionData: Bool {
        guard let projectId = selectedProjectId,
              let project   = store.data.projects.first(where: { $0.id == projectId })
        else { return false }
        if let chId = selectedChapterId,
           let ch   = project.chapters.first(where: { $0.id == chId }) {
            return ch.deadline != nil && ch.goal > 0
        }
        return project.chapters.contains { $0.deadline != nil && $0.goal > 0 }
    }

    // MARK: - Monthly aggregation

    private var monthlyDataPoints: [MonthCount] {
        let totals = store.writtenTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
        var monthly: [Date: Int] = [:]
        for (dateStr, count) in totals {
            guard let date = DataStore.parseDate(dateStr) else { continue }
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: date))!
            monthly[monthStart, default: 0] += count
        }
        return monthly.keys.sorted().map { MonthCount(month: $0, count: monthly[$0]!) }
    }

    private var chapterProgressData: [ChapterProgress] {
        guard let project = selectedProject else {
            // Vue globale : un point par projet
            return store.data.projects.enumerated().map { idx, project in
                let total = project.chapters.reduce(0) { sum, ch in
                    sum + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0)
                }
                let goal = project.chapters.reduce(0) { $0 + $1.goal }
                return ChapterProgress(name: project.name, total: total, goal: goal, color: Color.chapterColor(at: idx))
            }.filter { $0.total > 0 || $0.goal > 0 }
        }
        let chapters = selectedChapterId.flatMap { id in project.chapters.filter { $0.id == id } }
                        ?? project.chapters
        return chapters.enumerated().map { idx, chapter in
            let total = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            return ChapterProgress(name: chapter.name, total: total, goal: chapter.goal,
                                   color: Color.chapterColor(at: idx))
        }
    }

    private var totalWritten: Int { lineDataPoints.reduce(0) { $0 + $1.count } }
    private var activeDays: Int   { lineDataPoints.filter { $0.count > 0 }.count }
    private var avgPerActiveDay: Int { activeDays > 0 ? totalWritten / activeDays : 0 }
    private var maxDay: Int { lineDataPoints.map(\.count).max() ?? 0 }

    private var chapterColorMap: [String: Color] {
        guard let project = selectedProject else { return [:] }
        return Dictionary(uniqueKeysWithValues:
            project.chapters.enumerated().map { ($1.name, Color.chapterColor(at: $0)) }
        )
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView
                scopeCard
                if showMonthlyView {
                    monthlyChartCard
                    monthlyStatsRow
                } else if chartType == .velocity {
                    velocityChartCard
                } else if chartType == .cumulative {
                    cumulativeChartCard
                    if showProjection { projectionStatsRow }
                } else if totalWritten == 0 && stackedDataPoints.filter({ $0.count > 0 }).isEmpty {
                    emptyState
                } else {
                    chartCard
                    statsRow
                }
                if showChapterComparison && !chapterProgressData.isEmpty {
                    chapterComparisonCard
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var headerView: some View {
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
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(
                                showSidebar ? Color.accent.opacity(0.4) : Color.glassBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 2) {
                Text("Graphiques")
                    .font(TypeScale.pageTitle)
                    .foregroundColor(.primary)
                Text(selectedProject.map { "Projet : \($0.name)" } ?? "Vue globale")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()

            // #33 — Export PNG
            Button { exportChartAsPNG() } label: {
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
                .clipShape(AppLook.buttonShape(10))
                .overlay(AppLook.buttonShape(10).stroke(
                    pngExportSuccess ? Color.accentGreen.opacity(0.4) : Color.glassBorder, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
            }
            .buttonStyle(.pressable)
            .appAnimation(.easeInOut(duration: 0.2), value: pngExportSuccess)
            .help("Exporter ce graphique en image PNG")
        }
    }

    private func exportChartAsPNG() {
        let points = lineDataPoints
        let projectName = selectedProject?.name ?? "Global"
        let typeLabel = showMonthlyView ? "mensuel" : chartType.rawValue.lowercased()
        let snapshotView = ChartSnapshotView(
            title: "\(projectName) — \(typeLabel)",
            dataPoints: points,
            period: period.rawValue
        )
        guard let pngData = renderViewToPNG(snapshotView) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        panel.nameFieldStringValue = "graphique_\(typeLabel)_\(dateTag).png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? pngData.write(to: url)
            pngExportSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pngExportSuccess = false }
        }
    }

    private func renderViewToPNG<V: View>(_ content: V) -> Data? {
        let host = NSHostingView(rootView: content)
        let size = NSSize(width: 800, height: 400)
        host.setFrameSize(size)
        host.layoutSubtreeIfNeeded()
        guard let bitmapRep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: bitmapRep)
        let nsImage = NSImage(size: size)
        nsImage.addRepresentation(bitmapRep)
        guard let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [.compressionFactor: 0.9])
    }

    // MARK: - Scope card

    private var scopeCard: some View {
        GlassCard {
            VStack(spacing: 14) {

                // Period picker
                HStack(spacing: 0) {
                    ForEach(ChartPeriod.allCases) { p in
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.2)) { period = p }
                        } label: {
                            Text(p.rawValue)
                                .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                                .foregroundColor(period == p ? .white : Color.primary.opacity(0.65))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(period == p ? Color.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))

                // Custom date pickers
                if period == .custom {
                    Divider().overlay(Color.primary.opacity(0.07))
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("DU")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.labelMuted)
                                .kerning(0.8)
                            CompactDatePicker(date: $customStart, maxDate: now)
                        }
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .padding(.top, 18)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("AU")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.labelMuted)
                                .kerning(0.8)
                            CompactDatePicker(date: $customEnd, maxDate: now)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Durée")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.labelMuted)
                            Text("\(rangeDays + 1) j")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.accent)
                        }
                        .padding(.top, 18)
                    }
                }

                Divider().overlay(Color.primary.opacity(0.07))

                // Project scope chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        scopeChip(id: nil, name: "Tous les projets", icon: "globe")
                        ForEach(store.data.projects) { project in
                            scopeChip(id: project.id, name: project.name, icon: "folder.fill")
                        }
                    }
                    .padding(.horizontal, 2)
                }

                // Chapter filter
                if let project = selectedProject, !project.chapters.isEmpty {
                    Divider().overlay(Color.primary.opacity(0.07))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chapterChip(id: nil, name: "Tous les chapitres")
                            ForEach(project.chapters) { ch in
                                chapterChip(id: ch.id, name: ch.name)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                // Chart type toggle
                Divider().overlay(Color.primary.opacity(0.07))
                HStack(spacing: 6) {
                    // "Barres" uniquement si un projet est sélectionné
                    let visibleTypes: [ChartType] = selectedProjectId != nil
                        ? ChartType.allCases
                        : ChartType.allCases.filter { $0 != .bar }
                    ForEach(visibleTypes) { type in
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.2)) {
                                chartType = type
                                if type != .cumulative { showProjection = false }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: type.icon).font(.system(size: 11))
                                Text(type.rawValue)
                                    .font(.system(size: 12, weight: chartType == type ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundColor(chartType == type ? .white : .labelMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(chartType == type ? Color.accent.opacity(0.85) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(
                                chartType == type ? Color.accent : Color.primary.opacity(0.1),
                                lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    Spacer()
                }

                // Toggle projection (seulement en mode Cumulé + deadline disponible)
                if chartType == .cumulative && hasProjectionData {
                    Divider().overlay(Color.primary.opacity(0.07))
                    HStack(spacing: 6) {
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.2)) { showProjection.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.forward.to.line").font(.system(size: 11))
                                Text("Afficher la projection")
                                    .font(.system(size: 12, weight: showProjection ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundColor(showProjection ? .white : .labelMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(showProjection ? Color.accentGreen.opacity(0.85) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(showProjection ? Color.accentGreen : Color.primary.opacity(0.1), lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        Spacer()
                    }
                }
            }

                // Comparaison période précédente
                if isComparisonAvailable {
                    Divider().overlay(Color.primary.opacity(0.07))
                    HStack(spacing: 8) {
                        Button {
                            withAppAnimation(.easeInOut(duration: 0.2)) { showComparison.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11))
                                Text("Comparer avec la période précédente")
                                    .font(.system(size: 12, weight: showComparison ? .semibold : .regular))
                                    .lineLimit(1)
                            }
                            .foregroundColor(showComparison ? .white : .labelMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(showComparison ? Color.accentWarm.opacity(0.85) : Color.primary.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(showComparison ? Color.accentWarm : Color.primary.opacity(0.1), lineWidth: 1))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.pressable)
                        Spacer()
                    }
                }

                // Extra views toggles
                Divider().overlay(Color.primary.opacity(0.07))
                HStack(spacing: 8) {
                    Button {
                        withAppAnimation(.easeInOut(duration: 0.2)) { showMonthlyView.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 11))
                            Text("Vue mensuelle")
                                .font(.system(size: 12, weight: showMonthlyView ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundColor(showMonthlyView ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(showMonthlyView ? Color.accent.opacity(0.85) : Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showMonthlyView ? Color.accent : Color.primary.opacity(0.1), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    Button {
                        withAppAnimation(.easeInOut(duration: 0.2)) { showChapterComparison.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 11))
                            Text("Comparaison chapitres")
                                .font(.system(size: 12, weight: showChapterComparison ? .semibold : .regular))
                                .lineLimit(1)
                        }
                        .foregroundColor(showChapterComparison ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(showChapterComparison ? Color.accentGreen.opacity(0.85) : Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showChapterComparison ? Color.accentGreen : Color.primary.opacity(0.1), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    Spacer()
                }
        }
    }

    private func scopeChip(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = selectedProjectId == id
        return Button {
            withAppAnimation(.easeInOut(duration: 0.2)) {
                selectedProjectId = id
                selectedChapterId = nil
                if id != nil { chartType = .line }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? Color.accent.opacity(0.85) : Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.primary.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func chapterChip(id: UUID?, name: String) -> some View {
        let isSelected = selectedChapterId == id
        return Button {
            withAppAnimation(.easeInOut(duration: 0.2)) { selectedChapterId = id }
        } label: {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .labelMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentWarm.opacity(0.85) : Color.primary.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentWarm : Color.primary.opacity(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(chartType == .bar && selectedProjectId != nil
                     ? "Caractères écrits par jour (barres empilées)"
                     : "Caractères écrits par jour")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.0)

                if chartType == .bar, selectedProjectId != nil {
                    stackedBarChart
                } else {
                    lineAreaChart
                }

                if store.data.dailyGoal > 0 && chartType == .line {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(Color.accentWarm.opacity(0.55))
                            .frame(width: 18, height: 2)
                        Text("Objectif journalier : \(formatNumber(store.data.dailyGoal)) car.")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                }
                if showComparison && chartType == .line && isComparisonAvailable {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentWarm.opacity(0.50))
                                    .frame(width: 5, height: 2)
                                Color.clear.frame(width: 3, height: 2)
                            }
                        }
                        .frame(width: 20)
                        Text("Période précédente (même durée)")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                }
            }
        }
    }

    private var lineAreaChart: some View {
        Chart {
            ForEach(lineDataPoints) { point in
                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Caractères", point.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accent.opacity(0.40), Color.accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Caractères", point.count)
                )
                .foregroundStyle(Color.accent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                if point.count > 0 {
                    PointMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Caractères", point.count)
                    )
                    .foregroundStyle(Color.accent)
                    .symbolSize(30)
                }
            }

            if store.data.dailyGoal > 0 {
                RuleMark(y: .value("Objectif", store.data.dailyGoal))
                    .foregroundStyle(Color.accentWarm.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            // Courbe fantôme — période précédente alignée sur le même axe
            if showComparison && isComparisonAvailable {
                ForEach(comparisonPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Précédent", point.count)
                    )
                    .foregroundStyle(Color.accentWarm.opacity(0.40))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(date))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.labelMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(formatNumber(n))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.labelMuted)
                    }
                }
            }
        }
        .chartPlotStyle { plot in plot.background(Color.clear) }
        .frame(height: 200)
    }

    private var stackedBarChart: some View {
        Chart {
            ForEach(stackedDataPoints) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Caractères", point.count)
                )
                .foregroundStyle(by: .value("Chapitre", point.chapterName))
            }
        }
        .chartForegroundStyleScale(
            range: (0..<max(1, selectedProject?.chapters.count ?? 1)).map { Color.chapterColor(at: $0) }
        )
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(date))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.labelMuted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text(formatNumber(n))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.labelMuted)
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .chartPlotStyle { plot in plot.background(Color.clear) }
        .frame(height: 220)
    }

    private var xStride: Calendar.Component {
        if rangeDays <= 14  { return .day }
        if rangeDays <= 90  { return .weekOfYear }
        return .month
    }

    private func xAxisLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        if rangeDays <= 14       { fmt.dateFormat = "EEE d" }
        else if rangeDays <= 90  { fmt.dateFormat = "d MMM" }
        else                     { fmt.dateFormat = "MMM yy" }
        let s = fmt.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "Total", value: formatNumber(totalWritten), unit: "car.", color: .accent)
            MiniStatCard(label: "Jours actifs", value: "\(activeDays)", unit: "/ \(daysInRange.count) j", color: .accentWarm)
            MiniStatCard(label: "Meilleur jour", value: formatNumber(maxDay), unit: "car.", color: .accentGreen)
        }
    }

    // MARK: - Monthly chart

    private var monthlyChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("CARACTÈRES PAR MOIS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.0)

                if monthlyDataPoints.isEmpty {
                    Text("Pas encore de données")
                        .font(.system(size: 13))
                        .foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    Chart {
                        ForEach(monthlyDataPoints) { point in
                            BarMark(
                                x: .value("Mois", point.month, unit: .month),
                                y: .value("Caractères", point.count)
                            )
                            .foregroundStyle(Color.accent.gradient)
                            .cornerRadius(4)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(monthAxisLabel(date))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let n = value.as(Int.self) {
                                    Text(formatNumber(n))
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { plot in plot.background(Color.clear) }
                    .frame(height: 200)
                }
            }
        }
    }

    private var monthlyStatsRow: some View {
        let points = monthlyDataPoints
        let total = points.reduce(0) { $0 + $1.count }
        let best = points.map(\.count).max() ?? 0
        let avg = points.isEmpty ? 0 : total / points.count
        return HStack(spacing: 12) {
            MiniStatCard(label: "Total", value: formatNumber(total), unit: "car.", color: .accent)
            MiniStatCard(label: "Meilleur mois", value: formatNumber(best), unit: "car.", color: .accentWarm)
            MiniStatCard(label: "Moy./mois", value: formatNumber(avg), unit: "car.", color: .accentGreen)
        }
    }

    private func monthAxisLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMM yy"
        return fmt.string(from: date)
    }

    // MARK: - Chapter comparison

    private var chapterComparisonCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(selectedProjectId != nil ? "PROGRESSION DES CHAPITRES" : "PROGRESSION DES PROJETS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.0)

                VStack(spacing: 10) {
                    ForEach(chapterProgressData) { item in
                        chapterProgressRow(item: item)
                    }
                }
            }
        }
    }

    private func chapterProgressRow(item: ChapterProgress) -> some View {
        let hasGoal = item.goal > 0
        let ratio = hasGoal ? min(1.0, Double(item.total) / Double(item.goal)) : 0
        let pct = Int(ratio * 100)
        let isComplete = hasGoal && item.total >= item.goal

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(item.color).frame(width: 7, height: 7)
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(formatNumber(item.total))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    if hasGoal {
                        Text(" / \(formatNumber(item.goal))")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text("  \(pct)%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isComplete ? .accentGreen : item.color)
                    }
                }
            }
            if hasGoal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.color.opacity(0.12))
                            .frame(height: 3)
                        if ratio > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(isComplete ? Color.accentGreen : item.color)
                                .frame(width: max(3, geo.size.width * ratio), height: 3)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
    }

    // MARK: - V5 Velocity chart

    private var velocityChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("VITESSE D'ÉCRITURE GLISSANTE · 7 JOURS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.0)
                    Text("Moyenne des jours actifs sur les 7 jours précédents")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted.opacity(0.7))
                }

                let points = velocityDataPoints
                let maxV = points.map(\.velocity).max() ?? 1
                if maxV == 0 {
                    Text("Pas encore assez de données (7 jours requis)")
                        .font(.system(size: 13)).foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Chart {
                        ForEach(points) { pt in
                            AreaMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Vitesse", pt.velocity)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentWarm.opacity(0.35), Color.accentWarm.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)

                            LineMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Vitesse", pt.velocity)
                            )
                            .foregroundStyle(Color.accentWarm)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        }
                        if store.data.dailyGoal > 0 {
                            RuleMark(y: .value("Objectif", store.data.dailyGoal))
                                .foregroundStyle(Color.accent.opacity(0.55))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                                .annotation(position: .top, alignment: .trailing) {
                                    Text("Objectif \(formatNumber(store.data.dailyGoal))")
                                        .font(.system(size: 10)).foregroundColor(.accent.opacity(0.7))
                                }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: xStride)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(xAxisLabel(date)).font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let n = value.as(Int.self) {
                                    Text(formatNumber(n)).font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { $0.background(Color.clear) }
                    .frame(height: 200)

                    // Legend
                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Rectangle().fill(Color.accentWarm).frame(width: 14, height: 2)
                            Text("Vitesse glissante 7j").font(.system(size: 11)).foregroundColor(.labelMuted)
                        }
                        if store.data.dailyGoal > 0 {
                            HStack(spacing: 5) {
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1).fill(Color.accent.opacity(0.55))
                                            .frame(width: 4, height: 2)
                                        Color.clear.frame(width: 2, height: 2)
                                    }
                                }
                                Text("Objectif journalier").font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                        }
                    }
                }

                // Current velocity summary
                let current14 = store.velocity14Days
                if current14 > 0 {
                    Divider()
                    HStack(spacing: 20) {
                        velocityStatPill(label: "Vitesse actuelle (14j)", value: formatNumber(current14) + "/j", color: .accentWarm)
                        if store.data.dailyGoal > 0 {
                            let pct = Int(Double(current14) / Double(store.data.dailyGoal) * 100)
                            velocityStatPill(label: "vs objectif", value: "\(pct)%",
                                           color: current14 >= store.data.dailyGoal ? .accentGreen : .accentWarm)
                        }
                    }
                }
            }
        }
    }

    private func velocityStatPill(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10)).foregroundColor(.labelMuted)
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(color)
        }
    }

    // MARK: - V5 Cumulative chart

    private var cumulativeChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PROGRESSION CUMULATIVE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.0)
                    Text(showProjection ? "Réel · Projection (vitesse 14j) · Trajectoire idéale" : "Total écrit depuis le début")
                        .font(.system(size: 11)).foregroundColor(.labelMuted.opacity(0.7))
                }

                let cPoints = cumulativePoints
                let iPoints = idealTrajectoryPoints
                let allY    = (cPoints.map(\.total) + iPoints.map(\.ideal))
                let maxY    = max(allY.max() ?? 1, 1)

                if cPoints.isEmpty {
                    Text("Pas encore de données")
                        .font(.system(size: 13)).foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    Chart {
                        // Trajectoire idéale (ligne grise)
                        if showProjection {
                            ForEach(iPoints) { pt in
                                LineMark(
                                    x: .value("Date", pt.date, unit: .day),
                                    y: .value("Idéal", pt.ideal)
                                )
                                .foregroundStyle(Color.primary.opacity(0.25))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                .interpolationMethod(.linear)
                            }
                        }

                        // Réel + projection
                        ForEach(cPoints) { pt in
                            if !pt.isProjected {
                                AreaMark(
                                    x: .value("Date", pt.date, unit: .day),
                                    y: .value("Total", pt.total)
                                )
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.accent.opacity(0.35), Color.accent.opacity(0.02)],
                                        startPoint: .top, endPoint: .bottom
                                    )
                                )
                                .interpolationMethod(.linear)

                                LineMark(
                                    x: .value("Date", pt.date, unit: .day),
                                    y: .value("Total", pt.total)
                                )
                                .foregroundStyle(Color.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.linear)
                            } else {
                                LineMark(
                                    x: .value("Date", pt.date, unit: .day),
                                    y: .value("Total", pt.total)
                                )
                                .foregroundStyle(Color.accentGreen.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                                .interpolationMethod(.linear)
                            }
                        }

                        // Ligne d'objectif
                        if let goal = cumulativeGoal, goal > 0 {
                            RuleMark(y: .value("Objectif", goal))
                                .foregroundStyle(Color.accentWarm.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(cumulativeAxisLabel(date)).font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.primary.opacity(0.06))
                            AxisValueLabel {
                                if let n = value.as(Int.self) {
                                    Text(formatNumber(n)).font(.system(size: 10))
                                        .foregroundStyle(Color.labelMuted)
                                }
                            }
                        }
                    }
                    .chartPlotStyle { $0.background(Color.clear) }
                    .frame(height: 220)

                    // Légende
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Rectangle().fill(Color.accent).frame(width: 14, height: 2)
                            Text("Réel").font(.system(size: 11)).foregroundColor(.labelMuted)
                        }
                        if showProjection {
                            HStack(spacing: 5) {
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1).fill(Color.accentGreen.opacity(0.7))
                                            .frame(width: 4, height: 2)
                                        Color.clear.frame(width: 2, height: 2)
                                    }
                                }
                                Text("Projection").font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                            HStack(spacing: 5) {
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1).fill(Color.primary.opacity(0.25))
                                            .frame(width: 4, height: 2)
                                        Color.clear.frame(width: 2, height: 2)
                                    }
                                }
                                Text("Idéal").font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                        }
                        if let goal = cumulativeGoal, goal > 0 {
                            HStack(spacing: 5) {
                                HStack(spacing: 2) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 1).fill(Color.accentWarm.opacity(0.5))
                                            .frame(width: 4, height: 2)
                                        Color.clear.frame(width: 2, height: 2)
                                    }
                                }
                                Text("Objectif \(formatNumber(goal))").font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                        }
                    }
                }
            }
        }
    }

    private var cumulativeGoal: Int? {
        guard let pid = selectedProjectId,
              let project = store.data.projects.first(where: { $0.id == pid }) else { return nil }
        if let chId = selectedChapterId,
           let ch   = project.chapters.first(where: { $0.id == chId }) {
            return ch.goal > 0 ? ch.goal : nil
        }
        let totalGoal = project.chapters.reduce(0) { $0 + $1.goal }
        return totalGoal > 0 ? totalGoal : nil
    }

    private var projectionStatsRow: some View {
        let vel = store.velocity14Days
        let current = cumulativePoints.last(where: { !$0.isProjected })?.total ?? 0
        let goal = cumulativeGoal ?? 0
        let remaining = max(0, goal - current)
        let daysToFinish: Int? = vel > 0 && remaining > 0 ? Int(ceil(Double(remaining) / Double(vel))) : nil
        return HStack(spacing: 12) {
            MiniStatCard(label: "Total écrit", value: formatNumber(current), unit: "car.", color: .accent)
            if goal > 0 {
                MiniStatCard(label: "Restant", value: formatNumber(remaining), unit: "car.", color: .accentWarm)
            }
            if let d = daysToFinish {
                MiniStatCard(label: "Fin estimée", value: "\(d) j", unit: "à ce rythme", color: .accentGreen)
            }
        }
    }

    private func cumulativeAxisLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 40))
                    .foregroundColor(.labelMuted.opacity(0.5))
                VStack(spacing: 4) {
                    Text("Aucune donnée pour cette période")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Les graphiques apparaîtront dès ta première saisie.")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Mini stat card

struct MiniStatCard: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 5) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.0)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chart Snapshot View for PNG export (#33)

struct ChartSnapshotView: View {
    let title: String
    let dataPoints: [DayCount]
    let period: String

    private static let bg     = Color(red: 0.07, green: 0.07, blue: 0.10)
    private static let accent = Color(red: 0.247, green: 0.502, blue: 0.965)

    private var total: Int { dataPoints.reduce(0) { $0 + $1.count } }
    private var best: Int  { dataPoints.map(\.count).max() ?? 0 }
    private var active: Int { dataPoints.filter { $0.count > 0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header band
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold, design: AppLook.fontDesign))
                        .foregroundColor(.white)
                    Text("Période : \(period)  ·  Total : \(DataStore.formatNumber(total)) car.  ·  Jours actifs : \(active)")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Meilleur jour").font(.system(size: 10)).foregroundColor(.white.opacity(0.4))
                    Text(DataStore.formatNumber(best) + " car.")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(Self.accent)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .background(Self.bg)

            // Bars
            let maxVal = best > 0 ? best : 1
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(dataPoints) { pt in
                    let ratio = Double(pt.count) / Double(maxVal)
                    let h = max(3.0, 120.0 * ratio)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(pt.count > 0
                              ? Self.accent.opacity(0.35 + 0.65 * ratio)
                              : Color.white.opacity(0.05))
                        .frame(maxWidth: .infinity, minHeight: 3, maxHeight: CGFloat(h))
                }
            }
            .frame(height: 120)
            .padding(.horizontal, 24).padding(.vertical, 20)
            .background(Self.bg.opacity(0.95))

            // Footer
            HStack {
                Text("ThesisTracker · Ebbcent")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
                Spacer()
                Text(DataStore.today)
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.25))
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
            .background(Self.bg.opacity(0.95))
        }
        .frame(width: 800)
        .background(Self.bg)
    }
}
