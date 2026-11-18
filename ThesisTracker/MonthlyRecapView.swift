import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 5.24 Récap du mois
//
// Cinq écrans sur le mois écoulé, proposés à la première ouverture de chaque mois
// (affichage Tuiles) et rouvrables depuis la tuile « Récap du mois ».
// Les chiffres viennent de `dailyTotals()` : les mêmes que partout dans l'app.

struct MonthlyRecap {
    let monthStart: Date
    let dayValues: [Int]          // un total par jour du mois
    let leadingBlanks: Int        // cases vides avant le 1er (semaine commençant le lundi)
    let total: Int
    let writingDays: Int
    let bestDay: Int?             // numéro du jour
    let bestValue: Int
    let runLength: Int            // plus longue série du mois
    let runFrom: Int
    let runTo: Int
    let previousTotal: Int
    let topChapterName: String?
    let topChapterAdded: Int
    let monthlyGoal: Int

    private static let cal = DataStore.gregorianCal

    static func previousMonthStart(from now: Date = Date()) -> Date {
        let thisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return cal.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
    }

    static func monthKey(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func monthName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.calendar = cal
        f.dateFormat = "LLLL"
        return f.string(from: date)
    }

    var monthName: String { Self.monthName(monthStart) }
    var previousMonthName: String {
        Self.monthName(Self.cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart)
    }
    var sheets: Int { Int((Double(max(0, total)) / Double(TilesTheme.sheetSize)).rounded()) }
    var goalRatio: Double { monthlyGoal > 0 ? min(1, max(0, Double(total) / Double(monthlyGoal))) : 0 }

    private static func dayStrings(of monthStart: Date) -> [String] {
        let count = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        return (0..<count).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: monthStart).map(DataStore.dateString)
        }
    }

    /// Mois écoulés qui ont des saisies, du plus récent au plus ancien (5.26).
    static func availableMonths(store: DataStore, now: Date = Date()) -> [Date] {
        guard let first = store.dailyTotals().filter({ $0.value != 0 }).keys.min(),
              let firstDate = DataStore.parseDate(first) else { return [] }
        let firstMonth = cal.date(from: cal.dateComponents([.year, .month], from: firstDate)) ?? firstDate
        var months: [Date] = []
        var month = previousMonthStart(from: now)
        while month >= firstMonth, months.count < 240 {
            months.append(month)
            guard let earlier = cal.date(byAdding: .month, value: -1, to: month) else { break }
            month = earlier
        }
        return months
    }

    static func yearText(_ date: Date) -> String { String(cal.component(.year, from: date)) }

    /// Une notification par mois, à la première ouverture de l'app après le 1er (5.26).
    static func notifyIfDue(store: DataStore) {
        guard !store.data.projects.isEmpty else { return }
        let month = previousMonthStart()
        let key = monthKey(month)
        let defaultsKey = "monthlyRecapLastNotified"
        guard UserDefaults.standard.string(forKey: defaultsKey) != key else { return }
        UserDefaults.standard.set(key, forKey: defaultsKey)
        let recap = compute(store: store, monthStart: month, includeChapter: false)
        guard recap.total != 0 || recap.previousTotal != 0 else { return }
        let unit = store.data.useWordCount ? "mots" : "signes"
        let total = DataStore.formatNumber(store.data.useWordCount ? recap.total / 5 : recap.total)
        let days = "\(recap.writingDays) jour\(recap.writingDays > 1 ? "s" : "") d'écriture"
        NotificationManager.shared.sendMonthlyRecapReady(monthName: recap.monthName, summary: "\(total) \(unit), \(days).")
    }

    static func compute(store: DataStore, monthStart: Date, includeChapter: Bool = true) -> MonthlyRecap {
        let totals = store.dailyTotals()
        let days = dayStrings(of: monthStart)
        let values = days.map { totals[$0] ?? 0 }

        var bestDay: Int? = nil
        var bestValue = 0
        var run = 0, runLength = 0, runTo = 0
        for (index, value) in values.enumerated() {
            if value > bestValue { bestValue = value; bestDay = index + 1 }
            run = value > 0 ? run + 1 : 0
            if run > runLength { runLength = run; runTo = index + 1 }
        }

        let previousStart = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        let previousTotal = dayStrings(of: previousStart).reduce(0) { $0 + (totals[$1] ?? 0) }

        var topName: String? = nil
        var topAdded = 0
        for project in store.data.projects where includeChapter && !project.isArchived {
            for chapter in project.chapters {
                let added = days.reduce(0) { $0 + max(0, chapter.increment(for: $1)) }
                if added > topAdded { topAdded = added; topName = chapter.name }
            }
        }

        let weekday = cal.component(.weekday, from: monthStart)   // 1 = dimanche
        return MonthlyRecap(
            monthStart: monthStart,
            dayValues: values,
            leadingBlanks: (weekday + 5) % 7,
            total: values.reduce(0, +),
            writingDays: values.filter { $0 > 0 }.count,
            bestDay: bestDay,
            bestValue: bestValue,
            runLength: runLength,
            runFrom: max(1, runTo - runLength + 1),
            runTo: runTo,
            previousTotal: previousTotal,
            topChapterName: topName,
            topChapterAdded: topAdded,
            monthlyGoal: store.data.monthlyGoal
        )
    }

    /// Une phrase pour résumer le mois, selon l'objectif mensuel et le nombre de jours écrits.
    var verdict: String {
        if total <= 0 { return "Un mois blanc." }
        if monthlyGoal > 0, total >= monthlyGoal { return "Objectif tenu." }
        if writingDays <= 3 { return "Un mois en pointillé." }
        if monthlyGoal > 0, Double(total) >= Double(monthlyGoal) * 0.5 { return "Un mois plein." }
        if writingDays >= 12 { return "Un mois régulier." }
        return "Un mois discret."
    }

    var coverLine: String {
        if total <= 0 { return "Aucune saisie ce mois-là. Le prochain repart de zéro." }
        return "Ce que tu as fait de ces \(dayValues.count) jours, relu d'un seul coup."
    }
}

