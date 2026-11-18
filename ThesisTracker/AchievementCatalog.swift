import SwiftUI

// MARK: - 5.30 Accomplissements à progression, records, prochain badge
//
// Complète la page Accomplissements (badges de série et de volume, accomplissements généraux,
// défis de la semaine, tous conservés) par des accomplissements propres à une thèse :
// avancement du manuscrit, objectifs tenus, régularité, concentration, reprises.
//
// Principes :
// - tout est calculé à partir des données existantes (saisies, objectifs, relectures, sessions) :
//   aucun nouveau champ dans data.json, donc rien à synchroniser entre les deux Mac ;
// - chaque accomplissement a une progression (« 7 / 10 »), pas seulement un état gagné / pas gagné ;
// - les reprises comptent : revenir après une coupure est récompensé, une série cassée n'est pas punie.

struct ProgressAchievement: Identifiable {
    enum Family: String, CaseIterable, Identifiable {
        case manuscript = "Manuscrit"
        case goals = "Objectifs tenus"
        case rhythm = "Régularité"
        case focus = "Concentration"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .manuscript: return "text.book.closed.fill"
            case .goals:      return "target"
            case .rhythm:     return "calendar"
            case .focus:      return "timer"
            }
        }
    }

    let id: String
    let family: Family
    let icon: String
    let color: Color
    let name: String
    let detail: String
    let current: Int
    let target: Int
    /// Suffixe de la progression (« % », « jours »…).
    let unit: String

    var isUnlocked: Bool { current >= target }
    var ratio: Double { target > 0 ? min(1, max(0, Double(current) / Double(target))) : 0 }
    var progressText: String {
        let shown = min(current, target)
        return unit == "%" ? "\(shown) % sur \(target) %" : "\(shown) / \(target) \(unit)"
    }
}

struct WritingRecord: Identifiable {
    let id: String
    let icon: String
    let label: String
    let value: String
    let when: String
}

enum AchievementCatalog {

    private static let isoCal: Calendar = {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        return cal
    }()

