import SwiftUI

// MARK: - Heatmap par chapitre (#6)

/// Visualise la répartition du travail sur les 6 derniers mois, chapitre par chapitre.
/// Révèle les chapitres qui stagnent et ceux où va vraiment le temps.
struct ChapterHeatmapWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var project: Project? { store.activeProject }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.semSky.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.semSky)
                    }
                    Text("Heatmap par chapitre")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { showSheet = true } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.pressable)
                    .help("Voir en grand")
                    .accessibilityLabel("Voir en grand")
                }

                if let project, !project.chapters.isEmpty {
                    miniMatrix(project: project, days: 56)
                    HStack(spacing: 6) {
                        Text("8 sem.")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted.opacity(0.6))
                        Spacer()
                        legendCell(0); legendCell(1); legendCell(2); legendCell(3); legendCell(4)
                    }
                } else {
                    Text("Aucun chapitre dans le projet actif")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            ChapterHeatmapSheet(store: store)
        }
    }

    @ViewBuilder
    private func miniMatrix(project: Project, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(project.chapters.prefix(6)) { chapter in
                chapterRow(project: project, chapter: chapter, days: days, compact: true)
            }
            if project.chapters.count > 6 {
                Text("+ \(project.chapters.count - 6) chapitre\(project.chapters.count - 6 > 1 ? "s" : "")")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted.opacity(0.7))
            }
        }
    }

    private func legendCell(_ level: Int) -> some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(heatColor(level: level))
            .frame(width: 8, height: 8)
    }

    fileprivate func chapterRow(project: Project, chapter: Chapter, days: Int, compact: Bool) -> some View {
        let totals = store.dailyTotals(projectId: project.id, chapterId: chapter.id)
        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())
        let nameWidth: CGFloat = compact ? 70 : 130

        return HStack(spacing: 4) {
            Text(chapter.name)
                .font(.system(size: compact ? 9 : 11))
                .foregroundColor(.labelMuted)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 1) {
                ForEach(0..<days, id: \.self) { offset in
                    let date = cal.date(byAdding: .day, value: -(days - 1 - offset), to: today) ?? today
                    let dateStr = DataStore.dateString(from: date)
                    let value = totals[dateStr] ?? 0
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(heatColor(level: bucket(for: value, goal: chapter.goal)))
                        .frame(width: compact ? 4 : 9, height: compact ? 8 : 14)
                        .help("\(dateStr) · \(value.formatted()) signes")
                }
            }
        }
    }

    fileprivate func bucket(for value: Int, goal: Int) -> Int {
        if value <= 0 { return 0 }
        let ratio = goal > 0 ? Double(value) / Double(goal) * 7.0 : Double(value) / 1500.0
        if ratio >= 1.0 { return 4 }
        if ratio >= 0.5 { return 3 }
        if ratio >= 0.2 { return 2 }
        return 1
    }

    fileprivate func heatColor(level: Int) -> Color {
        let base = Color.semSky
        switch level {
        case 0: return Color.labelMuted.opacity(0.10)
        case 1: return base.opacity(0.25)
        case 2: return base.opacity(0.50)
        case 3: return base.opacity(0.75)
        case 4: return base
        default: return base
        }
    }
}

// MARK: - Sheet plein écran

struct ChapterHeatmapSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var rangeDays: Int = 84

    private var project: Project? { store.activeProject }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let project, !project.chapters.isEmpty {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(project.chapters) { chapter in
                            sheetChapterRow(project: project, chapter: chapter)
                        }
                    }
                    .padding(20)
                }
            } else {
                Text("Aucun chapitre")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundColor(.labelMuted)
            }
        }
        .sheetFrame(width: 880, height: 580)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Heatmap par chapitre").font(.system(size: 16, weight: .semibold))
                Text("\(project?.name ?? "") · \(rangeDays) jours")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Picker("", selection: $rangeDays) {
                Text("4 sem").tag(28)
                Text("8 sem").tag(56)
                Text("12 sem").tag(84)
                Text("6 mois").tag(180)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func sheetChapterRow(project: Project, chapter: Chapter) -> some View {
        let totals = store.dailyTotals(projectId: project.id, chapterId: chapter.id)
        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())

        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                let totalChars = totals.values.reduce(0, +)
                Text("\(totalChars.formatted()) car. sur la période")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
            .frame(width: 160, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(0..<rangeDays, id: \.self) { offset in
                    let date = cal.date(byAdding: .day, value: -(rangeDays - 1 - offset), to: today) ?? today
                    let dateStr = DataStore.dateString(from: date)
                    let value = totals[dateStr] ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(value: value, goal: chapter.goal))
                        .frame(width: rangeDays > 120 ? 4 : 7, height: 14)
                        .help("\(dateStr) · \(value.formatted()) signes")
                }
            }
        }
    }

    private func heatColor(value: Int, goal: Int) -> Color {
        let base = Color.semSky
        if value <= 0 { return Color.labelMuted.opacity(0.10) }
        let ratio = goal > 0 ? Double(value) / Double(goal) * 7.0 : Double(value) / 1500.0
        if ratio >= 1.0 { return base }
        if ratio >= 0.5 { return base.opacity(0.75) }
        if ratio >= 0.2 { return base.opacity(0.50) }
        return base.opacity(0.25)
    }
}
