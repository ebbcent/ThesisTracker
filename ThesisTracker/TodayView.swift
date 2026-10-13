import SwiftUI
import AppKit

// MARK: - Aujourd'hui (refonte 5.4)
//
// Écran d'accueil sobre : l'action du jour (saisir le total du chapitre) en
// premier, puis trois repères (série, semaine, fin estimée) et une ligne
// Pomodoro. Tout le reste (widgets, insights…) reste dans l'onglet
// « Tableau de bord ». Suit l'apparence de macOS ; en « Version Papier »
// (interfaceMode == "VD"), le même écran prend le thème Papier.

private struct TodayPalette {
    let background: Color
    let card: Color
    let border: Color
    let track: Color
    let text: Color
    let secondary: Color
    let progress: Color
    let progressText: Color
    let barMuted: Color
    let numberDesign: Font.Design

    static let system = TodayPalette(
        background: Color(nsColor: .windowBackgroundColor),
        card: Color(nsColor: .controlBackgroundColor),
        border: Color(nsColor: .separatorColor),
        track: Color.primary.opacity(0.08),
        text: Color.primary,
        secondary: Color.secondary,
        progress: Color.orange,
        progressText: Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(srgbRed: 1.0, green: 0.70, blue: 0.25, alpha: 1)
                : NSColor(srgbRed: 0.71, green: 0.33, blue: 0.04, alpha: 1)
        }),
        barMuted: Color.primary.opacity(0.18),
        numberDesign: .default
    )

    static let paper = TodayPalette(
        background: Color(red: 0.984, green: 0.973, blue: 0.949),
        card: Color(red: 1.0, green: 0.992, blue: 0.973),
        border: Color(red: 0.886, green: 0.851, blue: 0.784),
        track: Color(red: 0.918, green: 0.886, blue: 0.827),
        text: Color(red: 0.169, green: 0.165, blue: 0.153),
        secondary: Color(red: 0.420, green: 0.396, blue: 0.357),
        progress: Color(red: 0.722, green: 0.341, blue: 0.165),
        progressText: Color(red: 0.604, green: 0.204, blue: 0.071),
        barMuted: Color(red: 0.847, green: 0.812, blue: 0.741),
        numberDesign: .serif
    )
}