    private static func weekKey(_ date: Date) -> String {
        let c = isoCal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    // MARK: Accomplissements

    static func all(store: DataStore, sessions: [PomodoroSessionRecord]) -> [ProgressAchievement] {
        let totals = store.dailyTotals()
        let written = totals.filter { $0.value > 0 }
        var out: [ProgressAchievement] = []

        // ── Manuscrit ─────────────────────────────────────────────
        let percent = manuscriptPercent(store: store)
        let steps: [(Int, String, String, String)] = [
            (25, "quarter", "Premier quart", "Un quart du manuscrit écrit"),
            (50, "half", "Mi-parcours", "La moitié du manuscrit écrite"),
            (75, "threeQuarters", "Trois quarts", "Les trois quarts du manuscrit écrits"),
            (100, "complete", "Manuscrit complet", "Tous les chapitres à leur objectif")
        ]
        for (target, key, name, detail) in steps {
            out.append(ProgressAchievement(id: "ms_\(key)", family: .manuscript, icon: "text.book.closed.fill",
                                           color: .accentWarm, name: name, detail: detail,
                                           current: percent, target: target, unit: "%"))
        }

        var atGoal = 0, deadlinesKept = 0, reviewed = 0
        for project in store.data.projects where !project.isArchived {
            for chapter in project.chapters where !chapter.isArchived {
                if chapter.supervisorReviews.contains(where: { $0.sentDate != nil }) { reviewed += 1 }
                guard chapter.goal > 0 else { continue }
                let reached = chapter.entries
                    .sorted { $0.date < $1.date }
                    .first { $0.totalCount >= chapter.goal }
                guard let reached else { continue }
                atGoal += 1
                if let deadline = chapter.deadline, reached.date <= deadline { deadlinesKept += 1 }
            }
        }
        out.append(ProgressAchievement(id: "ms_firstDraft", family: .manuscript, icon: "doc.text.fill", color: .semGreen,
                                       name: "Premier jet", detail: "Un chapitre amené à son objectif",
                                       current: atGoal, target: 1, unit: "chapitre"))
        out.append(ProgressAchievement(id: "ms_threeDrafts", family: .manuscript, icon: "doc.on.doc.fill", color: .semGreen,
                                       name: "Trois premiers jets", detail: "Trois chapitres amenés à leur objectif",
                                       current: atGoal, target: 3, unit: "chapitres"))
        out.append(ProgressAchievement(id: "ms_deadlineKept", family: .manuscript, icon: "flag.checkered", color: .semBlue,
                                       name: "Échéance tenue", detail: "Un chapitre à son objectif avant sa date limite",
                                       current: deadlinesKept, target: 1, unit: "chapitre"))
        out.append(ProgressAchievement(id: "ms_reviewed", family: .manuscript, icon: "paperplane.fill", color: .semViolet,
                                       name: "Soumis au directeur", detail: "Un chapitre envoyé en relecture",
                                       current: reviewed, target: 1, unit: "chapitre"))

        // ── Objectifs tenus ───────────────────────────────────────
        let daily = store.data.dailyGoal
        let daysMet = daily > 0 ? totals.values.filter { $0 >= daily }.count : 0
        for target in [10, 50, 100] {
            out.append(ProgressAchievement(id: "goal_days_\(target)", family: .goals, icon: "checkmark.circle.fill", color: .semAmber,
                                           name: "\(target) objectifs du jour", detail: "Atteindre l'objectif du jour \(target) fois",
                                           current: daysMet, target: target, unit: "jours"))
        }
        var perWeek: [String: Int] = [:], perMonth: [String: Int] = [:]
        var weekdaysPerWeek: [String: Set<Int>] = [:]
        for (dateString, value) in totals {
            guard let date = DataStore.parseDate(dateString) else { continue }
            let week = weekKey(date)
            perWeek[week, default: 0] += value
            perMonth[String(dateString.prefix(7)), default: 0] += value
            if value > 0 {
                weekdaysPerWeek[week, default: []].insert(isoCal.component(.weekday, from: date))
            }
        }
        let weekly = store.data.weeklyGoal, monthly = store.data.monthlyGoal
        let weeksMet = weekly > 0 ? perWeek.values.filter { $0 >= weekly }.count : 0
        let monthsMet = monthly > 0 ? perMonth.values.filter { $0 >= monthly }.count : 0
        out.append(ProgressAchievement(id: "goal_week_1", family: .goals, icon: "calendar.badge.checkmark", color: .semGreen,
                                       name: "Semaine à l'objectif", detail: "Atteindre l'objectif d'une semaine",
                                       current: weeksMet, target: 1, unit: "semaine"))
        out.append(ProgressAchievement(id: "goal_week_10", family: .goals, icon: "calendar.badge.checkmark", color: .semGreen,
                                       name: "Dix semaines à l'objectif", detail: "Atteindre l'objectif hebdomadaire dix fois",
                                       current: weeksMet, target: 10, unit: "semaines"))
        out.append(ProgressAchievement(id: "goal_month_1", family: .goals, icon: "calendar.circle.fill", color: .semPink,
                                       name: "Mois à l'objectif", detail: "Atteindre l'objectif d'un mois",
                                       current: monthsMet, target: 1, unit: "mois"))

        // ── Régularité ────────────────────────────────────────────
        let bestWorkWeek = weekdaysPerWeek.values.map { $0.filter { (2...6).contains($0) }.count }.max() ?? 0
        let bestFullWeek = weekdaysPerWeek.values.map { $0.count }.max() ?? 0
        out.append(ProgressAchievement(id: "rhythm_workweek", family: .rhythm, icon: "briefcase.fill", color: .semSky,
                                       name: "Semaine de travail", detail: "Écrire du lundi au vendredi la même semaine",
                                       current: bestWorkWeek, target: 5, unit: "jours"))
        out.append(ProgressAchievement(id: "rhythm_fullweek", family: .rhythm, icon: "7.circle.fill", color: .semSky,
                                       name: "Sept sur sept", detail: "Écrire les sept jours d'une même semaine",
                                       current: bestFullWeek, target: 7, unit: "jours"))
        let comebacks = comebackCount(writtenDates: written.keys.sorted())
        out.append(ProgressAchievement(id: "rhythm_comeback", family: .rhythm, icon: "arrow.uturn.up.circle.fill", color: .semOrange,
                                       name: "Reprise", detail: "Se remettre à écrire après deux semaines d'arrêt",
                                       current: comebacks, target: 1, unit: "reprise"))
        out.append(ProgressAchievement(id: "rhythm_comeback3", family: .rhythm, icon: "arrow.uturn.up.circle.fill", color: .semOrange,
                                       name: "Toujours revenir", detail: "Reprendre trois fois après une coupure",
                                       current: comebacks, target: 3, unit: "reprises"))

        // ── Concentration ─────────────────────────────────────────
        let focus = sessions.filter { $0.kind == .focus && $0.completionState == .completed }
        for target in [10, 50, 200] {
            out.append(ProgressAchievement(id: "focus_sessions_\(target)", family: .focus, icon: "timer", color: .semBlue,
                                           name: "\(target) blocs de concentration", detail: "Terminer \(target) blocs au minuteur",
                                           current: focus.count, target: target, unit: "blocs"))
        }
        var perDay: [String: Int] = [:]
        for session in focus { perDay[DataStore.dateString(from: session.startedAt), default: 0] += 1 }
        out.append(ProgressAchievement(id: "focus_deepday", family: .focus, icon: "bolt.fill", color: .semViolet,
                                       name: "Journée profonde", detail: "Quatre blocs terminés dans la même journée",
                                       current: perDay.values.max() ?? 0, target: 4, unit: "blocs"))
        let hours = Int(focus.reduce(0) { $0 + $1.duration } / 3_600)
        out.append(ProgressAchievement(id: "focus_hours_25", family: .focus, icon: "hourglass", color: .semPurple,
                                       name: "25 heures de concentration", detail: "Cumuler 25 heures de blocs terminés",
                                       current: hours, target: 25, unit: "heures"))
        return out
    }

    /// Part écrite du manuscrit du projet actif (chapitres non archivés, comptés dans le total, avec objectif).
    static func manuscriptPercent(store: DataStore) -> Int {
        guard let project = store.activeProject else { return 0 }
        let chapters = project.chapters.filter { !$0.isArchived && $0.countsInThesisTotal && $0.goal > 0 }
        let goal = chapters.reduce(0) { $0 + $1.goal }
        guard goal > 0 else { return 0 }
        let done = chapters.reduce(0) { $0 + min($1.goal, store.latestTotal(for: $1.id, in: project.id)) }
        return Int((Double(done) / Double(goal) * 100).rounded(.down))
    }

    /// Nombre de fois où l'écriture a repris après au moins quatorze jours sans saisie.
    static func comebackCount(writtenDates: [String]) -> Int {
        var count = 0
        var previous: Date? = nil
        for dateString in writtenDates {
            guard let date = DataStore.parseDate(dateString) else { continue }
            if let previous {
                let gap = DataStore.gregorianCal.dateComponents([.day], from: previous, to: date).day ?? 0
                if gap > 14 { count += 1 }
            }
            previous = date
        }
        return count
    }

    /// Accomplissement non gagné le plus proche du but.
    static func nearest(_ list: [ProgressAchievement]) -> ProgressAchievement? {
        list.filter { !$0.isUnlocked }.max { $0.ratio < $1.ratio }
    }

    // MARK: Records

    static func records(store: DataStore) -> [WritingRecord] {
        let totals = store.dailyTotals()
        let unit = store.data.useWordCount ? "mots" : "signes"
        func num(_ v: Int) -> String { DataStore.formatNumber(store.data.useWordCount ? v / 5 : v) }
        var out: [WritingRecord] = []

        if let best = totals.max(by: { $0.value < $1.value }), best.value > 0,
           let date = DataStore.parseDate(best.key) {
            out.append(WritingRecord(id: "day", icon: "sun.max.fill", label: "Meilleur jour",
                                     value: "\(num(best.value)) \(unit)", when: dayFormatter.string(from: date)))
        }
        var perWeek: [String: (total: Int, first: Date)] = [:]
        var perMonth: [String: Int] = [:]
        var daysPerMonth: [String: Int] = [:]
        for (dateString, value) in totals {
            guard let date = DataStore.parseDate(dateString) else { continue }
            let key = weekKey(date)
            let first = isoCal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            perWeek[key] = ((perWeek[key]?.total ?? 0) + value, first)
            let month = String(dateString.prefix(7))
            perMonth[month, default: 0] += value
            if value > 0 { daysPerMonth[month, default: 0] += 1 }
        }
        if let best = perWeek.values.max(by: { $0.total < $1.total }), best.total > 0 {
            out.append(WritingRecord(id: "week", icon: "calendar", label: "Meilleure semaine",
                                     value: "\(num(best.total)) \(unit)", when: "semaine du " + dayFormatter.string(from: best.first)))
        }
        if let best = perMonth.max(by: { $0.value < $1.value }), best.value > 0,
           let date = DataStore.parseDate(best.key + "-01") {
            out.append(WritingRecord(id: "month", icon: "calendar.circle.fill", label: "Meilleur mois",
                                     value: "\(num(best.value)) \(unit)", when: monthFormatter.string(from: date)))
        }
        if let best = daysPerMonth.max(by: { $0.value < $1.value }), best.value > 0,
           let date = DataStore.parseDate(best.key + "-01") {
            out.append(WritingRecord(id: "monthDays", icon: "checkmark.circle.fill", label: "Mois le plus régulier",
                                     value: "\(best.value) jours écrits", when: monthFormatter.string(from: date)))
        }
        out.append(WritingRecord(id: "streak", icon: "flame.fill", label: "Plus longue série",
                                 value: "\(store.longestStreak) jours", when: "en cours : \(store.currentStreak)"))
        return out
    }

    // MARK: Annonce des nouveaux accomplissements

    /// Prévient une fois pour chaque accomplissement nouvellement gagné (au plus deux à la fois).
    /// La première fois, la liste déjà gagnée est seulement mémorisée : pas de rafale de notifications.
    static func announceNew(store: DataStore, sessions: [PomodoroSessionRecord]) {
        guard !store.data.projects.isEmpty else { return }
        let key = "achievementsSeen"
        let unlocked = all(store: store, sessions: sessions).filter(\.isUnlocked)
        let ids = Set(unlocked.map(\.id))
        guard let stored = UserDefaults.standard.array(forKey: key) as? [String] else {
            UserDefaults.standard.set(Array(ids), forKey: key)
            return
        }
        let seen = Set(stored)
        let fresh = unlocked.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return }
        UserDefaults.standard.set(Array(seen.union(ids)), forKey: key)
        for achievement in fresh.prefix(2) {
            NotificationManager.shared.sendAchievementUnlocked(name: achievement.name, detail: achievement.detail)
        }
    }
}

