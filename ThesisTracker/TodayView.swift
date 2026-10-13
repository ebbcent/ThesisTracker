import SwiftUI
import AppKit

// MARK: - Aujourd'hui (refonte 5.4, style d'origine conservé)
//
// Écran d'accueil : l'action du jour (saisir le total du chapitre) en premier,
// puis trois repères (série, semaine, fin estimée) et une ligne Pomodoro.
// Reprend les composants et couleurs de l'app (champ de saisie du tableau de
// bord avec dictée, bouton ambre, cartes, en-têtes de section). En « Version
// Papier » (interfaceMode == "VD"), le même écran prend le thème Papier.

private struct TodayPalette {
    let background: Color
    let card: Color
    let border: Color
    let field: Color
    let track: Color
    let secondary: Color
    let accent: Color
    let accentFill: LinearGradient
    let barMuted: Color
    let numberDesign: Font.Design

    static let app = TodayPalette(
        background: .appBg,
        card: .cardBg,
        border: .cardBorder,
        field: .fieldBg,
        track: Color.primary.opacity(0.08),
        secondary: .labelMuted,
        accent: .accentWarm,
        accentFill: LinearGradient(colors: [.accent, .accentWarm], startPoint: .leading, endPoint: .trailing),
        barMuted: Color.accentWarm.opacity(0.35),
        numberDesign: .default
    )

