import Foundation
import UserNotifications

// MARK: - Créneaux d'écriture récurrents (5.11)
// Stockés dans data.json (`AppData.writingSlots`), donc partagés entre les deux
// Mac. Chaque Mac programme ses rappels localement ; un interrupteur local
// (`writingSlotRemindersOnThisMac`) permet de les couper sur l'un des deux.
// Le rappel propose « Démarrer » : rien ne se lance sans un clic.

struct WritingSlot: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var weekdays: [Int] = [2, 3, 4, 5, 6]   // 1 = dim … 7 = sam
    var start: String = "09:00"              // "HH:mm"
    var durationMinutes: Int = 90
    var label: String? = nil
    var chapterId: UUID? = nil

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        weekdays        = (try? c.decodeIfPresent(LossyArray<Int>.self, forKey: .weekdays))?.elements ?? []
        start           = try c.decode(String.self, forKey: .start)
        durationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .durationMinutes)) ?? 60
        label           = try? c.decodeIfPresent(String.self, forKey: .label)
        chapterId       = try? c.decodeIfPresent(UUID.self, forKey: .chapterId)
    }

    /// (heure, minute) si `start` est valide.
    var startTime: (hour: Int, minute: Int)? {
        let parts = start.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    var endText: String {
        guard let time = startTime else { return "" }
        let total = time.hour * 60 + time.minute + max(0, durationMinutes)
        return String(format: "%02d:%02d", (total / 60) % 24, total % 60)
    }

    var displayLabel: String {
        let trimmed = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Créneau d'écriture" : trimmed
    }

    /// Un déclencheur hebdomadaire par jour coché.
    var triggerComponents: [DateComponents] {
        guard let time = startTime else { return [] }
        return Set(weekdays).filter { (1...7).contains($0) }.sorted().map { weekday in
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = time.hour
            comps.minute = time.minute
            return comps
        }
    }
}

enum WritingSlotScheduler {
    static let identifierPrefix = "writing-slot-"
    static let categoryIdentifier = "writing-slot"
    static let startActionIdentifier = "start-writing-slot"
    static let localSwitchKey = "writingSlotRemindersOnThisMac"

    static func identifier(slot: WritingSlot, weekday: Int) -> String {
        "\(identifierPrefix)\(slot.id.uuidString)-\(weekday)"
    }

    /// Identifiant du créneau à partir de celui de la notification.
    static func slotID(fromNotificationIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(identifierPrefix.count)
        return UUID(uuidString: String(rest.prefix(36)))
    }

    static var isEnabledOnThisMac: Bool {
        UserDefaults.standard.object(forKey: localSwitchKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: localSwitchKey)
    }

    /// Remplace tous les rappels de créneaux par ceux de `slots`.
    static func reschedule(_ slots: [WritingSlot]) {
        let center = UNUserNotificationCenter.current()
        NotificationManager.shared.registerCategories([
            UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [UNNotificationAction(identifier: startActionIdentifier, title: "Démarrer", options: [.foreground])],
                intentIdentifiers: [],
                options: []
            )
        ])
        let enabled = isEnabledOnThisMac
        Task {
            let pending = await center.pendingNotificationRequests()
            let old = pending.map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard enabled else { return }
            for slot in slots {
                for comps in slot.triggerComponents {
                    let content = UNMutableNotificationContent()
                    content.title = slot.displayLabel
                    content.body = "Créneau d'écriture \(slot.start)–\(slot.endText). Démarrer une session ?"
                    content.sound = .default
                    content.categoryIdentifier = categoryIdentifier
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: identifier(slot: slot, weekday: comps.weekday ?? 0),
                        content: content,
                        trigger: trigger
                    )
                    try? await center.add(request)
                }
            }
        }
    }
}

extension DataStore {
    var writingSlots: [WritingSlot] { data.writingSlots ?? [] }

    func updateWritingSlots(_ change: (inout [WritingSlot]) -> Void) {
        var slots = data.writingSlots ?? []
        change(&slots)
        data.writingSlots = slots
        save()
        WritingSlotScheduler.reschedule(slots)
    }
}