// MARK: - Page Accomplissements : familles et records

struct AchievementFamiliesSection: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoro: PomodoroAppController

    var body: some View {
        let list = AchievementCatalog.all(store: store, sessions: pomodoro.data.sessions)
        let records = AchievementCatalog.records(store: store)
        VStack(alignment: .leading, spacing: 28) {
            if !records.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    title("Records", icon: "rosette")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(records) { record in
                            recordCard(record)
                        }
                    }
                }
            }
            ForEach(ProgressAchievement.Family.allCases) { family in
                let items = list.filter { $0.family == family }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        title(family.rawValue, icon: family.icon)
                        Spacer()
                        Text("\(items.filter(\.isUnlocked).count) sur \(items.count)")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundColor(.labelMuted)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            AchievementProgressCard(item: item)
                        }
                    }
                }
            }
        }
    }

    private func title(_ text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.accentWarm)
            Text(text).font(.system(size: 15, weight: .bold))
        }
    }

    private func recordCard(_ record: WritingRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: record.icon).font(.system(size: 12)).foregroundColor(.accentWarm)
                Text(record.label).font(.system(size: 12, weight: .semibold)).foregroundColor(.labelMuted)
            }
            Text(record.value)
                .font(.system(size: 20, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(record.when)
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: AppLook.r(12, 20), style: .continuous).fill(Color.cardBg))
        .accessibilityElement(children: .combine)
    }
}

