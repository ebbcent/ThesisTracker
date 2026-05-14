import Foundation
import UserNotifications

@MainActor
final class PomodoroTimerNotificationManager: NSObject {
    private let center = UNUserNotificationCenter.current()

    var onStartBreak: (() -> Void)?
    var onStartSession: (() -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        registerCategories()
    }

    private func registerCategories() {
        let startBreakAction = UNNotificationAction(
            identifier: "start-break",
            title: "Démarrer la pause",
            options: []
        )
        let skipBreakAction = UNNotificationAction(
            identifier: "skip-break",
            title: "Sauter",
            options: [.destructive]
        )
        let focusCategory = UNNotificationCategory(
            identifier: "pomodoro.focus.finished",
            actions: [startBreakAction, skipBreakAction],
            intentIdentifiers: [],
            options: []
        )

        let startSessionAction = UNNotificationAction(
            identifier: "start-session",
            title: "Démarrer la session",
            options: []
        )
        let laterAction = UNNotificationAction(
            identifier: "later",
            title: "Plus tard",
            options: []
        )
        let breakCategory = UNNotificationCategory(
            identifier: "pomodoro.break.finished",
            actions: [startSessionAction, laterAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([focusCategory, breakCategory])
    }

    func scheduleSessionFinishedNotification(mode: ActiveTimerMode, nextMode: ActiveTimerMode?, plannedDuration: TimeInterval = 25 * 60) {
        let identifier = notificationIdentifier(for: mode)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: mode)
        content.body = notificationBody(for: mode, nextMode: nextMode, plannedDuration: plannedDuration)
        content.sound = .default

        switch mode {
        case .focus:
            content.categoryIdentifier = "pomodoro.focus.finished"
        case .shortBreak, .longBreak:
            content.categoryIdentifier = "pomodoro.break.finished"
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }

    func schedulePauseReminderNotification(mode: ActiveTimerMode) {
        center.removeDeliveredNotifications(withIdentifiers: ["pomodoro.pause.reminder"])
        let content = UNMutableNotificationContent()
        content.title = "Pause non démarrée ⏳"
        content.body = mode == .longBreak
            ? "La grande pause n'a pas encore commencé. Prends une vraie pause !"
            : "La pause n'a pas encore commencé. Pense à te reposer."
        content.sound = .default
        content.categoryIdentifier = "pomodoro.break.finished"
        let request = UNNotificationRequest(identifier: "pomodoro.pause.reminder", content: content, trigger: nil)
        center.add(request)
    }

    func scheduleSessionStartedNotification(duration: TimeInterval) {
        center.removeDeliveredNotifications(withIdentifiers: ["pomodoro.session.started"])
        let content = UNMutableNotificationContent()
        content.title = "Session démarrée ⏱"
        content.body = "\(Int(duration / 60)) minutes — bonne écriture !"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pomodoro.session.started",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    private func notificationIdentifier(for mode: ActiveTimerMode) -> String {
        switch mode {
        case .focus: "pomodoro.focus.finished"
        case .shortBreak: "pomodoro.short-break.finished"
        case .longBreak: "pomodoro.long-break.finished"
        }
    }

    private func notificationTitle(for mode: ActiveTimerMode) -> String {
        switch mode {
        case .focus: "Session terminée ✓"
        case .shortBreak: "Pause terminée"
        case .longBreak: "Grande pause terminée"
        }
    }

    private func notificationBody(for mode: ActiveTimerMode, nextMode: ActiveTimerMode?, plannedDuration: TimeInterval) -> String {
        switch mode {
        case .focus:
            let minutes = Int(plannedDuration / 60)
            return "\(minutes) min de concentration — prends une pause."
        case .shortBreak:
            return "Prêt pour la prochaine session ?"
        case .longBreak:
            return "Reposé ? Lance la prochaine session."
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PomodoroTimerNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case "start-break":
                self.onStartBreak?()
            case "start-session":
                self.onStartSession?()
            default:
                break
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
