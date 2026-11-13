import SwiftUI

// MARK: - Paper Dashboard (VD)

struct PaperDashboardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var inputText: String = ""
    @State private var noteText: String = ""
    @State private var selectedDate: Date = Date()
    @State private var showSettings = false
    @State private var savedConfirmation = false
    @State private var showDeleteConfirm = false
    @State private var noteSaveDebouncer = Debouncer(delay: 0.6)

    private var activeProject: Project? { store.activeProject }
    private var activeChapter: Chapter? { store.activeChapter }
    private var selectedDateStr: String { DataStore.dateString(from: selectedDate) }
    private var isToday: Bool { selectedDateStr == DataStore.today }
    private var hasExistingEntry: Bool { activeChapter?.entryForDate(selectedDateStr) != nil }

    var body: some View {
        ZStack {
            // Fond légèrement chaud
            Color.paperBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    paperHeader
                        .padding(.bottom, 32)

                    paperProjectSelector
                        .padding(.bottom, 24)

                    Divider()
                        .padding(.bottom, 32)

                    if activeChapter != nil {
                        bigNumberSection
                            .padding(.bottom, 28)

                        paperEntrySection
                            .padding(.bottom, 32)

                        Divider()
                            .padding(.bottom, 28)

                        paperProgressSection
                            .padding(.bottom, 32)

                        Divider()
                            .padding(.bottom, 28)

                        paperWeekSection
                            .padding(.bottom, 32)

                        Divider()
                            .padding(.bottom, 28)

                        paperInsightsSection

                    } else {
                        paperEmptyState
                    }
                }
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 48)
                .padding(.vertical, 36)
            }
        }
        .onAppear { refreshInput() }
        .sheet(isPresented: $showSettings) { SettingsView(store: store) }
        .alert("Effacer cette entrée ?", isPresented: $showDeleteConfirm) {
            Button("Effacer", role: .destructive) {
                if let chapter = activeChapter, let project = activeProject {
                    withAnimation { store.deleteEntry(for: chapter.id, in: project.id, date: selectedDateStr) }
                    inputText = ""
                }
            }
            Button("Annuler", role: .cancel) { }
        } message: {
            Text("L'entrée du \(DataStore.formatDate(selectedDate)) sera supprimée définitivement.")
        }
    }

    // MARK: - Header

    private var paperHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(showSidebar ? Color.accent.opacity(0.08) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.cardBorder.opacity(0.7), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(DataStore.formatLongDate(Date(), capitalize: true))
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                if store.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                        Text("\(store.currentStreak) jours")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.961, green: 0.455, blue: 0.114))
                }
            }

            // 5.14 — Professeur en note rapide (fenêtre flottante)
            ProfessorQuickButton(store: store, size: 32)

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.cardBorder.opacity(0.7), lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
            .help("Réglages")
            .accessibilityLabel("Réglages")
        }
    }

    // MARK: - Project / Chapter selector

    private var paperProjectSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.data.projects.isEmpty {
                Text("Aucun projet")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                    Picker("", selection: Binding(
                        get: { store.data.activeProjectId ?? UUID() },
                        set: { id in
                            store.data.activeProjectId = id
                            store.save()
                            refreshInput()
                        }
                    )) {
                        ForEach(store.data.projects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 14, weight: .medium))
                }

                if let project = activeProject, !project.chapters.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                        Picker("", selection: Binding(
                            get: { project.activeChapterId ?? UUID() },
                            set: { id in
                                if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                                    store.data.projects[idx].activeChapterId = id
                                    store.save()
                                    refreshInput()
                                }
                            }
                        )) {
                            ForEach(project.chapters) { chapter in
                                Text(chapter.name).tag(chapter.id)
                            }
                        }
                        .labelsHidden()
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Big number

    private var bigNumberSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Chiffre principal en New York serif
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                let count = inputInt ?? currentCount
                Text(formatNumber(count))
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.5), value: count)

                Text(store.data.useWordCount ? "mots" : "car.")
                    .font(.system(size: 20))
                    .foregroundColor(.labelMuted)
                    .padding(.bottom, 8)
            }

            // Progression du jour
            if store.data.dailyGoal > 0 {
                let ratio = min(1.0, Double(store.dailyProgress) / Double(store.data.dailyGoal))
                let pct = Int(ratio * 100)
                HStack(spacing: 8) {
                    Text("\(pct)% de l'objectif journalier")
                        .font(.system(size: 13))
                        .foregroundColor(ratio >= 1.0 ? .accentGreen : .labelMuted)
                    if ratio >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.accentGreen)
                    }
                }
            }
        }
    }

    private var currentCount: Int {
        activeChapter?.entryForDate(selectedDateStr).map { $0.totalCount } ?? 0
    }

    // MARK: - Entry section

    private var paperEntrySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Date
            HStack(spacing: 8) {
                DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: selectedDate) { _, _ in refreshInput() }
                if !isToday {
                    Button("Aujourd'hui") { withAnimation { selectedDate = Date() } }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accent)
                        .buttonStyle(.plain)
                    Label("Passé", systemImage: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                Spacer()
                if hasExistingEntry {
                    Button { showDeleteConfirm = true } label: {
                        Label("Effacer", systemImage: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 1, green: 0.35, blue: 0.35))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Saisie principale
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    TextField("ex: 15 340", text: $inputText)
                        .font(.system(size: 22, weight: .light))
                        .foregroundColor(.primary)
                        .textFieldStyle(.plain)
                        .onSubmit { saveEntry() }
                    Text(store.data.useWordCount ? "mots" : "car.")
                        .font(.system(size: 16))
                        .foregroundColor(.labelMuted)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.fieldBg)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                )
                .frame(maxWidth: .infinity)

                Button(action: saveEntry) {
                    HStack(spacing: 6) {
                        Image(systemName: savedConfirmation ? "checkmark" : "arrow.down.circle.fill")
                            .font(.system(size: 13))
                        Text(savedConfirmation ? "Enregistré" : "Sauvegarder")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(savedConfirmation ? Color.accentGreen : Color.accent)
                            .shadow(color: (savedConfirmation ? Color.accentGreen : Color.accent).opacity(0.30),
                                    radius: 6, x: 0, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(inputInt == nil)
                .animation(.easeInOut(duration: 0.22), value: savedConfirmation)
            }

            // Note
            HStack(spacing: 8) {
                Image(systemName: "pencil").foregroundColor(.labelMuted).font(.system(size: 11))
                TextField("Note du jour…", text: $noteText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .onSubmit { saveNote() }
                    .onChange(of: noteText) { _, _ in if hasExistingEntry { noteSaveDebouncer.schedule { saveNote() } } }
            }
        }
    }

    // MARK: - Progress (compact, pas de cartes)

    private var paperProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progression")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)

            VStack(spacing: 12) {
                paperProgressRow(
                    label: "Aujourd'hui",
                    value: store.dailyProgress,
                    goal: store.data.dailyGoal,
                    color: .accent
                )
                paperProgressRow(
                    label: "30 derniers jours",
                    value: store.monthlyProgress,
                    goal: store.data.monthlyGoal,
                    color: .accentWarm
                )
                if let chapter = activeChapter {
                    paperProgressRow(
                        label: chapter.name,
                        value: store.chapterProgress,
                        goal: chapter.goal,
                        color: .accentGreen
                    )
                }
            }
        }
    }

    private func paperProgressRow(label: String, value: Int, goal: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                if goal > 0 {
                    let isComplete = value >= goal
                    HStack(spacing: 0) {
                        Text(formatNumber(value))
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        Text(" / \(formatNumber(goal))")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text("  \(Int(min(1.0, Double(value) / Double(goal)) * 100))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isComplete ? .accentGreen : color)
                    }
                } else {
                    Text(formatNumber(value))
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                }
            }
            if goal > 0 {
                GeometryReader { geo in
                    let ratio = min(1.0, CGFloat(value) / CGFloat(max(goal, 1)))
                    ZStack(alignment: .leading) {
                        Rectangle().fill(color.opacity(0.10)).frame(height: 1)
                        Rectangle()
                            .fill(value >= goal ? Color.accentGreen : color)
                            .frame(width: max(0, geo.size.width * ratio), height: 1)
                    }
                }
                .frame(height: 1)
            }
        }
    }

    // MARK: - Week calendar (texte, épuré)

    private var paperWeekSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cette semaine")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)

            HStack(spacing: 0) {
                ForEach(currentWeekData, id: \.dateStr) { day in
                    paperWeekCell(day: day)
                }
            }
        }
    }

    private func paperWeekCell(day: WeekDayData) -> some View {
        let ratio: Double = store.data.dailyGoal > 0
            ? min(1.0, Double(day.written) / Double(store.data.dailyGoal))
            : (day.written > 0 ? 1.0 : 0.0)
        let reached = store.data.dailyGoal > 0 && day.written >= store.data.dailyGoal

        return VStack(spacing: 4) {
            Text(day.letter)
                .font(.system(size: 10))
                .foregroundColor(day.isToday ? .accent : .labelMuted)

            Text("\(day.dayNumber)")
                .font(.system(size: 13, weight: day.isToday ? .semibold : .regular))
                .foregroundColor(day.isFuture ? .labelMuted.opacity(0.4) : .primary)

            if reached {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.accentGreen)
                    .frame(height: 10)
            } else if day.written > 0 && !day.isFuture {
                Circle()
                    .fill(Color.accent.opacity(max(0.25, ratio * 0.85)))
                    .frame(width: 6, height: 6)
                    .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(day.isToday ? Color.accent.opacity(0.06) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // Reuse same WeekDayData logic
    private struct WeekDayData {
        let date: Date; let dateStr: String; let written: Int
        let isToday: Bool; let isFuture: Bool; let letter: String; let dayNumber: Int
    }

    private var currentWeekData: [WeekDayData] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let today = Date()
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        let todayStr = DataStore.today
        let allChapters = store.data.projects.flatMap { $0.chapters }
        let letters = ["D","L","M","M","J","V","S"]
        var result: [WeekDayData] = []
        var current = weekInterval.start
        for _ in 0..<7 {
            let dateStr = DataStore.dateString(from: current)
            let written = allChapters.reduce(0) { $0 + $1.increment(for: dateStr) }
            let weekday = cal.component(.weekday, from: current)
            result.append(WeekDayData(
                date: current, dateStr: dateStr, written: written,
                isToday: dateStr == todayStr, isFuture: current > today,
                letter: letters[weekday - 1], dayNumber: cal.component(.day, from: current)
            ))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        return result
    }

    // MARK: - Insights (compact)

    @ViewBuilder
    private var paperInsightsSection: some View {
        if !store.dailyTotals().isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Insights")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.8)

                VStack(spacing: 10) {
                    paperInsightRow(icon: "star.fill", color: .accent,
                        label: "Meilleur jour",
                        value: insightBestWeekday.name,
                        sub: insightBestWeekday.avg > 0 ? "moy. \(formatNumber(insightBestWeekday.avg))" : nil)
                    paperInsightRow(icon: "trophy.fill", color: .accentWarm,
                        label: "Record",
                        value: insightRecord.chars > 0 ? formatNumber(insightRecord.chars) : "—",
                        sub: insightRecord.chars > 0 ? insightRecord.label : nil)
                    if store.data.dailyGoal > 0 {
                        paperInsightRow(icon: "checkmark.seal.fill", color: .accentGreen,
                            label: "Objectif 30j",
                            value: "\(insightGoalRate)%",
                            sub: "\(insightGoalDays) / 30 jours")
                    }
                }
            }
        }
    }

    private func paperInsightRow(icon: String, color: Color, label: String, value: String, sub: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                if let sub = sub {
                    Text(sub)
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
            }
        }
    }

    // MARK: - Empty state

    private var paperEmptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 36))
                .foregroundColor(.labelMuted)
            Text(store.data.projects.isEmpty ? "Créez un projet pour commencer" : "Ajoutez un chapitre à ce projet")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Button("Ouvrir les projets") {
                withAnimation(.easeOut(duration: 0.15)) { showSidebar = true }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.accent))
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Computed insights

    private var insightBestWeekday: (name: String, avg: Int) {
        let totals = store.dailyTotals()
        let cal = Calendar(identifier: .gregorian)
        let frenchDays = ["Dimanche","Lundi","Mardi","Mercredi","Jeudi","Vendredi","Samedi"]
        var byWeekday: [Int: [Int]] = [:]
        for (dateStr, val) in totals {
            guard val > 0, let date = DataStore.parseDate(dateStr) else { continue }
            byWeekday[cal.component(.weekday, from: date), default: []].append(val)
        }
        guard let best = byWeekday.max(by: { ($0.value.reduce(0,+)/$0.value.count) < ($1.value.reduce(0,+)/$1.value.count) }) else { return ("—", 0) }
        return (frenchDays[best.key - 1], best.value.reduce(0,+) / best.value.count)
    }

    private var insightRecord: (chars: Int, label: String) {
        let totals = store.dailyTotals()
        guard let best = totals.max(by: { $0.value < $1.value }), best.value > 0 else { return (0, "") }
        return (best.value, DataStore.parseDate(best.key).map { DataStore.formatDate($0) } ?? best.key)
    }

    private var insightGoalDays: Int {
        let cal = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()
        return (0..<30).filter { offset -> Bool in
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return false }
            return (totals[DataStore.dateString(from: date)] ?? 0) >= store.data.dailyGoal
        }.count
    }

    private var insightGoalRate: Int { Int(Double(insightGoalDays) / 30.0 * 100) }

    // MARK: - Helpers

    private var inputInt: Int? {
        guard !inputText.isEmpty else { return nil }
        return Int(inputText
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: ""))
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func saveEntry() {
        guard let count = inputInt, let chapter = activeChapter, let project = activeProject else { return }
        withAnimation { store.setTotalForDate(count, for: chapter.id, in: project.id, date: selectedDateStr) }
        withAnimation(.easeOut(duration: 0.15)) { savedConfirmation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeOut(duration: 0.15)) { savedConfirmation = false }
        }
    }

    private func saveNote() {
        guard let chapter = activeChapter, let project = activeProject, hasExistingEntry else { return }
        store.setNoteForDate(noteText, for: chapter.id, in: project.id, date: selectedDateStr)
    }

    private func refreshInput() {
        guard let chapter = activeChapter else { inputText = ""; noteText = ""; return }
        let entry = chapter.entryForDate(selectedDateStr)
        inputText = entry.map { "\($0.totalCount)" } ?? ""
        noteText = entry?.note ?? ""
    }
}

// MARK: - Couleur fond papier

extension Color {
    static let paperBg = Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
        trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.110, green: 0.108, blue: 0.103, alpha: 1)   // #1c1b1a warm dark
            : NSColor(red: 0.980, green: 0.976, blue: 0.965, alpha: 1)   // #faf9f6 warm cream
    }))
}