struct AchievementProgressCard: View {
    let item: ProgressAchievement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(item.color.opacity(item.isUnlocked ? 0.18 : 0.08)).frame(width: 34, height: 34)
                    Image(systemName: item.isUnlocked ? item.icon : "lock.fill")
                        .font(.system(size: item.isUnlocked ? 14 : 12, weight: .semibold))
                        .foregroundColor(item.isUnlocked ? item.color : .labelMuted)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(item.isUnlocked ? .primary : .labelMuted)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.trackBg)
                    Capsule().fill(item.isUnlocked ? item.color : item.color.opacity(0.7))
                        .frame(width: item.ratio > 0 ? max(5, geo.size.width * item.ratio) : 0)
                }
            }
            .frame(height: 5)
            Text(item.isUnlocked ? "Gagné · " + item.progressText : item.progressText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(item.isUnlocked ? item.color : .labelMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: AppLook.r(12, 20), style: .continuous).fill(Color.cardBg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(item.detail), \(item.isUnlocked ? "gagné" : item.progressText)")
    }
}

// MARK: - Accueil Tuiles : prochain badge

struct TilesNextBadgeContent: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoro: PomodoroAppController

    var body: some View {
        let list = AchievementCatalog.all(store: store, sessions: pomodoro.data.sessions)
        let next = AchievementCatalog.nearest(list)
        VStack(alignment: .leading, spacing: 5) {
            Text("Prochain badge · \(list.filter(\.isUnlocked).count) sur \(list.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TilesTheme.gold)
                .lineLimit(1)
            if let next {
                Text(next.name)
                    .font(.system(size: 20, weight: .heavy))
                    .tracking(-0.4)
                    .foregroundColor(TilesTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(TilesTheme.line)
                        Capsule().fill(TilesTheme.gold).frame(width: next.ratio > 0 ? max(5, geo.size.width * next.ratio) : 0)
                    }
                }
                .frame(height: 6)
                Text(next.progressText)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(TilesTheme.muted)
                    .lineLimit(1)
            } else {
                Text("Tous gagnés")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundColor(TilesTheme.ink)
                Text("Il ne reste aucun accomplissement à débloquer.")
                    .font(.system(size: 12))
                    .foregroundColor(TilesTheme.muted)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
