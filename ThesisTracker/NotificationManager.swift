import Foundation
import UserNotifications
import SwiftUI
import AppKit

class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    // MARK: - Préférences (UserDefaults)

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ntfEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "ntfEnabled") }
    }

    var hour: Int {
        get {
            guard UserDefaults.standard.object(forKey: "ntfHour") != nil else { return 20 }
            return UserDefaults.standard.integer(forKey: "ntfHour")
        }
        set { UserDefaults.standard.set(newValue, forKey: "ntfHour") }
    }

    var minute: Int {
        get { UserDefaults.standard.integer(forKey: "ntfMinute") }
        set { UserDefaults.standard.set(newValue, forKey: "ntfMinute") }
    }

    /// Jours actifs — numéros Calendar : 1=Dim, 2=Lun, 3=Mar, 4=Mer, 5=Jeu, 6=Ven, 7=Sam
    var activeDays: Set<Int> {
        get {
            guard let arr = UserDefaults.standard.array(forKey: "ntfDays") as? [Int] else {
                return Set(2...6)   // Lun–Ven par défaut
            }
            return Set(arr)
        }
        set { UserDefaults.standard.set(Array(newValue), forKey: "ntfDays") }
    }

    // MARK: - Délégué unique & catégories partagées

    /// Préfixe des identifiants de notifications Pomodoro (gérées par PomodoroTimerNotificationManager).
    static let pomodoroIdentifierPrefix = "pomodoro."

    /// Préfixes des notifications planifiées par ce gestionnaire (seules celles-ci sont annulées par `cancelAll`).
    private static let ownedIdentifierPrefixes = [
        "wt-daily-", "deadline-", "pace-", "streak-", "daily-", "plateau-", "bravo-",
        "milestone-", "weekly-", "double-goal", "empty-day-", "bg-goal-"
    ]

    /// Actions des notifications Pomodoro, transmises par le délégué unique (identifiant d'action).
    var pomodoroResponseHandler: ((String) -> Void)?

    /// 5.11 — bouton « Démarrer » d'un rappel de créneau d'écriture (identifiant du créneau).
    var writingSlotStartHandler: ((UUID) -> Void)?

    /// 5.14 — clic sur la notification « Le professeur a répondu ».
    var professorReplyHandler: (() -> Void)?
    static let professorIdentifierPrefix = "professor-reply"

    /// 5.14 — réponse du professeur arrivée hors de vue : notification immédiate.
    func sendProfessorReply(preview: String) {
        let content = UNMutableNotificationContent()
        content.title = "L. Vandenbossche a répondu"
        content.body = preview
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let identifier = Self.professorIdentifierPrefix
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// 5.30 — accomplissement nouvellement gagné.
    func sendAchievementUnlocked(name: String, detail: String) {
        let content = UNMutableNotificationContent()
        content.title = "Accomplissement gagné : \(name)"
        content.body = detail + ". À retrouver dans « Accomplissements »."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "achievement-\(name)", content: content, trigger: nil))
    }

    /// 5.26 — récap du mois écoulé disponible : notification immédiate, une fois par mois.
    func sendMonthlyRecapReady(monthName: String, summary: String) {
        let content = UNMutableNotificationContent()
        content.title = "Ton récap de \(monthName) est prêt"
        content.body = summary + " À retrouver dans « Récaps du mois »."
        content.sound = .default
        let identifier = "monthly-recap"
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    /// `setNotificationCategories` remplace TOUTES les catégories : on les cumule ici.
    private var registeredCategories: [String: UNNotificationCategory] = [:]

    func registerCategories(_ categories: [UNNotificationCategory]) {
        for category in categories {
            registeredCategories[category.identifier] = category
        }
        center.setNotificationCategories(Set(registeredCategories.values))
    }

    // MARK: - Init

    override init() {
        super.init()
        // Seul délégué de UNUserNotificationCenter pour toute l'app
        center.delegate = self
    }

    // MARK: - Permissions

    func requestPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Dernière erreur renvoyée par macOS lors de la demande d'autorisation (diagnostic).
    private(set) var lastAuthorizationError: String?

    /// Demande l'autorisation à chaque lancement, indépendamment du Pomodoro.
    /// Sans effet visible si l'utilisateur a déjà répondu ; garde l'erreur éventuelle
    /// (par ex. « Notifications are not allowed for this application ») pour le diagnostic.
    func ensureAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
            DispatchQueue.main.async {
                self.lastAuthorizationError = error?.localizedDescription
            }
        }
    }

    /// État détaillé, lisible, des réglages de notifications de l'app dans macOS.
    func diagnostic(completion: @escaping (UNAuthorizationStatus, String) -> Void) {
        center.getNotificationSettings { settings in
            var parts: [String] = []
            switch settings.authorizationStatus {
            case .authorized:    parts.append("Autorisées")
            case .provisional:   parts.append("Autorisées sans alerte (provisoire)")
            case .denied:        parts.append("Refusées dans les Réglages Système")
            case .notDetermined: parts.append("Jamais demandées")
            case .ephemeral:     parts.append("Éphémères")
            @unknown default:    parts.append("État inconnu")
            }
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                switch settings.alertStyle {
                case .none:   parts.append("style « Aucun » : rien ne s'affiche à l'écran")
                case .banner: parts.append("style Bannières")
                case .alert:  parts.append("style Alertes")
                @unknown default: break
                }
                if settings.soundSetting == .disabled { parts.append("son coupé") }
                if settings.notificationCenterSetting == .disabled { parts.append("absentes du centre de notifications") }
                if settings.timeSensitiveSetting == .disabled { parts.append("notifications urgentes désactivées") }
            }
            DispatchQueue.main.async {
                if let error = self.lastAuthorizationError { parts.append("erreur macOS : \(error)") }
                completion(settings.authorizationStatus, parts.joined(separator: " · "))
            }
        }
    }

    /// Notification de test, envoyée dans 5 secondes (le temps de passer sur une autre app).
    func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test des notifications"
        content.body = "Si tu lis ceci, les notifications de Writing Process fonctionnent."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.removeDeliveredNotifications(withIdentifiers: ["test-notification"])
        center.add(UNNotificationRequest(identifier: "test-notification", content: content, trigger: trigger)) { error in
            if let error {
                DispatchQueue.main.async { self.lastAuthorizationError = error.localizedDescription }
            }
        }
    }

    /// Ouvre directement la page « Writing Process » des réglages de notifications de macOS.
    static func openSystemNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.writingprocess.app"
        let candidates = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
            "x-apple.systempreferences:com.apple.preference.notifications"
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
    }

    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Planification

    func scheduleNotifications() {
        // Ne retirer que nos rappels quotidiens (pas les notifications Pomodoro / deadlines…)
        center.removePendingNotificationRequests(withIdentifiers: (1...7).map { "wt-daily-\($0)" })
        guard isEnabled && !activeDays.isEmpty else { return }

        let content = UNMutableNotificationContent()
        content.title = "Writing Process"
        content.body = "N'oubliez pas d'écrire aujourd'hui ✍️"
        content.sound = .default

        for weekday in activeDays {
            var comps = DateComponents()
            comps.hour = hour
            comps.minute = minute
            comps.weekday = weekday
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: "wt-daily-\(weekday)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func cancelAll() {
        let prefixes = Self.ownedIdentifierPrefixes
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .map { $0.identifier }
                .filter { identifier in prefixes.contains { identifier.hasPrefix($0) } }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: - Deadline notifications

    func scheduleDeadlineNotifications(chaptersWithDeadlines: [(project: Project, chapter: Chapter)]) {
        // Supprime les anciennes notifs deadline
        center.getPendingNotificationRequests { requests in
            let deadlineIds = requests.filter { $0.identifier.hasPrefix("deadline-") }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: deadlineIds)

            let cal = Calendar(identifier: .gregorian)
            let today = Date()
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"

            for item in chaptersWithDeadlines {
                guard let deadlineStr = item.chapter.deadline,
                      let deadlineDate = fmt.date(from: deadlineStr) else { continue }

                for daysAhead in [7, 3, 1] {
                    guard let notifDate = cal.date(byAdding: .day, value: -daysAhead, to: deadlineDate),
                          notifDate > today else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = "📅 Échéance proche — \(item.chapter.name)"
                    content.body = daysAhead == 1
                        ? "Demain : échéance de « \(item.chapter.name) » (projet : \(item.project.name))"
                        : daysAhead == 7
                        ? "⚡️ 1 semaine avant l'échéance de « \(item.chapter.name) » (projet : \(item.project.name))"
                        : "Dans \(daysAhead) jours : échéance de « \(item.chapter.name) » (projet : \(item.project.name))"
                    content.sound = .default

                    var comps = cal.dateComponents([.year, .month, .day], from: notifDate)
                    comps.hour = 9; comps.minute = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let id = "deadline-\(item.chapter.id.uuidString)-\(daysAhead)d"
                    self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                }
            }
        }
    }

    // MARK: - Deadline pace alert (amélioration #14)

    struct DeadlinePaceItem {
        let chapterName: String
        let projectName: String
        let deadline: Date
        let etaDate: Date
        let requiredPerDay: Int
        let currentPerDay: Int
        let useWordCount: Bool
    }

    func scheduleDeadlinePaceAlerts(_ items: [DeadlinePaceItem]) {
        center.getPendingNotificationRequests { requests in
            let paceIds = requests.filter { $0.identifier.hasPrefix("pace-") }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: paceIds)

            let cal = Calendar(identifier: .gregorian)
            let now = Date()

            for (index, item) in items.prefix(3).enumerated() {
                guard item.etaDate > item.deadline else { continue } // déjà dans les temps
                let daysLate = cal.dateComponents([.day], from: item.deadline, to: item.etaDate).day ?? 0
                guard daysLate > 0 else { continue }

                let unit = item.useWordCount ? "mots" : "car."
                let needed = item.useWordCount ? item.requiredPerDay / 5 : item.requiredPerDay

                let content = UNMutableNotificationContent()
                content.title = "⚠️ Retard — \(item.chapterName)"
                content.body = "À ton rythme : fin le \(Self.shortDate(item.etaDate)) · Échéance : \(Self.shortDate(item.deadline)) (+\(daysLate)j). Besoin de +\(DataStore.formatNumber(needed)) \(unit)/jour."
                content.sound = .default

                // Demain matin à 8h
                guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { continue }
                var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
                comps.hour = 8; comps.minute = 0
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let id = "pace-\(index)-\(now.timeIntervalSince1970)"
                self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    // MARK: - Streak danger warning (V5 — #67)

    var streakWarningEnabled: Bool {
        guard UserDefaults.standard.object(forKey: "ntfStreakWarning") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "ntfStreakWarning")
    }

    /// Heure de l'alerte "série en danger" — défaut 23h (1 h avant minuit)
    var streakWarningHour: Int {
        get {
            guard UserDefaults.standard.object(forKey: "ntfStreakWarningHour") != nil else { return 23 }
            return UserDefaults.standard.integer(forKey: "ntfStreakWarningHour")
        }
        set { UserDefaults.standard.set(newValue, forKey: "ntfStreakWarningHour") }
    }
    var streakWarningMinute: Int {
        get { UserDefaults.standard.integer(forKey: "ntfStreakWarningMinute") }
        set { UserDefaults.standard.set(newValue, forKey: "ntfStreakWarningMinute") }
    }

    func scheduleStreakWarningIfNeeded(currentStreak: Int, hasWrittenToday: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: ["streak-warning"])
        guard isEnabled, streakWarningEnabled, !hasWrittenToday, currentStreak > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "🔥 Ta série est en danger !"
        content.body  = currentStreak == 1
            ? "Tu as commencé une série hier — écris au moins quelques mots pour la maintenir !"
            : "Série de \(currentStreak) jours en jeu — tu n'as pas encore écrit aujourd'hui."
        content.sound = .default

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = streakWarningHour; comps.minute = streakWarningMinute
        guard let fireDate = cal.date(from: comps), fireDate > Date() else { return }
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "streak-warning", content: content, trigger: trigger))
    }

    // MARK: - Daily summary notification

    func scheduleDailySummaryNotification(chars: Int, topProject: String?) {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-summary"])

        let content = UNMutableNotificationContent()
        content.title = "📊 Tes stats du jour sont prêtes !"
        let charsStr = DataStore.formatNumber(chars)
        if let proj = topProject {
            content.body = "\(charsStr) caractères écrits aujourd'hui · Meilleur projet : \(proj)"
        } else {
            content.body = "\(charsStr) caractères écrits aujourd'hui ✨"
        }
        content.sound = .default

        // Planifie dans 2 minutes (la notif "summary ready")
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 120, repeats: false)
        center.add(UNNotificationRequest(identifier: "daily-summary", content: content, trigger: trigger))
    }

    // MARK: - Plateau alerts (V5 — amélioration #6)

    func schedulePlateauAlerts(_ items: [DataStore.PlateauChapter]) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("plateau-") }.map { $0.identifier }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
            guard !items.isEmpty else { return }

            for (i, item) in items.prefix(2).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "📉 Plateau détecté — \(item.chapter.name)"
                let sincePart = item.daysSinceLastEntry >= 999
                    ? "Aucune écriture enregistrée"
                    : "Aucune écriture depuis \(item.daysSinceLastEntry) jour\(item.daysSinceLastEntry > 1 ? "s" : "")"
                content.body = "\(sincePart) · Échéance dans \(item.daysUntilDeadline) jours (\(item.project.name))"
                content.sound = .default

                // Notif dans 1 heure
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
                let id = "plateau-\(item.chapter.id.uuidString)-\(i)"
                self.center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }

    // MARK: - #57 Daily recap notification

    /// Planifie un récapitulatif à 19h si l'utilisateur a écrit aujourd'hui.
    /// Appelé à chaque sauvegarde — guard par date dans UserDefaults.
    func scheduleDailyRecapIfNeeded(totalToday: Int, streak: Int, dailyGoal: Int, useWordCount: Bool) {
        let enabled = UserDefaults.standard.object(forKey: "ntfDailyRecap") == nil ? true : UserDefaults.standard.bool(forKey: "ntfDailyRecap")
        guard isEnabled, enabled else { return }
        let todayKey = "lastDailyRecapDate"
        let today = Self.todayStr
        guard totalToday > 0, UserDefaults.standard.string(forKey: todayKey) != today else { return }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 19; comps.minute = 0
        guard let fireDate = cal.date(from: comps), fireDate > Date() else {
            // Déjà passé 19h — on programme quand même une notif immédiate si non envoyée
            UserDefaults.standard.set(today, forKey: todayKey)
            _sendImmediateRecap(totalToday: totalToday, streak: streak, dailyGoal: dailyGoal, useWordCount: useWordCount)
            return
        }

        UserDefaults.standard.set(today, forKey: todayKey)
        let content = UNMutableNotificationContent()
        content.title = "📝 Récapitulatif du jour"
        let count = useWordCount ? "\(DataStore.formatNumber(totalToday / 5)) mots" : "\(DataStore.formatNumber(totalToday)) car."
        let streakPart = streak > 1 ? " · 🔥 Série : \(streak) jours" : ""
        let goalPart = dailyGoal > 0 && totalToday >= dailyGoal ? " · ✅ Objectif atteint !" : ""
        content.body = "\(count) écrits aujourd'hui\(streakPart)\(goalPart)"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "daily-recap", content: content, trigger: trigger))
    }

    private func _sendImmediateRecap(totalToday: Int, streak: Int, dailyGoal: Int, useWordCount: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: ["daily-recap"])
        let content = UNMutableNotificationContent()
        content.title = "📝 Récapitulatif du jour"
        let count = useWordCount ? "\(DataStore.formatNumber(totalToday / 5)) mots" : "\(DataStore.formatNumber(totalToday)) car."
        let streakPart = streak > 1 ? " · 🔥 Série : \(streak) jours" : ""
        let goalPart = dailyGoal > 0 && totalToday >= dailyGoal ? " · ✅ Objectif atteint !" : ""
        content.body = "\(count) écrits aujourd'hui\(streakPart)\(goalPart)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        center.add(UNNotificationRequest(identifier: "daily-recap-late", content: content, trigger: trigger))
    }

    // MARK: - #58 Bravo après 2 jours consécutifs productifs

    func scheduleCongratulationsIfNeeded(streak: Int) {
        guard streak == 2 else { return }
        let key = "lastBravoStreakDate"
        let today = Self.todayStr
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)

        let content = UNMutableNotificationContent()
        content.title = "🎉 Bravo ! 2 jours d'affilée"
        content.body = "Tu as écrit 2 jours consécutifs — continue sur cette lancée !"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "bravo-streak-2", content: content, trigger: trigger))
    }

    // MARK: - #59 Milestone notifications (jalons J-7/J-3/J-1)

    /// Jalons de projet (dates définies par l'utilisateur dans ProjectMilestone).
    /// Appelé à chaque save() — supprime et replanifie toutes les notifs "milestone-".
    // #42 — Rappels personnalisables + #47 — Escalade intelligente
    struct MilestoneNotifItem {
        let projectName: String
        let milestoneName: String
        let date: Date
        let milestoneId: String
        let reminderDays: Int   // custom lead time from user
        let reminderHour: Int   // custom hour (0–23)
    }

    func scheduleMilestoneNotifications(milestones: [MilestoneNotifItem]) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("milestone-") }.map(\.identifier)
            self.center.removePendingNotificationRequests(withIdentifiers: ids)

            let cal   = Calendar(identifier: .gregorian)
            let today = Date()

            for item in milestones {
                // #47 — Escalade : 4 niveaux fixes + 1 rappel personnalisé
                // Levels: 30j info · 14j warning · 7j important · 1j urgent + custom
                let levels: [(days: Int, emoji: String, urgency: String)] = [
                    (30, "🔵", "Info"),
                    (14, "🟡", "Attention"),
                    (7,  "🟠", "Important"),
                    (1,  "🔴", "Urgent")
                ]
                // Include custom reminder day if it's distinct from the fixed levels
                var allLevels = levels
                let customDay = item.reminderDays
                if !allLevels.contains(where: { $0.days == customDay }) && customDay > 0 {
                    allLevels.append((customDay, "📌", "Rappel"))
                }

                for level in allLevels {
                    guard let notifDate = cal.date(byAdding: .day, value: -level.days, to: item.date),
                          notifDate > today else { continue }

                    let content = UNMutableNotificationContent()
                    let daysText: String
                    switch level.days {
                    case 1:  daysText = "demain"
                    case 7:  daysText = "dans 1 semaine"
                    case 14: daysText = "dans 2 semaines"
                    case 30: daysText = "dans 1 mois"
                    default: daysText = "dans \(level.days) jours"
                    }
                    content.title = "\(level.emoji) \(level.urgency) — \(item.milestoneName)"
                    content.body  = "Jalon « \(item.milestoneName) » (\(item.projectName)) · \(daysText)"
                    content.sound = level.days <= 7 ? .defaultCritical : .default

                    let useHour = item.reminderHour
                    var comps = cal.dateComponents([.year, .month, .day], from: notifDate)
                    comps.hour = useHour; comps.minute = 0
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    let uid = "milestone-\(item.milestoneId)-\(level.days)d"
                    self.center.add(UNNotificationRequest(identifier: uid, content: content, trigger: trigger))
                }
            }
        }
    }

    // MARK: - #60 Rapport push hebdomadaire (dimanche 19h)

    func scheduleWeeklyReportNotification(weekTotal: Int, daysWritten: Int, bestDay: Int, useWordCount: Bool) {
        let enabled = UserDefaults.standard.object(forKey: "ntfWeeklyReport") == nil ? true : UserDefaults.standard.bool(forKey: "ntfWeeklyReport")
        guard isEnabled, enabled else {
            center.removePendingNotificationRequests(withIdentifiers: ["weekly-report"])
            return
        }
        // Planifie pour le dimanche à 19h (weekday 1 en Calendar gregorian)
        var comps = DateComponents()
        comps.weekday = 1; comps.hour = 19; comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let total = useWordCount ? "\(DataStore.formatNumber(weekTotal / 5)) mots" : "\(DataStore.formatNumber(weekTotal)) car."
        let best  = useWordCount ? "\(DataStore.formatNumber(bestDay / 5)) mots" : "\(DataStore.formatNumber(bestDay)) car."

        let content = UNMutableNotificationContent()
        content.title = "📊 Rapport de la semaine"
        content.body  = "\(total) écrits · \(daysWritten) jour\(daysWritten > 1 ? "s" : "") actif\(daysWritten > 1 ? "s" : "") · Meilleur jour : \(best)"
        content.sound = .default

        // Supprime l'ancienne version puis replanifie
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-report"])
        center.add(UNNotificationRequest(identifier: "weekly-report", content: content, trigger: trigger))
    }

    // MARK: - #61 Alerte "objectif × 2"

    func scheduleDoubleGoalAlertIfNeeded(total: Int, goal: Int, useWordCount: Bool) {
        guard goal > 0, total >= goal * 2 else { return }
        let key = "lastDoubleGoalDate"
        let today = Self.todayStr
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)

        let count = useWordCount ? "\(DataStore.formatNumber(total / 5)) mots" : "\(DataStore.formatNumber(total)) car."
        let goalStr = useWordCount ? "\(DataStore.formatNumber(goal / 5)) mots" : "\(DataStore.formatNumber(goal)) car."

        let content = UNMutableNotificationContent()
        content.title = "🚀 Double objectif !"
        content.body  = "\(count) écrits — tu as fait le double de ton objectif (\(goalStr)) !"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        center.add(UNNotificationRequest(identifier: "double-goal", content: content, trigger: trigger))
    }

    // MARK: - #66 Rappel de saisie configurable si aucune entrée

    var emptyDayReminderEnabled: Bool {
        guard UserDefaults.standard.object(forKey: "ntfEmptyDay") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "ntfEmptyDay")
    }

    /// Heure du rappel "pas encore écrit" — défaut 20h
    var emptyDayReminderHour: Int {
        get {
            guard UserDefaults.standard.object(forKey: "ntfEmptyDayHour") != nil else { return 20 }
            return UserDefaults.standard.integer(forKey: "ntfEmptyDayHour")
        }
        set { UserDefaults.standard.set(newValue, forKey: "ntfEmptyDayHour") }
    }
    var emptyDayReminderMinute: Int {
        get { UserDefaults.standard.integer(forKey: "ntfEmptyDayMinute") }
        set { UserDefaults.standard.set(newValue, forKey: "ntfEmptyDayMinute") }
    }

    func scheduleEmptyDayReminderIfNeeded(hasWrittenToday: Bool) {
        center.removePendingNotificationRequests(withIdentifiers: ["empty-day-reminder"])
        guard isEnabled, emptyDayReminderEnabled, !hasWrittenToday else { return }

        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = emptyDayReminderHour; comps.minute = emptyDayReminderMinute
        guard let _ = cal.date(from: comps).flatMap({ $0 > Date() ? $0 : nil }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "✍️ Tu n'as pas encore écrit aujourd'hui"
        content.body  = "Quelques minutes suffisent pour maintenir ta progression. Lance une session !"
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: "empty-day-reminder", content: content, trigger: trigger))
    }

    // MARK: - #63 Notification en arrière-plan quand objectif franchi

    /// Envoie une notification immédiate si l'app n'est pas au premier plan et que l'objectif vient d'être atteint.
    func scheduleBackgroundGoalNotification(total: Int, goal: Int, useWordCount: Bool) {
        let enabled = UserDefaults.standard.object(forKey: "ntfBgGoal") == nil ? true : UserDefaults.standard.bool(forKey: "ntfBgGoal")
        guard isEnabled, enabled, goal > 0, total >= goal else { return }
        let key = "lastBgGoalDate"
        let today = Self.todayStr
        guard UserDefaults.standard.string(forKey: key) != today else { return }
        UserDefaults.standard.set(today, forKey: key)

        let count = useWordCount ? "\(DataStore.formatNumber(total / 5)) mots" : "\(DataStore.formatNumber(total)) car."
        let content = UNMutableNotificationContent()
        content.title = "✅ Objectif du jour atteint !"
        content.body  = "\(count) écrits — félicitations pour cette session productive !"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        center.add(UNNotificationRequest(identifier: "bg-goal-reached", content: content, trigger: trigger))
    }

    // MARK: - #23 Alerte chevauchement de deadlines

    func scheduleDeadlineConflictAlert(chapterNames: String, totalRequiredPerDay: Int, useWordCount: Bool) {
        let pace = useWordCount
            ? "\(DataStore.formatNumber(totalRequiredPerDay / 5)) mots/jour"
            : "\(DataStore.formatNumber(totalRequiredPerDay)) car./jour"

        let content = UNMutableNotificationContent()
        content.title = "⚠️ Chevauchement d'échéances"
        content.body  = "\(chapterNames) ont des échéances cette semaine — rythme combiné requis : \(pace). Planifie tes sessions !"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: ["deadline-conflict"])
        center.add(UNNotificationRequest(identifier: "deadline-conflict", content: content, trigger: trigger))
    }

    // MARK: - Helpers

    private static var todayStr: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    // MARK: - Delegate — afficher la bannière même si l'app est au premier plan

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .list, .sound])
        let identifier = notification.request.identifier
        let title = notification.request.content.title
        let body = notification.request.content.body
        Task { @MainActor in
            self.recordInAppCenter(identifier: identifier, title: title, body: body)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        let identifier = response.notification.request.identifier
        let title = response.notification.request.content.title
        let body = response.notification.request.content.body
        let action = response.actionIdentifier
        Task { @MainActor in
            // Record notifications delivered while the app was in background
            self.recordInAppCenter(identifier: identifier, title: title, body: body)
            // Actions Pomodoro (démarrer la pause / la session…) transmises au minuteur
            if identifier.hasPrefix(NotificationManager.pomodoroIdentifierPrefix) {
                self.pomodoroResponseHandler?(action)
            }
            if identifier.hasPrefix(NotificationManager.professorIdentifierPrefix) {
                self.professorReplyHandler?()
            }
            if action == WritingSlotScheduler.startActionIdentifier,
               let slotID = WritingSlotScheduler.slotID(fromNotificationIdentifier: identifier) {
                self.writingSlotStartHandler?(slotID)
            }
        }
        handler()
    }

    private func recordInAppCenter(identifier: String, title: String, body: String) {
        let category = AppNotificationCategory.from(identifier: identifier)
        AppNotificationStore.shared.record(
            title:    title,
            body:     body,
            category: category
        )
    }
}
