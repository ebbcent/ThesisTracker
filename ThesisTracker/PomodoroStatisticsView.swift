import Charts
import SwiftUI

struct PomodoroStatisticsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var controller: PomodoroAppController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Statistiques")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                        Text(periodTitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button("Aujourd'hui") { controller.jumpStatisticsAnchorToToday() }
                            .buttonStyle(CockpitButtonStyle())
                        Button { controller.shiftStatisticsAnchor(by: -1) } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(CockpitButtonStyle())
                        .help("Période précédente")
                        .accessibilityLabel("Période précédente")
                        Button { controller.shiftStatisticsAnchor(by: 1) } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(CockpitButtonStyle())
                        .help("Période suivante")
                        .accessibilityLabel("Période suivante")
                        Picker("Période", selection: $controller.selectedRange) {
                            ForEach(PomodoroStatisticsRange.allCases) { range in
                                Text(range.frenchLabel).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 280)
                    }
                }

                InfoCard(title: "Concentration", systemImage: "chart.xyaxis.line") {
                    Chart(controller.chartMetrics) { metric in
                        BarMark(
                            x: .value("Période", metric.label),
                            y: .value("Minutes", metric.minutes)
                        )
                        .foregroundStyle(proBarColor.opacity(0.75))
                        .cornerRadius(4)

                        LineMark(
                            x: .value("Période", metric.label),
                            y: .value("Sessions", metric.sessions * 25)
                        )
                        .foregroundStyle(proLineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .symbol(.circle)
                        .symbolSize(28)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(CockpitTheme.stroke(for: colorScheme))
                            AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
                            AxisValueLabel()
                                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                                .font(.system(size: 11, design: .rounded))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic) {
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(CockpitTheme.stroke(for: colorScheme))
                            AxisValueLabel()
                                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                                .font(.system(size: 11, design: .rounded))
                        }
                    }
                    .frame(height: 240)

                    HStack(spacing: 18) {
                        legendDot(color: proBarColor, label: "Minutes de concentration")
                        legendDot(color: proLineColor, label: "Sessions (×25 min)")
                    }
                    .padding(.top, 4)
                }

                HStack(alignment: .top, spacing: 20) {
                    contributionCard
                    distributionCard
                }

                FocusQualityCard()
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [CockpitTheme.backgroundTop(for: colorScheme), CockpitTheme.backgroundBottom(for: colorScheme)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }

    private var contributionCard: some View {
        InfoCard(title: "Activité annuelle", systemImage: "calendar") {
            Text("Cliquer sur un jour ouvre le journal filtré.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(13), spacing: 4), count: 20), spacing: 4) {
                ForEach(controller.contributionCells) { cell in
                    Button {
                        controller.selectContributionDay(cell.date)
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(contributionColor(for: cell.intensity))
                            .frame(width: 13, height: 13)
                    }
                    .buttonStyle(.plain)
                    .help("\(cell.date.formatted(date: .abbreviated, time: .omitted)) : \(cell.minutes) min")
                }
            }
        }
    }

    private var distributionCard: some View {
        VStack(spacing: 20) {
            InfoCard(title: "Par jour de semaine", systemImage: "calendar.day.timeline.left") {
                Chart(controller.weekdayDistribution) { bucket in
                    BarMark(
                        x: .value("Jour", bucket.label),
                        y: .value("Minutes", bucket.minutes)
                    )
                    .foregroundStyle(proMutedColor.opacity(0.70))
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks {
                        AxisValueLabel()
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(CockpitTheme.stroke(for: colorScheme))
                        AxisValueLabel()
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .frame(height: 160)
            }

            InfoCard(title: "Par heure de la journée", systemImage: "clock") {
                Chart(controller.hourlyDistribution) { bucket in
                    AreaMark(
                        x: .value("Heure", bucket.label),
                        y: .value("Minutes", bucket.minutes)
                    )
                    .foregroundStyle(proLineColor.opacity(0.12))

                    LineMark(
                        x: .value("Heure", bucket.label),
                        y: .value("Minutes", bucket.minutes)
                    )
                    .foregroundStyle(proLineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 4)) {
                        AxisValueLabel()
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(CockpitTheme.stroke(for: colorScheme))
                        AxisValueLabel()
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                            .font(.system(size: 11, design: .rounded))
                    }
                }
                .frame(height: 160)
            }
        }
    }

    private var proBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.58, blue: 0.80)
            : Color(red: 0.28, green: 0.43, blue: 0.68)
    }

    private var proLineColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.72, blue: 0.90)
            : Color(red: 0.18, green: 0.38, blue: 0.62)
    }

    private var proMutedColor: Color {
        colorScheme == .dark
            ? Color(red: 0.42, green: 0.55, blue: 0.52)
            : Color(red: 0.26, green: 0.43, blue: 0.40)
    }

    private func contributionColor(for intensity: Double) -> Color {
        colorScheme == .dark
            ? Color(red: 0.40, green: 0.55, blue: 0.78).opacity(max(0.08, intensity))
            : Color(red: 0.18, green: 0.36, blue: 0.60).opacity(max(0.08, intensity))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
        }
    }

    private var periodTitle: String {
        switch controller.selectedRange {
        case .daily:
            return controller.statisticsAnchorDate.formatted(date: .complete, time: .omitted)
        case .weekly:
            let week = Calendar.current.dateInterval(of: .weekOfYear, for: controller.statisticsAnchorDate)
            let start = week?.start.formatted(date: .abbreviated, time: .omitted) ?? ""
            let end = week?.end.addingTimeInterval(-86400).formatted(date: .abbreviated, time: .omitted) ?? ""
            return "Semaine du \(start) au \(end)"
        case .monthly:
            return controller.statisticsAnchorDate.formatted(.dateTime.month(.wide).year())
        case .yearly:
            return controller.statisticsAnchorDate.formatted(.dateTime.year())
        }
    }
}
