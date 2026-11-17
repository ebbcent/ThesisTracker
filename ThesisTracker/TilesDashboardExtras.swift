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
        HStack(spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                cell(item)
            }
        }
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
            .frame(width: 22, height: 22)
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

    private struct Upcoming { let slot: WritingSlot; let dayOffset: Int; let date: Date; let ongoing: Bool }

    private var upcoming: Upcoming? {
        let cal = DataStore.gregorianCal
        let now = Date()
        let today = cal.startOfDay(for: now)
        let nowMinutes = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        for offset in 0..<8 {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let weekday = cal.component(.weekday, from: date)
            let candidates = store.writingSlots
                .filter { $0.weekdays.contains(weekday) && $0.startTime != nil }
                .sorted { $0.start < $1.start }
            for slot in candidates {
                guard let time = slot.startTime else { continue }
                let startMinutes = time.hour * 60 + time.minute
                if offset == 0 {
                    if startMinutes + max(0, slot.durationMinutes) <= nowMinutes { continue }
                    return Upcoming(slot: slot, dayOffset: 0, date: date, ongoing: startMinutes <= nowMinutes)
                }
                return Upcoming(slot: slot, dayOffset: offset, date: date, ongoing: false)
            }
        }
        return nil
    }

    private func dayWord(_ up: Upcoming) -> String {
        if up.ongoing { return "En ce moment" }
        if up.dayOffset == 0 { return "Aujourd'hui" }
        if up.dayOffset == 1 { return "Demain" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE"
        let s = f.string(from: up.date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Prochain créneau")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TilesTheme.green)
            if let up = upcoming {
                Text("\(up.slot.start)–\(up.slot.endText)")
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .tracking(-1.5)
                    .foregroundColor(TilesTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("\(dayWord(up)) · \(up.slot.displayLabel)")
                    .font(.system(size: 13))
                    .foregroundColor(TilesTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Aucun")
                    .font(.system(size: 40, weight: .heavy))
                    .tracking(-1.5)
                    .foregroundColor(TilesTheme.ink)
                Text("Les créneaux d'écriture se règlent dans les Réglages.")
                    .font(.system(size: 13))
                    .foregroundColor(TilesTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Session")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TilesTheme.blue)
            Text(isIdle ? "Prêt" : clock)
                .font(.system(size: 40, weight: .heavy).monospacedDigit())
                .tracking(-1.5)
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
