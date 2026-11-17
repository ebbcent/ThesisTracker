import SwiftUI

// MARK: - Main View

struct NotificationCenterView: View {
    @ObservedObject var store: AppNotificationStore = .shared
    @State private var selectedCategory: AppNotificationCategory? = nil

    private var filtered: [AppNotification] {
        guard let cat = selectedCategory else { return store.notifications }
        return store.notifications.filter { $0.category == cat }
    }

    // Group by relative day label, preserving order
    private var grouped: [(label: String, items: [AppNotification])] {
        var result: [(label: String, items: [AppNotification])] = []
        var seen: [String: Int] = [:]
        for notif in filtered {
            let label = Self.dayLabel(notif.date)
            if let idx = seen[label] {
                result[idx].items.append(notif)
            } else {
                seen[label] = result.count
                result.append((label: label, items: [notif]))
            }
        }
        return result
    }

    private var usedCategories: [AppNotificationCategory] {
        let used = Set(store.notifications.map { $0.category })
        return AppNotificationCategory.allCases.filter { used.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.notifications.isEmpty {
                categoryFilter
            }
            Divider().overlay(Color.cardBorder)
            content
        }
        .sheetFrame(width: 360, height: 500)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20), style: .continuous))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                if store.unreadCount > 0 {
                    Text("\(store.unreadCount) non lue\(store.unreadCount > 1 ? "s" : "")")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if store.unreadCount > 0 {
                    Button {
                        withAppAnimation(.easeInOut(duration: 0.18)) { store.markAllRead() }
                    } label: {
                        Text("Tout lire")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.accent)
                    }
                    .buttonStyle(.pressable)
                }

                if !store.notifications.isEmpty {
                    Button {
                        withAppAnimation(.easeInOut(duration: 0.18)) { store.clearAll() }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                            .padding(5)
                            .background(Color.fieldBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .help("Tout effacer")
                    .accessibilityLabel("Tout effacer")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Category filter chips

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(label: "Tout", icon: nil, isSelected: selectedCategory == nil, color: .accent) {
                    withAppAnimation(.easeInOut(duration: 0.15)) { selectedCategory = nil }
                }
                ForEach(usedCategories, id: \.self) { cat in
                    chip(label: cat.displayName, icon: cat.icon, isSelected: selectedCategory == cat, color: cat.color) {
                        withAppAnimation(.easeInOut(duration: 0.15)) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private func chip(label: String, icon: String?, isSelected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? color : Color.fieldBg)
            )
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 26))
                    .foregroundColor(.labelMuted.opacity(0.5))
                Text(selectedCategory == nil ? "Aucune notification" : "Aucune notification dans cette catégorie")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(grouped, id: \.label) { group in
                        Section {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, notif in
                                NotificationRow(notif: notif, store: store)
                                if idx < group.items.count - 1 {
                                    Divider()
                                        .padding(.leading, 54)
                                        .overlay(Color.cardBorder.opacity(0.6))
                                }
                            }
                        } header: {
                            Text(group.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.labelMuted)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.cardBg.opacity(0.95))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    static func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        let daysAgo = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysAgo < 7 {
            fmt.dateFormat = "EEEE"
            return fmt.string(from: date).capitalized
        }
        fmt.dateFormat = "d MMMM"
        return fmt.string(from: date)
    }
}

// MARK: - Row

struct NotificationRow: View {
    let notif: AppNotification
    @ObservedObject var store: AppNotificationStore
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Category icon + unread dot
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppLook.r(9, 13), style: .continuous)
                        .fill(notif.category.color.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: notif.category.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(notif.category.color)
                }
                if !notif.isRead {
                    Circle()
                        .fill(Color.accent)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.cardBg, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                Text(notif.title)
                    .font(.system(size: 13, weight: notif.isRead ? .regular : .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                if !notif.body.isEmpty {
                    Text(notif.body)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(timeAgo(notif.date))
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted.opacity(0.65))
                    .padding(.top, 1)
            }

            Spacer(minLength: 4)

            // Toggle read button (visible on hover)
            Button {
                withAppAnimation(.easeInOut(duration: 0.15)) {
                    if notif.isRead {
                        store.markAsUnread(notif.id)
                    } else {
                        store.markAsRead(notif.id)
                    }
                }
            } label: {
                Image(systemName: notif.isRead ? "circle" : "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(notif.isRead ? .labelMuted.opacity(0.35) : .accent)
                    .opacity(hovering || !notif.isRead ? 1 : 0.3)
            }
            .buttonStyle(.pressable)
            .help(notif.isRead ? "Marquer comme non lu" : "Marquer comme lu")
            .accessibilityLabel(notif.isRead ? "Marquer comme non lu" : "Marquer comme lu")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            notif.isRead
                ? Color.clear
                : Color.accent.opacity(hovering ? 0.06 : 0.03)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if !notif.isRead {
                withAppAnimation(.easeInOut(duration: 0.15)) { store.markAsRead(notif.id) }
            }
        }
        .contextMenu {
            Button(notif.isRead ? "Marquer comme non lu" : "Marquer comme lu") {
                if notif.isRead { store.markAsUnread(notif.id) } else { store.markAsRead(notif.id) }
            }
            Divider()
            Button("Supprimer", role: .destructive) { store.delete(notif.id) }
        }
        .appAnimation(.easeInOut(duration: 0.12), value: notif.isRead)
    }

    private func timeAgo(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 60 { return "À l'instant" }
        if diff < 3600 { return "Il y a \(diff / 60) min" }
        if diff < 86400 { return "Il y a \(diff / 3600) h" }
        let days = diff / 86400
        if days == 1 { return "Hier" }
        return "Il y a \(days) jours"
    }
}
