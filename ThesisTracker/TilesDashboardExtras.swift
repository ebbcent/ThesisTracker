import SwiftUI

// MARK: - 5.24 Affichage « Tuiles » : chaîne des jours, chapitres, créneau, session
// Ces blocs reprennent des fonctions qui existent déjà (calendrier d'écriture, bornes
// d'objectif, créneaux, minuteur) : ils ne font que les montrer sur le nouvel accueil.

// MARK: Chaîne des jours (statuts du calendrier d'écriture)

struct TilesDayChain: View {
    @ObservedObject var store: DataStore
    var days: Int = 14

    private enum DayState { case written, neutral, missed, today }
    private struct Item { let date: Date; let state: DayState }

    private var items: [Item] {
        let cal = DataStore.gregorianCal
        let totals = store.dailyTotals()
        let today = cal.startOfDay(for: Date())
        var out: [Item] = []
        for offset in (0..<days).reversed() {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let written = (totals[DataStore.dateString(from: date)] ?? 0) > 0
            let state: DayState
            if written { state = .written }
            else if offset == 0 { state = .today }
            else if store.isNeutralStreakDay(date) { state = .neutral }
            else { state = .missed }
            out.append(Item(date: date, state: state))
        }
        return out
    }

    private static let letters = ["D", "L", "M", "M", "J", "V", "S"]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                cell(item)
            }
        }
        .fixedSize()
        .accessibilityElement()
        .accessibilityLabel("Les \(days) derniers jours")
        .accessibilityValue("\(items.filter { $0.state == .written }.count) jours écrits")
    }

    private func cell(_ item: Item) -> some View {
        let weekday = DataStore.gregorianCal.component(.weekday, from: item.date)
        let letter = Self.letters[max(0, min(6, weekday - 1))]
        let fill: Color
        let stroke: Color
        let text: Color
        let dashed: Bool
        let help: String
        switch item.state {
        case .written:
            fill = TilesTheme.ink; stroke = .clear; text = TilesTheme.card; dashed = false; help = "écrit"
        case .neutral:
            fill = .clear; stroke = TilesTheme.line; text = TilesTheme.muted; dashed = true; help = "non prévu, repos ou pause"
        case .missed:
            fill = TilesTheme.red.opacity(0.16); stroke = .clear; text = TilesTheme.red; dashed = false; help = "jour prévu, non écrit"
        case .today:
            fill = .clear; stroke = TilesTheme.blue; text = TilesTheme.blue; dashed = false; help = "aujourd'hui, pas encore écrit"
        }
        return Text(letter)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(text)
            .frame(width: 20, height: 20)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(stroke, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 3] : [])))
            .help("\(TilesDashboardView.dayMonth(item.date)) : \(help)")
    }
}

// MARK: Chapitres du projet (bornes plancher / plafond / environ)

struct TilesChapterList: View {
    @ObservedObject var store: DataStore
    let project: Project
    let onSelect: (Chapter) -> Void

    private var chapters: [Chapter] { project.chapters.filter { !$0.isArchived } }

