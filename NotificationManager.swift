import Foundation
import UserNotifications
import SwiftUI

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

    var weeklyReportEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "ntfWeeklyReport") }
        set { UserDefaults.standard.set(newValue, forKey: "ntfWeeklyReport") }
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

    // MARK: - Init

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permissions

    func requestPermission(completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func getAuthorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - Planification

    func scheduleNotifications() {
        center.removeAllPendingNotificationRequests()

        if isEnabled && !activeDays.isEmpty {
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

        scheduleWeeklyReport()
    }

    func scheduleWeeklyReport() {
        center.removePendingNotificationRequests(withIdentifiers: ["wt-weekly-report"])
        guard weeklyReportEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "📊 Bilan de ta semaine"
        content.body = "Découvre tes stats de la semaine passée dans Writing Process."
        content.sound = .default
        var comps = DateComponents()
        comps.weekday = 2  // Lundi
        comps.hour = 9
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: "wt-weekly-report", content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
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

                for daysAhead in [3, 1] {
                    guard let notifDate = cal.date(byAdding: .day, value: -daysAhead, to: deadlineDate),
                          notifDate > today else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = "📅 Deadline approche — \(item.chapter.name)"
                    content.body = daysAhead == 1
                        ? "Demain est la deadline pour « \(item.chapter.name) » (projet : \(item.project.name))"
                        : "Dans \(daysAhead) jours : deadline de « \(item.chapter.name) » (projet : \(item.project.name))"
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

    // MARK: - Delegate — afficher la bannière même si l'app est au premier plan

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
