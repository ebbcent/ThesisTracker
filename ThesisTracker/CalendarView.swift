import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date? = nil
    @State private var selectedProjectId: UUID? = nil
    @State private var pinnedLabelEdit: String = ""
    @State private var hoveredDateStr: String? = nil

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2  // Lundi
        return c
    }

    // MARK: - Données du mois

    /// Total de caractères écrits par date (projet sélectionné ou tous)
    private var charsByDate: [String: Int] {
        let projects = selectedProjectId.flatMap { id in
            store.data.projects.filter { $0.id == id }
        } ?? store.data.projects
        var result = [String: Int]()
        for project in projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    let inc = chapter.increment(for: entry.date)
                    if inc > 0 { result[entry.date, default: 0] += inc }
                }
            }
        }
        return result
    }

    /// Grille du mois : tableau de semaines, chaque semaine = 7 dates optionnelles
    private var monthGrid: [[Date?]] {
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))!
        let monthEnd   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!

        // Premier lundi avant ou égal à monthStart
        let wd = cal.component(.weekday, from: monthStart)
        let daysFromMon = (wd + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -daysFromMon, to: monthStart) else { return [] }

        var weeks: [[Date?]] = []
        var weekStart = gridStart
        while weekStart <= monthEnd {
            var week: [Date?] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: weekStart) else { week.append(nil); continue }
                // nil si hors du mois affiché
                let inMonth = cal.isDate(day, equalTo: monthStart, toGranularity: .month)
                week.append(inMonth ? day : nil)
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    private func dateStr(_ d: Date) -> String { DataStore.dateString(from: d) }

    private func intensity(chars: Int) -> Int {
        if chars == 0  { return 0 }
        if chars < 400 { return 1 }
        if chars < 1200 { return 2 }
        if chars < 2500 { return 3 }
        return 4
    }

    private func cellColor(_ level: Int, reached: Bool) -> Color {
        if reached { return Color.accentGreen }
        switch level {
        case 0: return Color.white.opacity(0.05)
        case 1: return Color.accent.opacity(0.25)
        case 2: return Color.accent.opacity(0.50)
        case 3: return Color.accent.opacity(0.75)
        default: return Color.accent
        }
    }

    // MARK: - Totaux du mois

    private var monthTotalChars: Int {
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))!
        return charsByDate.filter { dateStr, _ in
            guard let d = AppFormatters.isoDay.date(from: dateStr) else { return false }
            return cal.isDate(d, equalTo: monthStart, toGranularity: .month)
        }.values.reduce(0, +)
    }

    private var monthActiveDays: Int {
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))!
        return charsByDate.filter { dateStr, val in
            guard val > 0 else { return false }
            guard let d = AppFormatters.isoDay.date(from: dateStr) else { return false }
            return cal.isDate(d, equalTo: monthStart, toGranularity: .month)
        }.count
    }

    private var monthGoalDaysReached: Int {
        let goal = store.data.dailyGoal
        guard goal > 0 else { return 0 }
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth))!
        return charsByDate.filter { dateStr, val in
            guard val >= goal else { return false }
            guard let d = AppFormatters.isoDay.date(from: dateStr) else { return false }
            return cal.isDate(d, equalTo: monthStart, toGranularity: .month)
        }.count
    }

    private var monthDaysTotal: Int {
        let comps = cal.dateComponents([.year, .month], from: displayedMonth)
        guard let monthStart = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return 30 }
        return range.count
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView
                if !store.data.projects.isEmpty { scopeRow }
                statsRow
                calendarCard
                if let date = selectedDate { dayDetailCard(for: date) }
            }
            .padding(20)
        }
        .onAppear { goToCurrentMonth() }
        .onChange(of: selectedDate) { _, newDate in
            if let d = newDate {
                let ds = dateStr(d)
                pinnedLabelEdit = store.data.pinnedDates.first(where: { $0.date == ds })?.label ?? ""
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(showSidebar ? Color.accent.opacity(0.15) : Color.glassFill)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(showSidebar ? Color.accent.opacity(0.4) : Color.glassBorder, lineWidth: 1)))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Calendrier")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.primary)
                Text(monthTitle)
                    .font(.system(size: 12)).foregroundColor(.labelMuted)
            }

            Spacer()

            // Navigation mois
            HStack(spacing: 4) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.labelMuted)
                        .frame(width: 30, height: 30)
                        .background(Color.glassFill).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button("Aujourd'hui") {
                    withAnimation { goToCurrentMonth() }
                }
                .font(.system(size: 11, weight: .medium)).foregroundColor(.accent)
                .buttonStyle(.plain)

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(.labelMuted)
                        .frame(width: 30, height: 30)
                        .background(Color.glassFill).clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.glassBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
            }
        }
    }

    // MARK: - Scope (filtre projet)

    private var scopeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                calChip(id: nil, name: "Tous les projets")
                ForEach(store.data.projects) { p in
                    calChip(id: p.id, name: p.name)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func calChip(id: UUID?, name: String) -> some View {
        let sel = selectedProjectId == id
        return Button { selectedProjectId = id } label: {
            Text(name)
                .font(.system(size: 12, weight: sel ? .semibold : .regular))
                .foregroundColor(sel ? .white : .labelMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(sel ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(sel ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Stats du mois

    private var statsRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "Total mois",   value: fmt(monthTotalChars), unit: "car.", color: .accent)
            MiniStatCard(label: "Jours actifs", value: "\(monthActiveDays)", unit: "j",    color: .accentWarm)
            MiniStatCard(label: "Moy./jour actif",
                         value: monthActiveDays > 0 ? fmt(monthTotalChars / monthActiveDays) : "—",
                         unit: "car.", color: .accentGreen)
            if store.data.dailyGoal > 0 {
                MiniStatCard(label: "Obj. atteint",
                             value: "\(monthGoalDaysReached)",
                             unit: "/ \(monthDaysTotal) j",
                             color: .accent)
            }
        }
    }

    // MARK: - Grille calendrier

    private var calendarCard: some View {
        GlassCard {
            VStack(spacing: 10) {
                // En-têtes jours
                HStack(spacing: 0) {
                    ForEach(["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity)
                    }
                }

                Divider()

                // Semaines
                ForEach(monthGrid.indices, id: \.self) { weekIdx in
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { dayIdx in
                            if let date = monthGrid[weekIdx][dayIdx] {
                                calendarDayCell(date: date)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, minHeight: 56)
                            }
                        }
                    }
                }
            }
        }
    }

    private func calendarDayCell(date: Date) -> some View {
        let ds      = dateStr(date)
        let chars   = charsByDate[ds] ?? 0
        let goal    = store.data.dailyGoal
        let reached = goal > 0 && chars >= goal
        let level   = intensity(chars: chars)
        let isToday = ds == DataStore.today
        let isFuture = date > Date()
        let isSelected = selectedDate.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let isPinned = store.data.pinnedDates.contains(where: { $0.date == ds })

        return Button {
            withAnimation(.spring(response: 0.25)) {
                selectedDate = isSelected ? nil : date
            }
        } label: {
            VStack(spacing: 4) {
                // Numéro
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular))
                    .foregroundColor(isToday ? .accent : (isFuture ? .labelMuted.opacity(0.4) : .primary))

                // Pastille + total
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isFuture ? Color.clear : cellColor(level, reached: reached))
                        .frame(height: 28)
                    if chars > 0 && !isFuture {
                        Text(fmtShort(chars))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(level >= 2 ? .white : .primary)
                            .lineLimit(1)
                    }
                }

                // Indicateur objectif atteint / aujourd'hui
                Circle()
                    .fill(isToday ? Color.accent : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(4)
            .background(
                isSelected
                    ? Color.accent.opacity(0.12)
                    : (hoveredDateStr == ds ? Color.white.opacity(0.05) : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accent.opacity(0.35) : (isToday ? Color.accent.opacity(0.20) : Color.clear), lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.accent)
                        .padding(.top, 3).padding(.trailing, 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredDateStr = hovering ? ds : nil
        }
        .popover(isPresented: Binding(
            get: { hoveredDateStr == ds && chars > 0 && !isFuture },
            set: { if !$0 { hoveredDateStr = nil } }
        ), arrowEdge: .bottom) {
            dayHoverPopover(ds: ds, chars: chars, date: date)
        }
    }

    private func dayHoverPopover(ds: String, chars: Int, date: Date) -> some View {
        let entries: [(chapter: String, chars: Int, note: String?)] = store.data.projects.flatMap { project in
            project.chapters.compactMap { chapter -> (String, Int, String?)? in
                let inc = chapter.increment(for: ds)
                guard inc > 0 else { return nil }
                let note = chapter.entryForDate(ds)?.note
                return (chapter.name, inc, note)
            }
        }
        let goal = store.data.dailyGoal
        let pct = goal > 0 ? min(100, Int(Double(chars) / Double(goal) * 100)) : 0

        return VStack(alignment: .leading, spacing: 8) {
            Text(formattedDate(date))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)

            HStack(spacing: 10) {
                Label(fmt(chars) + " car.", systemImage: "text.cursor")
                    .font(.system(size: 11))
                    .foregroundColor(.accent)
                if goal > 0 {
                    Label("\(pct)%", systemImage: "target")
                        .font(.system(size: 11))
                        .foregroundColor(pct >= 100 ? .accentGreen : .labelMuted)
                }
            }

            if !entries.isEmpty {
                Divider()
                ForEach(entries.indices, id: \.self) { i in
                    let e = entries[i]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.chapter)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text(fmt(e.chars) + " car.")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.labelMuted)
                        }
                        if let note = e.note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                                .lineLimit(2)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 180, maxWidth: 260)
        .background(Color.cardBg)
        .darkPopoverAppearance()
    }

    // MARK: - Détail du jour sélectionné

    private func dayDetailCard(for date: Date) -> some View {
        let ds     = dateStr(date)
        let chars  = charsByDate[ds] ?? 0
        let goal   = store.data.dailyGoal
        let ratio  = goal > 0 ? min(1.0, Double(chars) / Double(goal)) : 0

        // Entrées par projet/chapitre pour ce jour
        let entries: [(project: String, chapter: String, chars: Int, note: String?)] = store.data.projects.flatMap { project in
            project.chapters.compactMap { chapter -> (String, String, Int, String?)? in
                let inc = chapter.increment(for: ds)
                guard inc > 0 else { return nil }
                let note = chapter.entryForDate(ds)?.note
                return (project.name, chapter.name, inc, note)
            }
        }

        let isPinned = store.data.pinnedDates.contains(where: { $0.date == ds })

        return GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                // Titre
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedDate(date))
                            .font(.system(size: 14, weight: .bold)).foregroundColor(.primary)
                        if chars > 0 {
                            Text(fmt(chars) + " car. écrits" + (goal > 0 ? " · \(Int(ratio * 100))% de l'objectif" : ""))
                                .font(.system(size: 12)).foregroundColor(.labelMuted)
                        } else {
                            Text("Aucune écriture ce jour").font(.system(size: 12)).foregroundColor(.labelMuted)
                        }
                    }
                    Spacer()
                    // Bouton épingler
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            store.togglePinnedDate(ds, label: pinnedLabelEdit)
                            pinnedLabelEdit = store.data.pinnedDates.first(where: { $0.date == ds })?.label ?? ""
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isPinned ? "pin.slash.fill" : "pin.fill")
                                .font(.system(size: 11))
                            Text(isPinned ? "Désépingler" : "Épingler")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(isPinned ? .labelMuted : .accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(isPinned ? Color.fieldBg : Color.accent.opacity(0.10))
                            .overlay(Capsule().stroke(isPinned ? Color.cardBorder : Color.accent.opacity(0.22), lineWidth: 1)))
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.25), value: isPinned)

                    if chars > 0 && goal > 0 {
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.08), lineWidth: 3).frame(width: 36, height: 36)
                            Circle()
                                .trim(from: 0, to: ratio)
                                .stroke(ratio >= 1 ? Color.accentGreen : Color.accent,
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 36, height: 36)
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(ratio * 100))%")
                                .font(.system(size: 8, weight: .bold)).foregroundColor(.accent)
                        }
                    }
                }

                // Label d'épingle (si épinglé)
                if isPinned {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.accent)
                        TextField("Ajouter une note…", text: $pinnedLabelEdit)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                            .onSubmit {
                                store.updatePinnedDateLabel(ds, label: pinnedLabelEdit)
                            }
                            .onChange(of: pinnedLabelEdit) { _, newVal in
                                store.updatePinnedDateLabel(ds, label: newVal)
                            }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(Color.accent.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.18), lineWidth: 1))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if !entries.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(entries.indices, id: \.self) { i in
                            let e = entries[i]
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Color.chapterColor(at: i)).frame(width: 7, height: 7)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.project == e.chapter ? e.chapter : "\(e.project) · \(e.chapter)")
                                        .font(.system(size: 12, weight: .medium)).foregroundColor(.primary)
                                    if let note = e.note, !note.isEmpty {
                                        Text(note).font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                }
                                Spacer()
                                Text(fmt(e.chars) + " car.")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.accent)
                            }
                        }
                    }
                }
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Helpers

    private var monthTitle: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMMM yyyy"
        let s = fmt.string(from: displayedMonth)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var canGoForward: Bool {
        let now = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
        return displayedMonth < now
    }

    private func changeMonth(by value: Int) {
        guard let next = cal.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        let now = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        withAnimation { displayedMonth = min(next, now) }
        selectedDate = nil
    }

    private func goToCurrentMonth() {
        let comps = cal.dateComponents([.year, .month], from: Date())
        displayedMonth = cal.date(from: comps) ?? Date()
        selectedDate = nil
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "EEEE d MMMM yyyy"
        let s = fmt.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Format court : 1 500 → "1,5k", 800 → "800"
    private func fmtShort(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: k < 10 ? "%.1fk" : "%.0fk", k)
        }
        return "\(n)"
    }
}