    private func num(_ value: Int) -> String {
        DataStore.formatNumber(store.data.useWordCount ? value / 5 : value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Chapitres")
                    .font(.system(size: 22, weight: .heavy))
                    .tracking(-0.5)
                    .foregroundColor(TilesTheme.ink)
                Spacer()
                Text(project.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TilesTheme.muted)
            }
            .padding(.bottom, 8)
            if chapters.isEmpty {
                Text("Ce projet n'a pas encore de chapitre. Ajoute-en un depuis la barre latérale.")
                    .font(.system(size: 14))
                    .foregroundColor(TilesTheme.muted)
            }
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                if index > 0 { Rectangle().fill(TilesTheme.line).frame(height: 1) }
                row(chapter)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(TilesTheme.card))
    }

    private func row(_ chapter: Chapter) -> some View {
        let parts = TilesChapterTitle(chapter.name)
        let total = store.latestTotal(for: chapter.id, in: project.id)
        let isActive = project.activeChapterId == chapter.id
        let state = chapter.goalState(total: total)
        let color: Color = {
            switch state {
            case .reached:     return TilesTheme.green
            case .overCeiling: return TilesTheme.red
            default:           return isActive ? TilesTheme.blue : TilesTheme.ink
            }
        }()
        return Button { onSelect(chapter) } label: {
            HStack(alignment: .center, spacing: 16) {
                Text(parts.number ?? "·")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundColor(isActive ? TilesTheme.blue : TilesTheme.muted)
                    .frame(width: 22, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.title)
                        .font(.system(size: 16, design: .serif))
                        .foregroundColor(TilesTheme.ink)
                        .lineLimit(1)
                    Text(caption(chapter))
                        .font(.system(size: 12))
                        .foregroundColor(TilesTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                bar(chapter: chapter, total: total, color: color)
                    .frame(width: 170, height: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(num(total))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundColor(TilesTheme.ink)
                    Text(store.pagesLabel(total) ?? " ")
                        .font(.system(size: 12))
                        .foregroundColor(TilesTheme.muted)
                }
                .frame(width: 92, alignment: .trailing)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .help(isActive ? "Chapitre en cours" : "Passer à ce chapitre")
        .accessibilityLabel("\(chapter.name), \(num(total)) sur \(num(chapter.goal))")
    }

    private func caption(_ chapter: Chapter) -> String {
        var bits: [String] = []
        if chapter.goal > 0 { bits.append("\(chapter.effectiveGoalKind.label) \(num(chapter.goal))") }
        if let status = chapter.status { bits.append(status.label.lowercased()) }
        if let date = chapter.deadline.flatMap(DataStore.parseDate) {
            bits.append("échéance " + TilesDashboardView.dayMonth(date))
        }
        if !chapter.countsInThesisTotal { bits.append("hors total") }
        return bits.isEmpty ? "sans objectif" : bits.joined(separator: " · ")
    }

    /// Jauge : le plafond est marqué par un trait, la fourchette « environ » par une bande.
    private func bar(chapter: Chapter, total: Int, color: Color) -> some View {
        let goal = Double(max(0, chapter.goal))
        let kind = chapter.effectiveGoalKind
        let scale = max(1, kind == .around ? goal * (1 + Chapter.aroundTolerance) : goal, Double(total))
        let ratio = goal > 0 ? min(1, Double(total) / scale) : 0
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(TilesTheme.line)
                if goal > 0, kind == .around {
                    Rectangle()
                        .fill(TilesTheme.green.opacity(0.28))
                        .frame(width: geo.size.width * (goal * 2 * Chapter.aroundTolerance / scale))
                        .offset(x: geo.size.width * (goal * (1 - Chapter.aroundTolerance) / scale))
                }
                Capsule().fill(color).frame(width: ratio > 0 ? max(8, geo.size.width * ratio) : 0)
                if goal > 0, kind == .atMost {
                    Rectangle()
                        .fill(TilesTheme.ink)
                        .frame(width: 2, height: geo.size.height + 8)
                        .offset(x: min(geo.size.width - 2, geo.size.width * (goal / scale)), y: 0)
                }
            }
            .frame(height: geo.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Prochain créneau d'écriture

struct TilesSlotContent: View {
    @ObservedObject var store: DataStore
    @ObservedObject private var calendarService = WritingCalendarService.shared

    private struct Upcoming { let start: Date; let end: Date; let title: String; let fromCalendar: Bool }

    /// Prochain créneau : le plus proche entre les créneaux réguliers et ceux lus dans le calendrier.
    private var upcoming: Upcoming? {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        var candidates: [Upcoming] = []
        for offset in 0..<8 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: day)
            for slot in store.writingSlots where slot.weekdays.contains(weekday) {
                guard let time = slot.startTime,
                      let start = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else { continue }
                let end = start.addingTimeInterval(Double(max(0, slot.durationMinutes)) * 60)
                if end > now { candidates.append(Upcoming(start: start, end: end, title: slot.displayLabel, fromCalendar: false)) }
            }
        }
        for event in calendarService.upcoming.prefix(20) {
            candidates.append(Upcoming(start: event.start, end: event.end, title: event.title, fromCalendar: true))
        }
        return candidates.min { $0.start < $1.start }
    }

    private static let hour: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private func dayWord(_ up: Upcoming) -> String {
        let cal = Calendar.current
        if up.start <= Date() { return "En ce moment" }
        if cal.isDateInToday(up.start) { return "Aujourd'hui" }
        if cal.isDateInTomorrow(up.start) { return "Demain" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d"
        let s = f.string(from: up.start)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Prochain créneau")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TilesTheme.green)
            if let up = upcoming {
                Text("\(Self.hour.string(from: up.start))–\(Self.hour.string(from: up.end))")
                    .font(.system(size: 26, weight: .heavy).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundColor(TilesTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(dayWord(up)) · \(up.title)" + (up.fromCalendar ? " · calendrier" : ""))
                    .font(.system(size: 12))
                    .foregroundColor(TilesTheme.muted)
                    .lineLimit(2)
            } else {
                Text("Aucun")
                    .font(.system(size: 26, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundColor(TilesTheme.ink)
                Text("À régler dans Réglages › Créneaux d'écriture.")
                    .font(.system(size: 12))
                    .foregroundColor(TilesTheme.muted)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Session (minuteur et intention)

struct TilesSessionContent: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var controller: PomodoroAppController

    private var snap: PomodoroTimerSnapshot { controller.timerSnapshot }
    private var isIdle: Bool { snap.phase == .idle }

    private var clock: String {
        let seconds = max(0, Int(snap.remainingTime.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Session")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TilesTheme.blue)
            Text(isIdle ? "Prêt" : clock)
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .tracking(-0.8)
                .foregroundColor(TilesTheme.ink)
                .contentTransition(.numericText())
            if let intention = controller.activeIntention, !isIdle {
                Text("« \(intention) »")
                    .font(.system(size: 14, design: .serif).italic())
                    .foregroundColor(TilesTheme.muted)
                    .lineLimit(2)
            }
            PomodoroQuickControl(store: store)
        }
    }
}

// MARK: Changement d'apparence (Tuiles ↔ affichages d'origine)

/// Quand l'affichage change, les couleurs de l'app sont relues et la fenêtre est redessinée.
struct AppLookRefresher: ViewModifier {
    @AppStorage("interfaceMode") private var interfaceMode: String = "VT"
    @AppStorage("tilesPaper") private var paper: Bool = true
    @AppStorage("tilesAccentHex") private var accentHex: String = AppLook.defaultAccentHex
    @AppStorage("forceDarkMode") private var forceDark: Bool = false
    @AppStorage("forceLightMode") private var forceLight: Bool = false
    @State private var token = 0

    func body(content: Content) -> some View {
        content
            .tint(Color.accent)   // 5.27 — interrupteurs, curseurs et sélecteurs à la couleur d'accent
            .id(token)
            .onChange(of: interfaceMode) { _, _ in redraw() }
            .onChange(of: paper) { _, _ in redraw() }
            .onChange(of: accentHex) { _, _ in redraw() }
            .onChange(of: forceDark) { _, _ in AppLook.applyAppearance() }
            .onChange(of: forceLight) { _, _ in AppLook.applyAppearance() }
            .onAppear { AppLook.applyAppearance() }
    }

    private func redraw() {
        AppLook.refresh()
        token += 1
    }
}

// MARK: Réglage du fond (Réglages)

struct TilesLookSettingsSection: View {
    @AppStorage("tilesPaper") private var paper: Bool = true
    @AppStorage("forceDarkMode") private var forceDark: Bool = false
    @AppStorage("forceLightMode") private var forceLight: Bool = false

    /// 0 = système, 1 = clair, 2 = sombre.
    private var appearance: Binding<Int> {
        Binding(
            get: { forceDark ? 2 : (forceLight ? 1 : 0) },
            set: { value in
                forceDark = value == 2
                forceLight = value == 1
                AppLook.applyAppearance()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("APPARENCE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Apparence", selection: appearance) {
                    Text("Système").tag(0)
                    Text("Clair").tag(1)
                    Text("Sombre").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("S'applique à toute l'app, quel que soit l'affichage. Le bouton soleil / lune de l'accueil Tuiles fait la même chose.")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.bottom, 10)

            Text("FOND (AFFICHAGE TUILES)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            VStack(alignment: .leading, spacing: 8) {
                Picker("Fond", selection: $paper) {
                    Text("Papier").tag(true)
                    Text("Neutre").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("« Papier » : fond et cartes légèrement chauds, comme une feuille. « Neutre » : blanc et gris clair. La couleur d'accent de l'affichage Tuiles se choisit dans « Couleur d'accent » ; elle est distincte de celle des affichages d'origine.")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.cardBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .onChange(of: paper) { _, _ in AppLook.refresh() }
    }
}

// MARK: - 5.27 Surface flottante : verre en Tuiles, carte pleine sinon

/// Fond des éléments qui flottent au-dessus du contenu (bandeaux, bulles, saisie rapide, barres d'onglets).
/// En apparence Tuiles : verre d'Apple, dépoli pour rester lisible. Sinon : la carte pleine d'origine.
struct FloatingSurface: View {
    var radius: CGFloat

    var body: some View {
        if AppLook.tiles {
            Color.clear
                .appGlass(in: RoundedRectangle(cornerRadius: radius + 6, style: .continuous), legible: true, fallback: .cardBg)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.cardBg)
        }
    }
}

extension AppLook {
    /// Fond d'un popover : laissé au matériau du système en Tuiles (verre), carte pleine sinon.
    static var popoverBackground: Color { tiles ? .clear : .cardBg }
}
