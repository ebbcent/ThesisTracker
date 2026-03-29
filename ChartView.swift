import SwiftUI
import Charts

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
    case line = "Courbe"
    case bar  = "Barres"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .line: return "chart.line.uptrend.xyaxis"
        case .bar:  return "chart.bar.fill"
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

struct ProjectionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
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
    @State private var showCumulativeView: Bool = false

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
        let totals = store.dailyTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
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
            (chapter.id, store.dailyTotals(projectId: project.id, chapterId: chapter.id))
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
        let totals = store.dailyTotals(projectId: selectedProjectId, chapterId: selectedChapterId)

        return zip(daysInRange, previousDates).map { currentDate, previousDate in
            let previousDateString = DataStore.dateString(from: previousDate)
            return ComparisonPoint(date: currentDate, count: totals[previousDateString] ?? 0)
        }
    }

    // MARK: - Cumulative data

    private var cumulativeDataPoints: [DayCount] {
        let totals = store.dailyTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
        var running = 0
        return daysInRange.map { date in
            let dateStr = DataStore.dateString(from: date)
            running += totals[dateStr] ?? 0
            return DayCount(date: date, count: running)
        }
    }

    // MARK: - Monthly aggregation

    private var monthlyDataPoints: [MonthCount] {
        let totals = store.dailyTotals(projectId: selectedProjectId, chapterId: selectedChapterId)
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
                    sum + (ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0)
                }
                let goal = project.chapters.reduce(0) { $0 + $1.goal }
                return ChapterProgress(name: project.name, total: total, goal: goal, color: Color.chapterColor(at: idx))
            }.filter { $0.total > 0 || $0.goal > 0 }
        }
        let chapters = selectedChapterId.flatMap { id in project.chapters.filter { $0.id == id } }
                        ?? project.chapters
        return chapters.enumerated().map { idx, chapter in
            let total = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
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

    // MARK: - Deadline projection

    private var deadlineProjectionPoints: [ProjectionPoint] {
        var chapter: Chapter? = nil
        var currentTotal = 0
        if let selChapterId = selectedChapterId,
           let proj = selectedProject,
           let ch = proj.chapters.first(where: { $0.id == selChapterId }),
           ch.deadline != nil, ch.goal > 0 {
            chapter = ch
            currentTotal = ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
        } else if let proj = selectedProject {
            chapter = proj.chapters.first(where: { $0.deadline != nil && $0.goal > 0 })
            if let ch = chapter {
                currentTotal = ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
            }
        }
        guard let ch = chapter,
              let deadlineStr = ch.deadline,
              let deadline = DataStore.parseDate(deadlineStr),
              deadline > Date() else { return [] }
        return [
            ProjectionPoint(date: Date(), count: currentTotal),
            ProjectionPoint(date: deadline, count: ch.goal)
        ]
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
                } else if showCumulativeView {
                    cumulativeChartCard
                    statsRow
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(showSidebar ? Color.accent.opacity(0.15) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                showSidebar ? Color.accent.opacity(0.4) : Color.glassBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Graphiques")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(selectedProject.map { "Projet : \($0.name)" } ?? "Vue globale")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
        }
    }

    // MARK: - Scope card

    private var scopeCard: some View {
        GlassCard {
            VStack(spacing: 14) {

                // Period picker
                HStack(spacing: 0) {
                    ForEach(ChartPeriod.allCases) { p in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { period = p }
                        } label: {
                            Text(p.rawValue)
                                .font(.system(size: 12, weight: period == p ? .semibold : .regular))
                                .foregroundColor(period == p ? .white : Color.primary.opacity(0.65))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(period == p ? Color.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.black.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Custom date pickers
                if period == .custom {
                    Divider().overlay(Color.white.opacity(0.07))
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("DU")
                                .font(.system(size: 9, weight: .bold))
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
                                .font(.system(size: 9, weight: .bold))
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

                Divider().overlay(Color.white.opacity(0.07))

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
                    Divider().overlay(Color.white.opacity(0.07))
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
                if selectedProjectId != nil {
                    Divider().overlay(Color.white.opacity(0.07))
                    HStack(spacing: 6) {
                        ForEach(ChartType.allCases) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { chartType = type }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: type.icon).font(.system(size: 11))
                                    Text(type.rawValue)
                                        .font(.system(size: 12, weight: chartType == type ? .semibold : .regular))
                                }
                                .foregroundColor(chartType == type ? .white : .labelMuted)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(chartType == type ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    chartType == type ? Color.accent : Color.white.opacity(0.1),
                                    lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
            }

                // Comparaison période précédente
                if isComparisonAvailable {
                    Divider().overlay(Color.white.opacity(0.07))
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showComparison.toggle() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.system(size: 11))
                                Text("Comparer avec la période précédente")
                                    .font(.system(size: 12, weight: showComparison ? .semibold : .regular))
                            }
                            .foregroundColor(showComparison ? .white : .labelMuted)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(showComparison ? Color.accentWarm.opacity(0.85) : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(showComparison ? Color.accentWarm : Color.white.opacity(0.1), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }

                // Extra views toggles
                Divider().overlay(Color.white.opacity(0.07))
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showMonthlyView.toggle()
                            if showMonthlyView { showCumulativeView = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 11))
                            Text("Vue mensuelle")
                                .font(.system(size: 12, weight: showMonthlyView ? .semibold : .regular))
                        }
                        .foregroundColor(showMonthlyView ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(showMonthlyView ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showMonthlyView ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCumulativeView.toggle()
                            if showCumulativeView { showMonthlyView = false }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                                .font(.system(size: 11))
                            Text("Vue cumulative")
                                .font(.system(size: 12, weight: showCumulativeView ? .semibold : .regular))
                        }
                        .foregroundColor(showCumulativeView ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(showCumulativeView ? Color.insightPurple.opacity(0.85) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showCumulativeView ? Color.insightPurple : Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showChapterComparison.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.bar.doc.horizontal")
                                .font(.system(size: 11))
                            Text("Comparaison chapitres")
                                .font(.system(size: 12, weight: showChapterComparison ? .semibold : .regular))
                        }
                        .foregroundColor(showChapterComparison ? .white : .labelMuted)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(showChapterComparison ? Color.accentGreen.opacity(0.85) : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(showChapterComparison ? Color.accentGreen : Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
        }
    }

    private func scopeChip(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = selectedProjectId == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedProjectId = id
                selectedChapterId = nil
                if id != nil { chartType = .line }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func chapterChip(id: UUID?, name: String) -> some View {
        let isSelected = selectedChapterId == id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedChapterId = id }
        } label: {
            Text(name)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .labelMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSelected ? Color.accentWarm.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentWarm : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                if chartType == .line && !deadlineProjectionPoints.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentWarm.opacity(0.70))
                                    .frame(width: 5, height: 2)
                                Color.clear.frame(width: 3, height: 2)
                            }
                        }
                        .frame(width: 20)
                        Text("Trajectoire vers deadline")
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
            // Projection vers deadline
            if !deadlineProjectionPoints.isEmpty {
                ForEach(deadlineProjectionPoints) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Projection", point.count)
                    )
                    .foregroundStyle(Color.accentWarm.opacity(0.70))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .interpolationMethod(.linear)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: xStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.06))
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
                    .foregroundStyle(Color.white.opacity(0.06))
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
                    .foregroundStyle(Color.white.opacity(0.06))
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
                    .foregroundStyle(Color.white.opacity(0.06))
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
            if showCumulativeView {
                let total = cumulativeDataPoints.last?.count ?? 0
                MiniStatCard(label: "Total cumulé", value: formatNumber(total), unit: "car.", color: .insightPurple)
                MiniStatCard(label: "Jours actifs", value: "\(activeDays)", unit: "/ \(daysInRange.count) j", color: .accentWarm)
                MiniStatCard(label: "Moy./jour actif", value: formatNumber(avgPerActiveDay), unit: "car.", color: .accent)
            } else {
                MiniStatCard(label: "Total", value: formatNumber(totalWritten), unit: "car.", color: .accent)
                MiniStatCard(label: "Jours actifs", value: "\(activeDays)", unit: "/ \(daysInRange.count) j", color: .accentWarm)
                MiniStatCard(label: "Meilleur jour", value: formatNumber(maxDay), unit: "car.", color: .accentGreen)
                MiniStatCard(label: "Moy./jour actif", value: formatNumber(avgPerActiveDay), unit: "car.", color: .insightPurple)
            }
        }
    }

    // MARK: - Cumulative chart

    private var cumulativeChartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("PROGRESSION CUMULATIVE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(1.0)

                Chart {
                    ForEach(cumulativeDataPoints) { point in
                        AreaMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Total", point.count)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.insightPurple.opacity(0.40), Color.insightPurple.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.monotone)

                        LineMark(
                            x: .value("Date", point.date, unit: .day),
                            y: .value("Total", point.count)
                        )
                        .foregroundStyle(Color.insightPurple)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    }
                    // Projection vers deadline
                    if !deadlineProjectionPoints.isEmpty {
                        ForEach(deadlineProjectionPoints) { point in
                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Projection", point.count)
                            )
                            .foregroundStyle(Color.accentWarm.opacity(0.70))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .interpolationMethod(.linear)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: xStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
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
                            .foregroundStyle(Color.white.opacity(0.06))
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

                if !deadlineProjectionPoints.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            ForEach(0..<3) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Color.accentWarm.opacity(0.70))
                                    .frame(width: 5, height: 2)
                                Color.clear.frame(width: 3, height: 2)
                            }
                        }
                        .frame(width: 20)
                        Text("Trajectoire vers deadline")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                }
            }
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
                                .foregroundStyle(Color.white.opacity(0.06))
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
                                .foregroundStyle(Color.white.opacity(0.06))
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

    // MARK: - Empty state

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 14) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucune donnée pour cette période")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
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
                    .font(.system(size: 9, weight: .bold))
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
