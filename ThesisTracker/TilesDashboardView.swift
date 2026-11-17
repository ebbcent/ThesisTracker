import AppKit
import SwiftUI

// MARK: - 5.24 Tableau de bord « Tuiles » (VT)
//
// Troisième affichage du tableau de bord, à côté de la version actuelle (VA) et de la
// version papier (VD) : rien n'est retiré, le menu Affichage permet de revenir à l'une ou l'autre.
// Principe : une grande tuile pour le chapitre en cours, une tuile par chiffre, la saisie dans
// une capsule de verre qui flotte en bas (le contenu défile dessous).

// MARK: Couleurs (clair / sombre)

enum TilesTheme {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        func ns(_ v: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                    blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil, dynamicProvider: { trait in
            trait.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark) : ns(light)
        }))
    }

    static let bg     = dynamic(0xF1EFEA, 0x0F0E10)
    static let card   = dynamic(0xFFFFFF, 0x1C1B1E)
    static let ink    = dynamic(0x1A1917, 0xF2EFE8)
    static let muted  = dynamic(0x615C53, 0xA9A398)
    static let line   = dynamic(0xE3DFD6, 0x333136)
    static let blue   = dynamic(0x1F3FD1, 0x8FA3FF)
    static let onBlue = dynamic(0xFFFFFF, 0x0F0E10)
    static let red    = dynamic(0xB3261E, 0xFF8A7A)
    static let green  = dynamic(0x1F6B45, 0x7FD3A5)
    static let gold   = dynamic(0x8A5A00, 0xF0C36A)

    static let radius: CGFloat = 28
    /// Un feuillet = 1 500 signes.
    static let sheetSize = 1500
}

// MARK: Titre de chapitre découpé (« 4. Titre : sous-titre »)

struct TilesChapterTitle {
    let number: String?
    let title: String
    let subtitle: String?

