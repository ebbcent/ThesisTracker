import SwiftUI
import AppKit

// MARK: - Mode Présentation (#34)
// Plein écran minimaliste avec les stats clés, pour une réunion de suivi avec le directeur.

struct PresentationView: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool

    @State private var currentSlide: Int = 0

    private static let bg      = Color(red: 0.04, green: 0.04, blue: 0.08)
    private static let accent  = Color(red: 0.961, green: 0.620, blue: 0.043)
    private static let blue    = Color(red: 0.247, green: 0.502, blue: 0.965)
    private static let green   = Color(red: 0.196, green: 0.784, blue: 0.549)

    // MARK: - Computed data

    private var activeProject: Project? {
        store.data.projects.first(where: { $0.id == store.data.activeProjectId })
            ?? store.data.projects.first
    }

    private var totalCharsAllProjects: Int {
        store.data.projects.flatMap { $0.chapters }.compactMap { ch in
            ch.entries.max(by: { $0.date < $1.date })?.totalCount
        }.reduce(0, +)
    }

    private var globalGoalTotal: Int {
        store.data.projects.flatMap { $0.chapters }.reduce(0) { $0 + $1.goal }
    }

    private var globalWrittenTotal: Int {
        store.data.projects.flatMap { $0.chapters }.compactMap { ch in
            ch.entries.max(by: { $0.date < $1.date })?.totalCount
        }.reduce(0, +)
    }

    private var globalRatio: Double {
        globalGoalTotal > 0 ? min(1.0, Double(globalWrittenTotal) / Double(globalGoalTotal)) : 0
    }

    private var allChapterSummaries: [(project: String, chapter: String, total: Int, goal: Int, pct: Int, status: ChapterStatus?)] {
        store.data.projects.flatMap { project in
            project.chapters.map { ch in
                let latest = ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                let pct = ch.goal > 0 ? min(100, Int(Double(latest) / Double(ch.goal) * 100)) : -1
                return (project.name, ch.name, latest, ch.goal, pct, ch.status)
            }
        }
    }

    private var upcomingMilestones: [(title: String, date: String, project: String)] {
        store.data.projects.flatMap { p in
            p.milestones.filter { !$0.isCompleted }.compactMap { m -> (String, String, String)? in
                guard DataStore.parseDate(m.date) != nil else { return nil }
                return (m.title, m.date, p.name)  // store raw yyyy-MM-dd for sorting/parsing
            }
        }
        .sorted { $0.date < $1.date }
    }

    private var last30DaysTotals: [(date: String, value: Int)] {
        let cal = Calendar.current
        return (0..<30).reversed().compactMap { offset -> (String, Int)? in
            guard let d = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let str = DataStore.dateString(from: d)
            let val = store.dailyTotals()[str] ?? 0
            return (str, val)
        }
    }

    private var slides: [Int] { [0, 1, 2] } // 0: global, 1: chapters, 2: milestones

    private var slideTitles: [String] { ["Vue d'ensemble", "Chapitres", "Jalons"] }

    // MARK: - Body

    var body: some View {
        ZStack {
            Self.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                // Slide content
                ZStack {
                    if currentSlide == 0 { overviewSlide.transition(.opacity) }
                    if currentSlide == 1 { chaptersSlide.transition(.opacity) }
                    if currentSlide == 2 { milestonesSlide.transition(.opacity) }
                }
                .animation(.easeInOut(duration: 0.35), value: currentSlide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom nav
                bottomNav
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onKeyPress(.escape) { isPresented = false; return .handled }
        .onKeyPress(.leftArrow) {
            withAnimation { if currentSlide > 0 { currentSlide -= 1 } }
            return .handled
        }
        .onKeyPress(.rightArrow) {
            withAnimation { if currentSlide < slides.count - 1 { currentSlide += 1 } }
            return .handled
        }
        .focusable()
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            // Close
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Quitter le mode présentation (⎋)")

            Spacer()

            // Slide tabs
            HStack(spacing: 4) {
                ForEach(slides, id: \.self) { idx in
                    Button { withAnimation { currentSlide = idx } } label: {
                        Text(slideTitles[idx])
                            .font(.system(size: 12, weight: currentSlide == idx ? .semibold : .regular))
                            .foregroundColor(currentSlide == idx ? .white : .white.opacity(0.35))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(currentSlide == idx ? Color.white.opacity(0.12) : Color.clear)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Date
            Text(generatedAt)
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.25))
        }
        .padding(.horizontal, 32).padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Slide 0: Vue d'ensemble

    private var overviewSlide: some View {
        VStack(spacing: 36) {
            // Project name
            VStack(spacing: 6) {
                Text("PROGRESSION GLOBALE")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Self.accent.opacity(0.7)).kerning(2)
                Text(activeProject?.name ?? "Tous les projets")
                    .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            .padding(.top, 20)

            // Big stats row
            HStack(spacing: 20) {
                bigStatCard(
                    icon: "text.cursor",
                    label: "Total écrit",
                    value: DataStore.formatNumber(globalWrittenTotal),
                    sub: "car.",
                    color: Self.accent
                )
                if globalGoalTotal > 0 {
                    bigStatCard(
                        icon: "target",
                        label: "Progression",
                        value: "\(Int(globalRatio * 100))",
                        sub: "%",
                        color: globalRatio >= 1 ? Self.green : Self.blue
                    )
                }
                bigStatCard(
                    icon: "flame.fill",
                    label: "Série",
                    value: "\(store.currentStreak)",
                    sub: "jours",
                    color: Color(red: 0.961, green: 0.455, blue: 0.114)
                )
                bigStatCard(
                    icon: "bolt.fill",
                    label: "Vitesse 14 j",
                    value: DataStore.formatNumber(store.velocity14Days),
                    sub: "car./j",
                    color: Color(red: 0.706, green: 0.502, blue: 0.984)
                )
            }
            .padding(.horizontal, 60)

            // Global progress bar
            if globalGoalTotal > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Objectif global")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.5))
                        Spacer()
                        Text("\(DataStore.formatNumber(globalWrittenTotal)) / \(DataStore.formatNumber(globalGoalTotal)) car.")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.white.opacity(0.07))
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 6)
                                .fill(LinearGradient(
                                    colors: globalRatio >= 1
                                        ? [Self.green, Self.green.opacity(0.6)]
                                        : [Self.accent, Self.accent.opacity(0.5)],
                                    startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * CGFloat(globalRatio), height: 12)
                        }
                    }
                    .frame(height: 12)
                }
                .padding(.horizontal, 60)
            }

            // Mini activity bars (30 days)
            let bars = last30DaysTotals
            let maxVal = bars.map(\.value).max() ?? 1
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(bars, id: \.date) { item in
                    let ratio = Double(item.value) / Double(maxVal)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.value > 0 ? Self.accent.opacity(0.3 + 0.7 * ratio) : Color.white.opacity(0.05))
                        .frame(maxWidth: .infinity, minHeight: 3, maxHeight: max(3, 60 * ratio))
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 60)
        }
    }

    // MARK: - Slide 1: Chapitres

    private var chaptersSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("CHAPITRES")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Self.accent.opacity(0.7)).kerning(2)
                    .padding(.top, 20)

                ForEach(Array(allChapterSummaries.enumerated()), id: \.offset) { idx, ch in
                    chapterRow(ch, colorIdx: idx)
                }
            }
            .padding(.horizontal, 60).padding(.bottom, 30)
        }
    }

    private func chapterRow(_ ch: (project: String, chapter: String, total: Int, goal: Int, pct: Int, status: ChapterStatus?), colorIdx: Int) -> some View {
        let ratio = ch.goal > 0 ? min(1.0, Double(ch.total) / Double(ch.goal)) : 0
        let isComplete = ratio >= 1.0 || ch.status == .termine
        let color: Color = isComplete ? Self.green : Color.chapterColor(at: colorIdx)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Status dot
                Circle()
                    .fill(isComplete ? Self.green : (ch.status == .redaction ? Self.accent : Color.white.opacity(0.25)))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.chapter)
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(.white)
                    Text(ch.project)
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                if ch.goal > 0 {
                    Text("\(ch.pct)%")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(isComplete ? Self.green : color)
                    Text("\(DataStore.formatNumber(ch.total)) / \(DataStore.formatNumber(ch.goal)) car.")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                } else {
                    Text(DataStore.formatNumber(ch.total) + " car.")
                        .font(.system(size: 13, design: .monospaced)).foregroundColor(.white.opacity(0.5))
                }
            }
            if ch.goal > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isComplete ? Self.green : color)
                            .frame(width: geo.size.width * CGFloat(ratio), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    // MARK: - Slide 2: Jalons

    private var milestonesSlide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("JALONS À VENIR")
                    .font(.system(size: 11, weight: .semibold)).foregroundColor(Self.accent.opacity(0.7)).kerning(2)
                    .padding(.top, 20)

                if upcomingMilestones.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36)).foregroundColor(Self.green)
                        Text("Aucun jalon à venir")
                            .font(.system(size: 16)).foregroundColor(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ForEach(Array(upcomingMilestones.enumerated()), id: \.offset) { idx, milestone in
                        milestoneRow(milestone)
                    }
                }
            }
            .padding(.horizontal, 60).padding(.bottom, 30)
        }
    }

    private func milestoneRow(_ m: (title: String, date: String, project: String)) -> some View {
        let parsedDate = DataStore.parseDate(m.date)
        let daysLeft: Int = {
            guard let d = parsedDate else { return 999 }
            return Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 999
        }()
        let displayDate = parsedDate.map { DataStore.formatDate($0) } ?? m.date
        let urgency: Color = daysLeft < 7 ? Color(red: 0.9, green: 0.3, blue: 0.2) :
                             daysLeft < 30 ? Self.accent : Self.green

        return HStack(spacing: 16) {
            VStack(spacing: 4) {
                Circle().fill(urgency).frame(width: 10, height: 10)
                if daysLeft >= 0 {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 30)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(m.title)
                    .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                HStack(spacing: 8) {
                    Text(displayDate)
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    Text("·").foregroundColor(.white.opacity(0.2))
                    Text(m.project)
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
                    if daysLeft >= 0 {
                        Text("·").foregroundColor(.white.opacity(0.2))
                        Text("dans \(daysLeft) j")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(urgency)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(urgency.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Bottom nav

    private var bottomNav: some View {
        HStack {
            Button {
                withAnimation { if currentSlide > 0 { currentSlide -= 1 } }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(currentSlide > 0 ? .white.opacity(0.7) : .white.opacity(0.15))
            }
            .buttonStyle(.plain)
            .disabled(currentSlide == 0)

            Spacer()

            // Dot indicators
            HStack(spacing: 8) {
                ForEach(slides, id: \.self) { idx in
                    Circle()
                        .fill(currentSlide == idx ? Self.accent : Color.white.opacity(0.2))
                        .frame(width: currentSlide == idx ? 8 : 5, height: currentSlide == idx ? 8 : 5)
                        .animation(.spring(response: 0.25), value: currentSlide)
                }
            }

            Spacer()

            Button {
                withAnimation { if currentSlide < slides.count - 1 { currentSlide += 1 } }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(currentSlide < slides.count - 1 ? .white.opacity(0.7) : .white.opacity(0.15))
            }
            .buttonStyle(.plain)
            .disabled(currentSlide == slides.count - 1)
        }
        .padding(.horizontal, 60).padding(.vertical, 18)
        .background(Color.white.opacity(0.04))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private var generatedAt: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateStyle = .long
        return f.string(from: Date())
    }

    private func bigStatCard(icon: String, label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11)).foregroundColor(color)
                Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.4)).kerning(0.8)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundColor(.white)
                Text(sub).font(.system(size: 12)).foregroundColor(.white.opacity(0.4))
            }
            Rectangle().fill(color.opacity(0.3)).frame(height: 3).clipShape(Capsule())
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }
}