// MARK: - Vue

struct MonthlyRecapView: View {
    @ObservedObject var store: DataStore
    let recap: MonthlyRecap
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private let pageCount = 5

    private struct Theme { let bg: Color; let fg: Color; let pop: Color; let light: Bool }

    private static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
              blue: Double(v & 0xFF) / 255, opacity: 1)
    }

    private static let themes: [Theme] = [
        Theme(bg: hex(0x1F3FD1), fg: hex(0xFBF9F4), pop: hex(0xFFD27A), light: false),
        Theme(bg: hex(0xFBF9F4), fg: hex(0x1B1A17), pop: hex(0x1F3FD1), light: true),
        Theme(bg: hex(0x11100F), fg: hex(0xF0EDE6), pop: hex(0x8FA3FF), light: false),
        Theme(bg: hex(0x1F5A3D), fg: hex(0xF3F1E7), pop: hex(0xFFD27A), light: false),
        Theme(bg: hex(0xFBF9F4), fg: hex(0x1B1A17), pop: hex(0x1F3FD1), light: true)
    ]

    private var theme: Theme { Self.themes[min(max(page, 0), Self.themes.count - 1)] }
    private var unitWord: String { store.data.useWordCount ? "mots" : "signes" }
    private func num(_ value: Int) -> String {
        DataStore.formatNumber(store.data.useWordCount ? value / 5 : value)
    }
    private func dayLabel(_ day: Int) -> String { day == 1 ? "1er" : "\(day)" }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                topBar
                Group {
                    switch page {
                    case 0: coverPage
                    case 1: totalPage
                    case 2: daysPage
                    case 3: chapterPage
                    default: summaryPage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .transition(.opacity)
                .id(page)
                bottomBar
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 28)
        }
        .foregroundColor(theme.fg)
        .appAnimation(Motion.panel, value: page)
        .sheetFrame(width: 980, height: 640)
    }

    // MARK: Barres

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule().fill(theme.fg.opacity(index <= page ? 1 : 0.28)).frame(height: 4)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Text("WRITING PROCESS · RÉCAP DU MOIS")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.2)
                Spacer()
                Text("\(page + 1) / \(pageCount)")
                    .font(.system(size: 12, design: .monospaced))
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button { if page > 0 { page -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(theme.fg.opacity(theme.light ? 0.08 : 0.16)))
            }
            .buttonStyle(.pressable)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(page == 0 ? 0.35 : 1)
            .disabled(page == 0)
            .accessibilityLabel("Écran précédent")

            Spacer()

            Button("Fermer") { dismiss() }
                .buttonStyle(.pressable)
                .font(.system(size: 13, weight: .medium))
                .keyboardShortcut(.cancelAction)
                .padding(.trailing, 14)

            Button {
                if page < pageCount - 1 { page += 1 } else { dismiss() }
            } label: {
                HStack(spacing: 8) {
                    Text(page == 0 ? "Commencer" : (page == pageCount - 1 ? "Terminer" : "Suivant"))
                        .font(.system(size: 14, weight: .semibold))
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Capsule().fill(theme.fg.opacity(theme.light ? 0.08 : 0.16)))
            }
            .buttonStyle(.pressable)
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    // MARK: Écrans

    private var coverPage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer()
            Text("Ton mois d'écriture")
                .font(.system(size: 28, design: .serif).italic())
            Text(recap.monthName.capitalized)
                .font(.system(size: 190, weight: .regular, design: .serif))
                .tracking(-8)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            Text(recap.coverLine)
                .font(.system(size: 17))
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.top, 8)
            Spacer()
        }
    }

    private var totalPage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Text("En \(recap.monthName), tu as écrit")
                .font(.system(size: 28, design: .serif).italic())
            Text(num(recap.total))
                .font(.system(size: 150, weight: .light, design: .monospaced))
                .tracking(-9)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            (Text("\(unitWord). ")
             + (store.data.useWordCount ? Text("") : Text("Soit ") + Text("\(recap.sheets) feuillets").foregroundColor(theme.pop) + Text(". "))
             + Text(versusLine))
                .font(.system(size: 28, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if recap.monthlyGoal > 0 {
                HStack(spacing: 16) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.fg.opacity(0.12))
                            Capsule().fill(theme.fg).frame(width: geo.size.width * recap.goalRatio)
                        }
                    }
                    .frame(height: 10)
                    Text("\(Int((recap.goalRatio * 100).rounded())) % de l'objectif mensuel de \(num(recap.monthlyGoal))")
                        .font(.system(size: 13, design: .monospaced))
                        .fixedSize()
                }
            }
        }
    }

    private var versusLine: String {
        let previous = recap.previousTotal
        guard previous > 0 else { return "En \(recap.previousMonthName) : rien." }
        let change = Int((Double(recap.total - previous) / Double(previous) * 100).rounded())
        if abs(change) > 300 { return "En \(recap.previousMonthName) : \(num(previous))." }
        if change > 0 { return "\(change) % de plus qu'en \(recap.previousMonthName)." }
        if change < 0 { return "\(-change) % de moins qu'en \(recap.previousMonthName)." }
        return "Autant qu'en \(recap.previousMonthName)."
    }

    private var daysPage: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(recap.writingDays)")
                    .font(.system(size: 200, weight: .regular, design: .serif))
                    .tracking(-8)
                    .foregroundColor(theme.pop)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("\(recap.writingDays > 1 ? "jours" : "jour") d'écriture")
                    .font(.system(size: 38, design: .serif))
                Text(runLine)
                    .font(.system(size: 22, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(["lun.", "mar.", "mer.", "jeu.", "ven.", "sam.", "dim."], id: \.self) { name in
                        Text(name).font(.system(size: 11)).opacity(0.75).frame(width: 48)
                    }
                }
                .accessibilityHidden(true)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(48), spacing: 8), count: 7), spacing: 8) {
                    ForEach(0..<recap.leadingBlanks, id: \.self) { _ in
                        Color.clear.frame(width: 48, height: 48)
                    }
                    ForEach(Array(recap.dayValues.enumerated()), id: \.offset) { index, value in
                        dayCell(day: index + 1, value: value)
                    }
                }
                .frame(width: 7 * 48 + 6 * 8)
            }
        }
    }

    private func dayCell(day: Int, value: Int) -> some View {
        let strong = value >= 10_000
        let fill: Color = strong ? theme.pop
            : (value >= 2_000 ? theme.pop.opacity(0.55) : (value > 0 ? theme.pop.opacity(0.26) : theme.fg.opacity(0.08)))
        return Text("\(day)")
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(strong ? theme.bg : theme.fg.opacity(value > 0 ? 1 : 0.55))
            .frame(width: 48, height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill))
            .help("\(dayLabel(day)) \(recap.monthName) : \(num(value)) \(unitWord)")
            .accessibilityLabel("\(dayLabel(day)) \(recap.monthName), \(num(value)) \(unitWord)")
    }

    private var runLine: String {
        if recap.runLength >= 2 {
            return "Dont une série de \(recap.runLength) jours, du \(dayLabel(recap.runFrom)) au \(recap.runTo)."
        }
        if recap.writingDays == 1, let day = recap.bestDay {
            return "Tout s'est joué le \(dayLabel(day))."
        }
        return recap.writingDays == 0 ? "Pas une ligne ce mois-là." : "Des journées isolées, sans série."
    }

    private var chapterPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name = recap.topChapterName {
                let parts = TilesChapterTitle(name)
                Text(("Ton chapitre du mois" + (parts.number.map { " · chapitre \($0)" } ?? "")).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.2)
                Text(parts.title)
                    .font(.system(size: 76, weight: .regular, design: .serif))
                    .tracking(-2.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                if let subtitle = parts.subtitle {
                    Text(subtitle)
                        .font(.system(size: 24, design: .serif).italic())
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 48) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AJOUTÉS CE MOIS-CI").font(.system(size: 12, weight: .semibold)).kerning(1.2)
                        Text("+" + num(recap.topChapterAdded))
                            .font(.system(size: 60, weight: .light, design: .monospaced))
                            .tracking(-3)
                            .foregroundColor(theme.pop)
                    }
                    if let day = recap.bestDay {
                        Text("Ton meilleur jour : le \(dayLabel(day)), avec \(num(recap.bestValue)) \(unitWord).")
                            .font(.system(size: 22, design: .serif))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)
                    }
                }
            } else {
                Spacer()
                Text("Aucun chapitre n'a avancé ce mois-là.")
                    .font(.system(size: 44, design: .serif))
                Spacer()
            }
        }
        .padding(.top, 28)
    }

    private var summaryPage: some View {
        HStack(alignment: .center, spacing: 48) {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(recap.monthName) en quatre chiffres".uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(1.2)
                Text(recap.verdict)
                    .font(.system(size: 72, design: .serif).italic())
                    .tracking(-2)
                    .fixedSize(horizontal: false, vertical: true)
                Button { saveImage() } label: {
                    Text("Enregistrer l'image")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 44)
                        .background(Capsule().fill(theme.pop))
                }
                .buttonStyle(.pressable)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            summaryTiles
        }
    }

    private var summaryTiles: some View {
        let cells: [(String, String, UInt32, UInt32)] = [
            (num(recap.total), unitWord, 0x1F3FD1, 0xFBF9F4),
            ("\(recap.writingDays)", recap.writingDays > 1 ? "jours d'écriture" : "jour d'écriture", 0x11100F, 0xFBF9F4),
            (num(recap.bestValue), "meilleur jour", 0xB3261E, 0xFFF5EE),
            ("\(recap.sheets)", "feuillets", 0xE8B84A, 0x1B1A17)
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(196), spacing: 14), count: 2), spacing: 14) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                VStack(alignment: .leading, spacing: 8) {
                    Text(cell.0)
                        .font(.system(size: 36, weight: .light, design: .monospaced))
                        .tracking(-1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(cell.1).font(.system(size: 14))
                }
                .foregroundColor(Self.hex(cell.3))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Self.hex(cell.2)))
            }
        }
        .frame(width: 2 * 196 + 14)
    }

    // MARK: Image du résumé

    @MainActor private func saveImage() {
        let card = VStack(alignment: .leading, spacing: 18) {
            Text("WRITING PROCESS · \(recap.monthName.uppercased())")
                .font(.system(size: 12, weight: .semibold))
                .kerning(1.2)
            Text(recap.verdict)
                .font(.system(size: 54, design: .serif).italic())
            summaryTiles
        }
        .foregroundColor(Self.hex(0x1B1A17))
        .padding(40)
        .background(Self.hex(0xFBF9F4))

        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Récap \(recap.monthName).png"
        if panel.runModal() == .OK, let url = panel.url {
            try? png.write(to: url)
        }
    }
}