    init(_ name: String) {
        var rest = name.trimmingCharacters(in: .whitespaces)
        var num: String? = nil
        if let dot = rest.firstIndex(of: "."), dot > rest.startIndex,
           rest[rest.startIndex..<dot].allSatisfy({ $0.isNumber }) {
            num = String(rest[rest.startIndex..<dot])
            rest = String(rest[rest.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
        }
        number = num
        if let r = rest.range(of: " : ") {
            title = String(rest[..<r.lowerBound])
            subtitle = String(rest[r.upperBound...])
        } else {
            title = rest
            subtitle = nil
        }
    }
}

// MARK: Vue

struct TilesDashboardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @AppStorage("interfaceMode") private var interfaceMode: String = "VT"
    @AppStorage("forceDarkMode") private var forceDarkMode: Bool = false
    @AppStorage("forceLightMode") private var forceLightMode: Bool = false
    @AppStorage("monthlyRecapLastSeen") private var recapLastSeen: String = ""
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText: String = ""
    @State private var savedFlash = false
    @State private var showRecap = false
    @FocusState private var inputFocused: Bool

    private var project: Project? { store.activeProject }
    private var chapter: Chapter? { store.activeChapter }
    private var unitWord: String { store.data.useWordCount ? "mots" : "signes" }

    private func num(_ value: Int) -> String {
        DataStore.formatNumber(store.data.useWordCount ? value / 5 : value)
    }

    private var inputInt: Int? {
        let cleaned = inputText.filter { !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" }
        guard !cleaned.isEmpty else { return nil }
        return Int(cleaned)
    }

    private var recap: MonthlyRecap {
        MonthlyRecap.compute(store: store, monthStart: MonthlyRecap.previousMonthStart())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let project, let chapter {
                    heroCard(project: project, chapter: chapter)
                } else {
                    emptyCard
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270, maximum: 560), spacing: 18)], spacing: 18) {
                    recapTile
                    ringTile(title: "Jour", value: store.dailyProgress, goal: store.effectiveDailyGoal, color: TilesTheme.blue)
                    ringTile(title: "Semaine", value: store.weeklyProgress, goal: store.data.weeklyGoal, color: TilesTheme.green)
                    ringTile(title: MonthlyRecap.monthName(Date()).capitalized, value: store.currentCalendarMonthProgress,
                             goal: store.data.monthlyGoal, color: TilesTheme.gold)
                    streakTile
                    deadlineTile
                    defenseTile
                    classicTile
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 1180)
            .frame(maxWidth: .infinity)
        }
        .background(TilesTheme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { entryCapsule }
        .sheet(isPresented: $showRecap) {
            MonthlyRecapView(store: store, recap: recap)
        }
        .onAppear { presentRecapIfDue() }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardSave)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .dashboardFocusInput)) { _ in inputFocused = true }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.longDate(Date()))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TilesTheme.muted)
                Text("Aujourd'hui")
                    .font(.system(size: 36, weight: .heavy))
                    .tracking(-1)
                    .foregroundColor(TilesTheme.ink)
            }
            Spacer()
            headerButton(systemImage: "sidebar.left", help: showSidebar ? "Masquer la barre latérale" : "Afficher la barre latérale") {
                withAppAnimation(Motion.panel) { showSidebar.toggle() }
            }
            headerButton(systemImage: colorScheme == .dark ? "sun.max.fill" : "moon.fill",
                         help: colorScheme == .dark ? "Passer en clair" : "Passer en sombre") {
                let goDark = colorScheme != .dark
                forceDarkMode = goDark
                forceLightMode = !goDark
            }
        }
    }

    private func headerButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(TilesTheme.ink)
                .frame(width: 38, height: 38)
                .appGlass(in: Circle(), fallback: TilesTheme.card)
        }
        .buttonStyle(.pressable)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Chapitre en cours

    private func heroCard(project: Project, chapter: Chapter) -> some View {
        let parts = TilesChapterTitle(chapter.name)
        let latest = store.latestTotal(for: chapter.id, in: project.id)
        let ratio = chapter.goal > 0 ? min(1, Double(latest) / Double(chapter.goal)) : 0
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                chapterMenu(project: project, chapter: chapter, parts: parts)
                Spacer()
                if let info = deadlineInfo(chapter.deadline) {
                    Text(info.text)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TilesTheme.red)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(parts.title)
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .tracking(-0.5)
                    .foregroundColor(TilesTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = parts.subtitle {
                    Text(subtitle)
                        .font(.system(size: 18, design: .serif).italic())
                        .foregroundColor(TilesTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 16) {
                Text(num(latest))
                    .font(.system(size: 80, weight: .heavy).monospacedDigit())
                    .tracking(-3)
                    .foregroundColor(TilesTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .appAnimation(Motion.progress, value: latest)
                Spacer(minLength: 0)
                Text(heroCaption(latest: latest, goal: chapter.goal))
                    .font(.system(size: 14))
                    .foregroundColor(TilesTheme.muted)
                    .multilineTextAlignment(.trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(TilesTheme.line)
                    Capsule().fill(TilesTheme.blue)
                        .frame(width: max(ratio > 0 ? 16 : 0, geo.size.width * ratio))
                        .appAnimation(Motion.progress, value: ratio)
                }
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityLabel("Progression du chapitre")
            .accessibilityValue("\(Int(ratio * 100)) %")
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 30)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(TilesTheme.card))
    }

    private func heroCaption(latest: Int, goal: Int) -> String {
        var s = goal > 0 ? "\(unitWord) sur \(num(goal))" : unitWord
        if !store.data.useWordCount {
            let done = latest / TilesTheme.sheetSize
            if goal > 0 {
                let all = Int((Double(goal) / Double(TilesTheme.sheetSize)).rounded(.up))
                s += " · \(done) feuillets sur \(all)"
            } else {
                s += " · \(done) feuillets"
            }
        }
        return s
    }

    private func chapterMenu(project: Project, chapter: Chapter, parts: TilesChapterTitle) -> some View {
        let label: String = {
            var s = parts.number.map { "Chapitre \($0)" } ?? project.name
            if let status = chapter.status { s += " · " + status.label.lowercased() }
            return s
        }()
        return Menu {
            ForEach(store.data.projects.filter { !$0.isArchived }) { p in
                Menu(p.name) {
                    ForEach(p.chapters.filter { !$0.isArchived }) { c in
                        Button(c.name) { select(chapter: c.id, in: p.id) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(label).font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(TilesTheme.blue)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Changer de chapitre")
    }

    private func select(chapter chapterId: UUID, in projectId: UUID) {
        guard let idx = store.data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        store.data.activeProjectId = projectId
        store.data.projects[idx].activeChapterId = chapterId
        store.save()
        inputText = ""
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aucun chapitre sélectionné")
                .font(.system(size: 24, weight: .regular, design: .serif))
                .foregroundColor(TilesTheme.ink)
            Text("Choisis ou crée un chapitre dans la barre latérale pour commencer à saisir.")
                .font(.system(size: 14))
                .foregroundColor(TilesTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(TilesTheme.card))
    }

    // MARK: Tuiles

    private func tile<Content: View>(background: Color = TilesTheme.card, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(RoundedRectangle(cornerRadius: TilesTheme.radius, style: .continuous).fill(background))
    }

    private func ringTile(title: String, value: Int, goal: Int, color: Color) -> some View {
        let ratio = goal > 0 ? min(1, max(0, Double(value) / Double(goal))) : 0
        return tile {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(TilesTheme.line, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: ratio)
                        .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .appAnimation(Motion.progress, value: ratio)
                }
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                    Text(num(value))
                        .font(.system(size: 32, weight: .heavy).monospacedDigit())
                        .tracking(-1)
                        .foregroundColor(TilesTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(goal > 0 ? "sur \(num(goal))" : "pas d'objectif")
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(ratio * 100)) % de l'objectif")
    }

    private var streakTile: some View {
        let streak = store.currentStreak
        let week = store.lastSevenDaysTotals
        return tile {
            VStack(alignment: .leading, spacing: 10) {
                Text("Série").font(.system(size: 13, weight: .semibold)).foregroundColor(TilesTheme.muted)
                Text(streak > 1 ? "\(streak) jours" : "\(streak) jour")
                    .font(.system(size: 52, weight: .heavy))
                    .tracking(-2)
                    .foregroundColor(TilesTheme.ink)
                HStack(spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, value in
                        Capsule().fill(value > 0 ? TilesTheme.ink : TilesTheme.line).frame(height: 10)
                    }
                }
                .accessibilityHidden(true)
                Text("Record : \(store.longestStreak) jours")
                    .font(.system(size: 13))
                    .foregroundColor(TilesTheme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var deadlineTile: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let next = store.chaptersWithDeadlines.first { item in
            guard let d = item.chapter.deadline.flatMap(DataStore.parseDate) else { return false }
            return Calendar.current.startOfDay(for: d) >= today
        }
        return tile {
            VStack(alignment: .leading, spacing: 8) {
                if let next, let info = deadlineInfo(next.chapter.deadline) {
                    Text("Échéance · \(next.chapter.shortLabel)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TilesTheme.red)
                        .lineLimit(1)
                    Text(info.short)
                        .font(.system(size: 52, weight: .heavy))
                        .tracking(-2)
                        .foregroundColor(TilesTheme.ink)
                    Text(deadlineCaption(for: next.chapter, in: next.project))
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Échéance").font(.system(size: 13, weight: .semibold)).foregroundColor(TilesTheme.muted)
                    Text("Aucune")
                        .font(.system(size: 52, weight: .heavy))
                        .tracking(-2)
                        .foregroundColor(TilesTheme.ink)
                    Text("Aucune échéance à venir.")
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func deadlineCaption(for chapter: Chapter, in project: Project) -> String {
        var s = chapter.deadline.flatMap(DataStore.parseDate).map(Self.dayMonth) ?? ""
        if let pace = store.requiredPacePerDay(for: chapter, in: project) {
            s += " · \(num(pace)) \(unitWord) par jour pour tenir"
        }
        return s
    }

    private var defenseTile: some View {
        tile(background: TilesTheme.ink) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Soutenance")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TilesTheme.bg.opacity(0.8))
                if let date = store.targetDefenseDate {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                               to: Calendar.current.startOfDay(for: date)).day ?? 0
                    Text(days >= 0 ? "\(days) jours" : "Passée")
                        .font(.system(size: 52, weight: .heavy))
                        .tracking(-2)
                        .foregroundColor(TilesTheme.bg)
                    Text(Self.fullDate(date) + (thesisPercent.map { " · \($0) % des chapitres écrits" } ?? ""))
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.bg.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("À définir")
                        .font(.system(size: 52, weight: .heavy))
                        .tracking(-2)
                        .foregroundColor(TilesTheme.bg)
                    Text("La date se règle dans le tableau de bord complet.")
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.bg.opacity(0.8))
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Part écrite des chapitres du projet actif (hors archivés et hors total).
    private var thesisPercent: Int? {
        guard let project else { return nil }
        let chapters = project.chapters.filter { !$0.isArchived && $0.excludedFromThesisTotal != true && $0.goal > 0 }
        let goal = chapters.reduce(0) { $0 + $1.goal }
        guard goal > 0 else { return nil }
        let written = chapters.reduce(0) { $0 + store.latestTotal(for: $1.id, in: project.id) }
        return Int((Double(written) / Double(goal) * 100).rounded())
    }

    private var recapTile: some View {
        let r = recap
        return Button { showRecap = true } label: {
            tile(background: TilesTheme.blue) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Récap du mois")
                        .font(.system(size: 13, weight: .semibold))
                    Text(r.monthName.capitalized)
                        .font(.system(size: 52, weight: .regular, design: .serif))
                        .tracking(-1.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack {
                        Text("\(num(r.total)) \(unitWord), \(r.writingDays) \(r.writingDays > 1 ? "jours" : "jour") d'écriture")
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("Voir")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(TilesTheme.blue)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(TilesTheme.onBlue))
                    }
                }
                .foregroundColor(TilesTheme.onBlue)
            }
        }
        .buttonStyle(.pressable)
        .help("Ouvrir le récap de \(r.monthName)")
    }

    private var classicTile: some View {
        Button { interfaceMode = "VA" } label: {
            tile {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tableau de bord complet")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(TilesTheme.muted)
                    Text("Tous les widgets")
                        .font(.system(size: 28, weight: .heavy))
                        .tracking(-0.8)
                        .foregroundColor(TilesTheme.ink)
                    Text("Notes, relectures, planification, saisie d'un autre jour. Retour ici par le menu Affichage.")
                        .font(.system(size: 13))
                        .foregroundColor(TilesTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.pressable)
        .help("Afficher le tableau de bord complet (⌥⌘1)")
    }

    // MARK: Saisie (capsule de verre)

    private var entryCapsule: some View {
        HStack(spacing: 10) {
            if let chapter {
                Text(chapter.shortLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(TilesTheme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 160)
                    .padding(.horizontal, 6)
            }
            TextField("Total du chapitre", text: $inputText)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundColor(TilesTheme.ink)
                .focused($inputFocused)
                .onSubmit { save() }
                .frame(width: 150)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().fill(TilesTheme.card))
                .overlay(Capsule().stroke(TilesTheme.line, lineWidth: 1))
                .accessibilityLabel("Total du chapitre")
            if let delta = typedDelta {
                Text((delta < 0 ? "−" : "+") + DataStore.formatNumber(abs(delta)))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundColor(TilesTheme.blue)
                    .frame(minWidth: 64, alignment: .leading)
            }
            Button(action: save) {
                Text(savedFlash ? "Enregistré" : "Enregistrer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(TilesTheme.onBlue)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Capsule().fill(savedFlash ? TilesTheme.green : TilesTheme.blue))
            }
            .buttonStyle(.pressable)
            .disabled(inputInt == nil || chapter == nil)
            .help("Enregistrer le total du jour (⌘S)")
            Button {
                NotificationCenter.default.post(name: .navigateToTimer, object: nil)
            } label: {
                Image(systemName: "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(TilesTheme.ink)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(TilesTheme.line, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .help("Ouvrir le minuteur")
            .accessibilityLabel("Ouvrir le minuteur")
        }
        .padding(8)
        .appGlass(in: Capsule(), legible: true, fallback: TilesTheme.card)
        .padding(.bottom, 16)
        .padding(.top, 6)
    }

    private var typedDelta: Int? {
        guard let typed = inputInt, let project, let chapter else { return nil }
        return typed - store.latestTotal(for: chapter.id, in: project.id)
    }

    private func save() {
        guard let count = inputInt, let project, let chapter else { return }
        withAppAnimation(Motion.progress) {
            store.setTotalForDate(count, for: chapter.id, in: project.id, date: DataStore.today)
        }
        inputText = ""
        withAppAnimation(Motion.quick) { savedFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAppAnimation(Motion.quick) { savedFlash = false }
        }
    }

    // MARK: Récap du mois : affichage automatique

    /// Le récap du mois écoulé s'ouvre une fois, à la première ouverture du mois.
    private func presentRecapIfDue() {
        let key = MonthlyRecap.monthKey(MonthlyRecap.previousMonthStart())
        guard recapLastSeen != key else { return }
        guard !recapLastSeen.isEmpty else {
            // Première utilisation de l'affichage Tuiles : pas d'ouverture surprise.
            recapLastSeen = key
            return
        }
        recapLastSeen = key
        if recap.total != 0 || recap.previousTotal != 0 { showRecap = true }
    }

    // MARK: Dates

    private func deadlineInfo(_ deadline: String?) -> (text: String, short: String)? {
        guard let date = deadline.flatMap(DataStore.parseDate) else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
        if days > 1 { return ("À rendre dans \(days) jours", "\(days) jours") }
        if days == 1 { return ("À rendre demain", "Demain") }
        if days == 0 { return ("À rendre aujourd'hui", "Aujourd'hui") }
        return ("Échéance dépassée de \(-days) jour\(days < -1 ? "s" : "")", "Dépassée")
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = format
        return f
    }

    static func longDate(_ date: Date) -> String {
        let s = formatter("EEEE d MMMM").string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func dayMonth(_ date: Date) -> String { formatter("d MMMM").string(from: date) }
    static func fullDate(_ date: Date) -> String { formatter("d MMMM yyyy").string(from: date) }
}
