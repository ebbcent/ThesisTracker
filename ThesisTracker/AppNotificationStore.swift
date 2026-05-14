import Foundation
import SwiftUI
import Combine

// MARK: - Category

enum AppNotificationCategory: String, Codable, CaseIterable {
    case deadline  = "deadline"
    case streak    = "streak"
    case progress  = "progress"
    case reminder  = "reminder"
    case milestone = "milestone"
    case report    = "report"

    var icon: String {
        switch self {
        case .deadline:  return "calendar.badge.exclamationmark"
        case .streak:    return "flame.fill"
        case .progress:  return "chart.bar.fill"
        case .reminder:  return "bell.fill"
        case .milestone: return "star.fill"
        case .report:    return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .deadline:  return .orange
        case .streak:    return Color(red: 0.961, green: 0.620, blue: 0.043)
        case .progress:  return Color.accentGreen
        case .reminder:  return Color.accent
        case .milestone: return Color(red: 0.749, green: 0.318, blue: 0.918)
        case .report:    return Color(red: 0.247, green: 0.502, blue: 0.965)
        }
    }

    var displayName: String {
        switch self {
        case .deadline:  return "Échéances"
        case .streak:    return "Série"
        case .progress:  return "Progression"
        case .reminder:  return "Rappels"
        case .milestone: return "Jalons"
        case .report:    return "Rapports"
        }
    }

    // Infer category from UNNotification request identifier
    static func from(identifier: String) -> AppNotificationCategory {
        if identifier.hasPrefix("deadline-") || identifier.hasPrefix("pace-") || identifier == "deadline-conflict" {
            return .deadline
        } else if identifier.hasPrefix("streak-") || identifier == "bravo-streak-2" {
            return .streak
        } else if identifier.hasPrefix("milestone-") {
            return .milestone
        } else if identifier.hasPrefix("weekly-") || identifier.hasPrefix("daily-recap") || identifier == "daily-summary" {
            return .report
        } else if identifier == "double-goal" || identifier == "bg-goal-reached" || identifier.hasPrefix("plateau-") {
            return .progress
        } else {
            return .reminder
        }
    }
}

// MARK: - Model

struct AppNotification: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var date: Date
    var category: AppNotificationCategory
    var isRead: Bool = false
}

// MARK: - Store

class AppNotificationStore: ObservableObject {
    static let shared = AppNotificationStore()

    @Published private(set) var notifications: [AppNotification] = []

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    private let storageKey = "appNotificationsV1"

    private init() {
        load()
    }

    // MARK: - Recording

    func record(title: String, body: String, category: AppNotificationCategory) {
        let notif = AppNotification(
            title: title,
            body: body,
            date: Date(),
            category: category
        )
        DispatchQueue.main.async {
            self.notifications.insert(notif, at: 0)
            if self.notifications.count > 150 {
                self.notifications = Array(self.notifications.prefix(150))
            }
            self.save()
        }
    }

    // MARK: - Read state

    func markAsRead(_ id: UUID) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[idx].isRead = true
        save()
    }

    func markAsUnread(_ id: UUID) {
        guard let idx = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[idx].isRead = false
        save()
    }

    func markAllRead() {
        for idx in notifications.indices { notifications[idx].isRead = true }
        save()
    }

    // MARK: - Deletion

    func delete(_ id: UUID) {
        notifications.removeAll { $0.id == id }
        save()
    }

    func clearAll() {
        notifications = []
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AppNotification].self, from: data)
        else { return }
        notifications = decoded
    }
}
