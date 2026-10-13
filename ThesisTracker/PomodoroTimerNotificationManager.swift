import Foundation
import UserNotifications

@MainActor
final class PomodoroTimerNotificationManager: NSObject {
    private let center = UNUserNotificationCenter.current()

    /// Identifiant fixe de la notification de fin de session (planifiée à l'avance).
    static let sessionEndIdentifier = "pomodoro.session.end"
    static let pauseReminderIdentifier = "pomodoro.pause.reminder"
    private static let focusFinishedCategory = "pomodoro.focus.finished"
    private static let breakFinishedCategory = "pomodoro.break.finished"
    private static let pauseReminderCategory = "pomodoro.pause.reminder"

    var onStartBreak: (() -> Void)?
    var onStartSession: (() -> Void)?
    var onSkipBreak: (() -> Void)?

    override init() {
        super.init()
    }

    func requestAuthorizationIfNeeded() async {
        // Pas de `center.delegate = self` : NotificationManager est l'unique délégué de l'app
        // et nous transmet les actions des notifications Pomodoro (branché ici, une fois au lancement,
        // pour qu'une instance d'aperçu ne détourne pas les actions).
        NotificationManager.shared.pomodoroResponseHandler = { [weak self] action in
            self?.handleAction(action)
        }
        // Catégories enregistrées à chaque lancement (pas seulement à la première autorisation)
        registerCategories()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    private func handleAction(_ action: String) {
        switch action {
        case "start-break":
            onStartBreak?()
        case "start-session":
            onStartSession?()
        case "skip-break":
            onSkipBreak?()
        default:
            break
        }
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
            identifier: Self.focusFinishedCategory,
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
            identifier: Self.breakFinishedCategory,
            actions: [startSessionAction, laterAction],
            intentIdentifiers: [],
            options: []
        )

        // Rappel « pause non démarrée » : l'action démarre la pause (et non une session)
        let reminderCategory = UNNotificationCategory(
            identifier: Self.pauseReminderCategory,
            actions: [startBreakAction, skipBreakAction],
            intentIdentifiers: [],
            options: []
        )

        // Fusion avec les catégories éventuelles des autres gestionnaires (setNotificationCategories remplace tout)
        NotificationManager.shared.registerCategories([focusCategory, breakCategory, reminderCategory])
    }

    /// Planifie à l'avance la notification de fin de session (au démarrage / à la reprise).
    /// Le son est joué par l'app (PomodoroSoundManager) : la notification est silencieuse pour éviter un double son.
    func scheduleSessionEndNotification(mode: ActiveTimerMode, plannedDuration: TimeInterval, fireIn interval: TimeInterval) {
        let identifier = Self.sessionEndIdentifier
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = notificationTitle(for: mode)
        content.body = notificationBody(for: mode, plannedDuration: plannedDuration)
        content.sound = nil

        switch mode {
        case .focus:
            content.categoryIdentifier = Self.focusFinishedCategory
        case .shortBreak, .longBreak:
            content.categoryIdentifier = Self.breakFinishedCategory
        }

        // UNTimeIntervalNotificationTrigger exige un intervalle > 0
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    /// Annule la notification de fin planifiée (pause, arrêt, veille…).
    func cancelSessionEndNotification() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.sessionEndIdentifier])
    }

    func schedulePauseReminderNotification(mode: ActiveTimerMode) {
        center.removeDeliveredNotifications(withIdentifiers: [Self.pauseReminderIdentifier])
        let content = UNMutableNotificationContent()
        content.title = "Pause non démarrée ⏳"
        content.body = mode == .longBreak
            ? "La grande pause n'a pas encore commencé. Prends une vraie pause !"
            : "La pause n'a pas encore commencé. Pense à te reposer."
        content.sound = .default
        content.categoryIdentifier = Self.pauseReminderCategory
        let request = UNNotificationRequest(identifier: Self.pauseReminderIdentifier, content: content, trigger: nil)
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

    private func notificationTitle(for mode: ActiveTimerMode) -> String {
        switch mode {
        case .focus: "Session terminée ✓"
        case .shortBreak: "Pause terminée"
        case .longBreak: "Grande pause terminée"
        }
    }

    private func notificationBody(for mode: ActiveTimerMode, plannedDuration: TimeInterval) -> String {
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