    static let paper = TodayPalette(
        background: Color(red: 0.984, green: 0.973, blue: 0.949),
        card: Color(red: 1.0, green: 0.992, blue: 0.973),
        border: Color(red: 0.886, green: 0.851, blue: 0.784),
        field: Color(red: 0.965, green: 0.945, blue: 0.906),
        track: Color(red: 0.918, green: 0.886, blue: 0.827),
        secondary: Color(red: 0.420, green: 0.396, blue: 0.357),
        accent: Color(red: 0.604, green: 0.204, blue: 0.071),
        accentFill: LinearGradient(colors: [Color(red: 0.722, green: 0.341, blue: 0.165),
                                            Color(red: 0.604, green: 0.204, blue: 0.071)],
                                   startPoint: .leading, endPoint: .trailing),
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

    @State private var noteText: String = ""
    @State private var savedConfirmation: Bool = false
    @State private var isDictating: Bool = false
    @State private var clusterToken = UUID()
    @FocusState private var inputFocused: Bool

    private var palette: TodayPalette { interfaceMode == "VD" ? .paper : .app }
    private var today: String { DataStore.today }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                SectionHeader("Session du jour")
                if store.activeChapter != nil {
                    entryCard
                } else {
                    noChapterCard
                }
                SectionHeader("Repères")
                indicators
                pomodoroLine
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .onAppear(perform: refreshFields)
        .onChange(of: store.activeChapter?.id) { _, _ in refreshFields() }
        .onChange(of: store.dataVersion) { _, _ in
            if !inputFocused { refreshFields() }
        }
        // ⌘N : aller au champ de saisie (⌘S est géré par le champ lui-même)
        .onReceive(NotificationCenter.default.publisher(for: .dashboardFocusInput)) { _ in inputFocused = true }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            if !showSidebar {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Afficher la barre latérale")
                .accessibilityLabel("Afficher la barre latérale")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Aujourd'hui")
                    .font(.system(size: 22, weight: .bold, design: palette.numberDesign))
                Text(Self.longDate.string(from: Date()).capitalizedFirst)
                    .font(.system(size: 12))
                    .foregroundColor(palette.secondary)
            }
            Spacer()
            chapterMenu
        }
    }

    @ViewBuilder
    private var chapterMenu: some View {
        if let project = store.activeProject, !project.chapters.isEmpty {
            Menu {
                ForEach(project.chapters.filter { !$0.isArchived }) { chapter in
                    Button(chapter.name) { selectChapter(chapter.id, in: project) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 12))
                        .foregroundColor(palette.accent)
                    Text(store.activeChapter?.name ?? "Choisir un chapitre")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.labelMuted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(minWidth: 200, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).fill(palette.field))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.border, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Chapitre actif")
            .accessibilityLabel("Chapitre actif : \(store.activeChapter?.name ?? "aucun")")
        }
    }

    // MARK: Saisie du jour

    private var entryCard: some View {
        let written = store.dailyProgress
        let goal = dailyGoal
        let ratio = goal > 0 ? min(1, Double(written) / Double(goal)) : 0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ÉCRIT AUJOURD'HUI")
                        .font(.system(size: 10, weight: .semibold))
                        .kerning(1.0)
                        .foregroundColor(palette.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(DataStore.formatNumber(displayed(written)))
                            .font(.system(size: 52, weight: .bold, design: palette.numberDesign))
                            .monospacedDigit()
                        Text(unitShort)
                            .font(.system(size: 15))
                            .foregroundColor(palette.secondary)
                    }
                }
                Spacer()
                if goal > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("OBJECTIF DU JOUR")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.0)
                            .foregroundColor(palette.secondary)
                        HStack(spacing: 6) {
                            Text(DataStore.formatNumber(displayed(goal)))
                                .foregroundColor(.primary)
                            Text("·").foregroundColor(palette.secondary)
                            Text("\(Int(ratio * 100)) %").foregroundColor(palette.accent)
                        }
                        .font(.system(size: 18, weight: .semibold))
                        .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)

            if goal > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.accentFill)
                            .frame(width: proxy.size.width * CGFloat(ratio))
                    }
                }
                .frame(height: 6)
                .accessibilityLabel("Progression de l'objectif du jour")
                .accessibilityValue("\(Int(ratio * 100)) pour cent")
            }

            // Champ de saisie d'origine (dictée, historique, ⌘S, « Sauvegarder »)
            WritingEntryInputCluster(
                useWordCount: store.data.useWordCount,
                initialText: initialTotalText,
                entryForHistory: store.activeChapter?.entryForDate(today),
                savedConfirmation: savedConfirmation,
                focused: $inputFocused,
                isDictating: $isDictating,
                onSave: { count in save(count) }
            )
            .id(clusterToken)

            Divider().padding(.top, 4)
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .foregroundColor(.labelMuted)
                    .font(.system(size: 11))
                    .accessibilityHidden(true)
                TextField("Note du jour (optionnel)…", text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(saveNote)
                    .accessibilityLabel("Note du jour")
            }
        }
        .padding(18)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    private var noChapterCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aucun chapitre actif")
                .font(.system(size: 14, weight: .semibold))
            Text("Choisis ou crée un chapitre dans la barre latérale pour saisir ton total du jour.")
                .font(.system(size: 12))
                .foregroundColor(palette.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Repères

    private var indicators: some View {
        HStack(alignment: .top, spacing: 12) {
            tile(icon: "flame.fill", title: "Série") {
                Text("\(store.currentStreak) jour\(store.currentStreak > 1 ? "s" : "")")
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                Text("Record : \(store.longestStreak) jours")
                    .font(.system(size: 11)).foregroundColor(palette.secondary)
            }
            tile(icon: "calendar", title: weekTitle) {
                weekBars
            }
            tile(icon: "flag.checkered", title: "Fin estimée de la thèse") {
                if let project = store.activeProject,
                   let date = store.estimatedCompletionDate(for: project.id) {
                    Text(DataStore.formatDate(date))
                        .font(.system(size: 22, weight: .bold))
                    Text("Au rythme de \(DataStore.formatNumber(displayed(store.velocity14Days))) \(unitShort)/jour")
                        .font(.system(size: 11)).foregroundColor(palette.secondary)
                } else {
                    Text("—").font(.system(size: 22, weight: .bold))
                    Text("Pas assez de données récentes")
                        .font(.system(size: 11)).foregroundColor(palette.secondary)
                }
            }
        }
    }

    private var weekTitle: String {
        let goal = store.data.weeklyGoal
        let done = displayed(weekDays.reduce(0) { $0 + $1.value })
        return goal > 0
            ? "Semaine · \(DataStore.formatNumber(done)) / \(DataStore.formatNumber(displayed(goal)))"
            : "Semaine · \(DataStore.formatNumber(done))"
    }

    private var weekBars: some View {
        let days = weekDays
        let maxValue = max(1, days.map(\.value).max() ?? 1)
        return VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(day.isToday ? AnyShapeStyle(palette.accentFill)
                                          : AnyShapeStyle(day.value > 0 ? palette.barMuted : palette.track))
                        .frame(height: max(3, CGFloat(day.value) / CGFloat(maxValue) * 36))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36, alignment: .bottom)
            HStack(spacing: 6) {
                ForEach(days) { day in
                    Text(day.letter)
                        .font(.system(size: 9, weight: day.isToday ? .bold : .regular))
                        .foregroundColor(day.isToday ? palette.accent : palette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Écriture de la semaine")
        .accessibilityValue(days.map { "\($0.letter) \(displayed($0.value))" }.joined(separator: ", "))
    }

    @ViewBuilder
    private func tile<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(palette.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.secondary)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    // MARK: Pomodoro

    private var pomodoroLine: some View {
        let summary = pomodoroController.dashboardSummary
        return HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 12))
                .foregroundColor(palette.accent)
                .accessibilityHidden(true)
            Text("Pomodoro : **\(summary.completedFocusSessions) session\(summary.completedFocusSessions > 1 ? "s" : "")** · \(Self.formatMinutes(summary.focusMinutes)) de focus aujourd'hui")
                .font(.system(size: 12))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { selectedNav = .charts }
            } label: {
                Text("Voir les analyses")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.accent)
            }
            .buttonStyle(.plain)
            Button {
                pomodoroController.startFocusSession()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Démarrer un focus").font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(palette.accent)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.accent.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.accent.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(!pomodoroController.canStartSession)
            .opacity(pomodoroController.canStartSession ? 1 : 0.5)
            .help("Raccourci global : ⌃⌥P")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border, lineWidth: 1))
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

    private var unitShort: String { store.data.useWordCount ? "mots" : "car." }

    /// Les compteurs sont stockés en caractères ; en mode mots, on divise par 5.
    private func displayed(_ value: Int) -> Int {
        store.data.useWordCount ? value / 5 : value
    }

    /// Total du jour s'il existe, sinon champ vide (comme le tableau de bord).
    private var initialTotalText: String {
        guard let entry = store.activeChapter?.entryForDate(today) else { return "" }
        return "\(entry.totalCount)"
    }

    private func selectChapter(_ id: UUID, in project: Project) {
        guard let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) else { return }
        store.data.activeProjectId = project.id
        store.data.projects[idx].activeChapterId = id
        store.save()
    }

    private func refreshFields() {
        noteText = store.activeChapter?.entryForDate(today)?.note ?? ""
        clusterToken = UUID()
    }

    private func save(_ count: Int) {
        guard let project = store.activeProject, let chapter = store.activeChapter else { return }
        withAnimation { store.setTotalForDate(count, for: chapter.id, in: project.id, date: today) }
        if !noteText.isEmpty {
            store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: today)
        }
        inputFocused = false
        withAnimation(.easeOut(duration: 0.15)) { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.15)) { savedConfirmation = false }
        }
    }

    private func saveNote() {
        guard let project = store.activeProject, let chapter = store.activeChapter,
              chapter.entryForDate(today) != nil else { return }
        store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: today)
    }

    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy"
        return f
    }()

    private static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