struct TodayView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool
    @Binding var selectedNav: NavItem
    @EnvironmentObject private var pomodoroController: PomodoroAppController
    @AppStorage("interfaceMode") private var interfaceMode: String = "VA"

    @State private var totalText: String = ""
    @State private var noteText: String = ""
    @State private var savedFlash: Bool = false
    @FocusState private var totalFocused: Bool

    private var palette: TodayPalette { interfaceMode == "VD" ? .paper : .system }
    private var today: String { DataStore.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if store.activeChapter != nil {
                    entryCard
                } else {
                    noChapterCard
                }
                indicators
                pomodoroLine
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .foregroundStyle(palette.text)
        .onAppear(perform: refreshFields)
        .onChange(of: store.activeChapter?.id) { _, _ in refreshFields() }
        .onChange(of: store.dataVersion) { _, _ in
            if !totalFocused { refreshFields() }
        }
        // Raccourcis existants de saisie (⌘S enregistrer, ⌘N aller au champ)
        .onReceive(NotificationCenter.default.publisher(for: .dashboardSave)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardFocusInput)) { _ in totalFocused = true }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            if !showSidebar {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .buttonStyle(.borderless)
                .help("Afficher la barre latérale")
                .accessibilityLabel("Afficher la barre latérale")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Aujourd'hui")
                    .font(.system(.largeTitle, design: palette.numberDesign).weight(.bold))
                Text(Self.longDate.string(from: Date()).capitalizedFirst)
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
            }
            Spacer()
            if let project = store.activeProject, !project.chapters.isEmpty {
                Picker("Chapitre", selection: chapterBinding(project)) {
                    ForEach(project.chapters.filter { !$0.isArchived }) { chapter in
                        Text(chapter.name).tag(Optional(chapter.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
            }
        }
    }

    // MARK: Saisie du jour

    private var entryCard: some View {
        let written = store.dailyProgress
        let goal = dailyGoal
        let ratio = goal > 0 ? min(1, Double(written) / Double(goal)) : 0

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Écrit aujourd'hui")
                        .font(.callout)
                        .foregroundStyle(palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(DataStore.formatNumber(displayed(written)))
                            .font(.system(size: 60, weight: .bold, design: palette.numberDesign))
                            .monospacedDigit()
                        Text(unitName)
                            .font(.title3)
                            .foregroundStyle(palette.secondary)
                    }
                }
                Spacer()
                if goal > 0 {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Objectif du jour")
                            .font(.callout)
                            .foregroundStyle(palette.secondary)
                        HStack(spacing: 6) {
                            Text(DataStore.formatNumber(displayed(goal)))
                            Text("·").foregroundStyle(palette.secondary)
                            Text("\(Int(ratio * 100)) %").foregroundStyle(palette.progressText)
                        }
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if goal > 0 {
                ProgressView(value: ratio)
                    .progressViewStyle(TodayBarStyle(fill: palette.progress, track: palette.track, height: 8))
                    .accessibilityLabel("Progression de l'objectif du jour")
                    .accessibilityValue("\(Int(ratio * 100)) pour cent")
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nouveau total du chapitre")
                        .font(.callout)
                        .foregroundStyle(palette.secondary)
                    TextField("Total en caractères", text: $totalText)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3.monospacedDigit())
                        .focused($totalFocused)
                        .onSubmit(save)
                        .accessibilityLabel("Nouveau total du chapitre")
                }
                Button(action: save) {
                    Text(savedFlash ? "Enregistré ✓" : "Enregistrer")
                        .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(parsedTotal == nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Note du jour (facultatif)")
                    .font(.callout)
                    .foregroundStyle(palette.secondary)
                TextField("Ce qui a avancé, ce qui bloque…", text: $noteText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                    .accessibilityLabel("Note du jour")
            }
        }
        .padding(28)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
    }

    private var noChapterCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aucun chapitre actif")
                .font(.title3.weight(.semibold))
            Text("Choisis ou crée un chapitre dans la barre latérale pour saisir ton total du jour.")
                .foregroundStyle(palette.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Repères

    private var indicators: some View {
        HStack(alignment: .top, spacing: 16) {
            tile(title: "Série") {
                Text("\(store.currentStreak) jour\(store.currentStreak > 1 ? "s" : "")")
                    .font(.title.weight(.bold)).monospacedDigit()
                Text("Record : \(store.longestStreak) jours")
                    .font(.caption).foregroundStyle(palette.secondary)
            }
            tile(title: weekTitle) {
                weekBars
            }
            tile(title: "Fin estimée de la thèse") {
                if let project = store.activeProject,
                   let date = store.estimatedCompletionDate(for: project.id) {
                    Text(DataStore.formatDate(date))
                        .font(.title.weight(.bold))
                    Text("Au rythme de \(DataStore.formatNumber(displayed(store.velocity14Days))) \(unitShort)/jour")
                        .font(.caption).foregroundStyle(palette.secondary)
                } else {
                    Text("—").font(.title.weight(.bold))
                    Text("Pas assez de données récentes")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
            }
        }
    }

    private var weekTitle: String {
        let goal = store.data.weeklyGoal
        let done = displayed(weekDays.reduce(0) { $0 + $1.value })
        return goal > 0
            ? "Cette semaine · \(DataStore.formatNumber(done)) / \(DataStore.formatNumber(displayed(goal)))"
            : "Cette semaine · \(DataStore.formatNumber(done))"
    }

    private var weekBars: some View {
        let days = weekDays
        let maxValue = max(1, days.map(\.value).max() ?? 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.isToday ? palette.progress : (day.value > 0 ? palette.barMuted : palette.track))
                        .frame(height: max(3, CGFloat(day.value) / CGFloat(maxValue) * 40))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack(spacing: 8) {
                ForEach(days) { day in
                    Text(day.letter)
                        .font(.caption2)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Écriture de la semaine")
        .accessibilityValue(days.map { "\($0.letter) \(displayed($0.value))" }.joined(separator: ", "))
    }

    @ViewBuilder
    private func tile<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout)
                .foregroundStyle(palette.secondary)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Pomodoro

    private var pomodoroLine: some View {
        let summary = pomodoroController.dashboardSummary
        return HStack(spacing: 12) {
            Image(systemName: "timer")
                .foregroundStyle(palette.secondary)
                .accessibilityHidden(true)
            Text("Pomodoro : **\(summary.completedFocusSessions) session\(summary.completedFocusSessions > 1 ? "s" : "")** · \(Self.formatMinutes(summary.focusMinutes)) de focus aujourd'hui")
            Spacer()
            Button("Voir les analyses") {
                withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .charts }
            }
            .buttonStyle(.link)
            Button("Démarrer un focus") {
                pomodoroController.startFocusSession()
            }
            .disabled(!pomodoroController.canStartSession)
            .help("Raccourci global : ⌃⌥P")
        }
        .font(.callout)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Données

    private struct WeekDay: Identifiable {
        let id: String
        let letter: String
        let value: Int
        let isToday: Bool
    }

    /// Semaine ISO en cours (lundi → dimanche), comme les défis hebdomadaires.
    private var weekDays: [WeekDay] {
        let cal = DataStore.iso8601Cal
        let now = Date()
        guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return [] }
        let totals = store.dailyTotals()
        let letters = ["L", "M", "M", "J", "V", "S", "D"]
        return (0..<7).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = DataStore.dateString(from: day)
            return WeekDay(id: key, letter: letters[offset], value: totals[key] ?? 0, isToday: key == today)
        }
    }

    private var dailyGoal: Int {
        let smart = store.todaySmartGoal
        return smart > 0 ? smart : store.effectiveDailyGoal
    }

    private var unitName: String { store.data.useWordCount ? "mots" : "caractères" }
    private var unitShort: String { store.data.useWordCount ? "mots" : "car." }

    /// Les compteurs sont stockés en caractères ; en mode mots, on divise par 5.
    private func displayed(_ value: Int) -> Int {
        store.data.useWordCount ? value / 5 : value
    }

    private var parsedTotal: Int? {
        let digits = totalText.filter(\.isNumber)
        guard !digits.isEmpty, let value = Int(digits), value >= 0 else { return nil }
        return value
    }

    private func chapterBinding(_ project: Project) -> Binding<UUID?> {
        Binding(
            get: { store.activeProject?.activeChapterId },
            set: { newID in
                guard let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) else { return }
                store.data.projects[idx].activeChapterId = newID
                store.save()
            }
        )
    }

    private func refreshFields() {
        guard let chapter = store.activeChapter else {
            totalText = ""; noteText = ""
            return
        }
        let entry = chapter.entryForDate(today)
        let total = entry?.totalCount ?? chapter.previousTotal(before: today)
        totalText = total > 0 ? DataStore.formatNumber(total) : ""
        noteText = entry?.note ?? ""
    }

    private func save() {
        guard let value = parsedTotal,
              let project = store.activeProject,
              let chapter = store.activeChapter else { return }
        store.setTotalForDate(value, for: chapter.id, in: project.id, date: today)
        store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: today)
        totalFocused = false
        withAnimation(.easeOut(duration: 0.15)) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.15)) { savedFlash = false }
        }
    }

    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}

/// Barre de progression plate aux couleurs du thème.
private struct TodayBarStyle: ProgressViewStyle {
    let fill: Color
    let track: Color
    let height: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: proxy.size.width * CGFloat(configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: height)
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