// MARK: - 5.26 Page « Récaps du mois » : tous les mois écoulés

struct MonthlyRecapArchiveView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    private struct Entry: Identifiable {
        let id: String
        let recap: MonthlyRecap
    }

    @State private var entries: [Entry] = []
    @State private var opened: Entry? = nil

    private var unitWord: String { store.data.useWordCount ? "mots" : "signes" }
    private func num(_ value: Int) -> String {
        DataStore.formatNumber(store.data.useWordCount ? value / 5 : value)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Un récap par mois écoulé, du plus récent au plus ancien")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.labelMuted)
                        Text("Récaps du mois")
                            .font(.system(size: 26, weight: .heavy))
                            .tracking(-0.6)
                    }
                    Spacer()
                    Button {
                        withAppAnimation(Motion.panel) { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .appGlass(in: Circle())
                    }
                    .buttonStyle(.pressable)
                    .help(showSidebar ? "Masquer la barre latérale" : "Afficher la barre latérale")
                    .accessibilityLabel("Barre latérale")
                }
                if entries.isEmpty {
                    EmptyStateView(icon: "rectangle.stack", title: "Pas encore de récap",
                                   message: "Le premier récap apparaîtra au début du mois prochain, dès qu'un mois complet aura des saisies.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 215, maximum: 420), spacing: 14)], spacing: 14) {
                    ForEach(entries) { entry in
                        card(entry)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(Color.appBg.ignoresSafeArea())
        .onAppear(perform: reload)
        .sheet(item: $opened) { entry in
            MonthlyRecapView(store: store, recap: MonthlyRecap.compute(store: store, monthStart: entry.recap.monthStart))
        }
    }

    private func reload() {
        entries = MonthlyRecap.availableMonths(store: store).map { month in
            Entry(id: MonthlyRecap.monthKey(month),
                  recap: MonthlyRecap.compute(store: store, monthStart: month, includeChapter: false))
        }
    }

    private func card(_ entry: Entry) -> some View {
        let recap = entry.recap
        return Button { opened = entry } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(MonthlyRecap.yearText(recap.monthStart))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.labelMuted)
                Text(recap.monthName.capitalized)
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .tracking(-0.6)
                    .foregroundColor(.accentWarm)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(num(recap.total)) \(unitWord)")
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                Text("\(recap.writingDays) jour\(recap.writingDays > 1 ? "s" : "") d'écriture · \(recap.verdict)")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.cardBg))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help("Ouvrir le récap de \(recap.monthName) \(MonthlyRecap.yearText(recap.monthStart))")
    }
}
