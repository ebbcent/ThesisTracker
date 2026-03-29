import SwiftUI
import UserNotifications

struct SettingsView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    // Objectifs
    @State private var dailyGoalText: String   = ""
    @State private var weeklyGoalText: String  = ""
    @State private var monthlyGoalText: String = ""
    @State private var useWordCount: Bool = false

    // Thème couleur
    @State private var selectedAccentHex: String = "#F59E0B"
    @State private var customColor: Color = Color(red: 0.961, green: 0.620, blue: 0.043)

    private let accentPresets: [(name: String, hex: String)] = [
        ("Amber",  "#F59E0B"),
        ("Indigo", "#6366F1"),
        ("Sauge",  "#34D399"),
        ("Rose",   "#F43F5E"),
        ("Teal",   "#14B8A6"),
    ]

    // Notifications
    @State private var notificationsEnabled: Bool              = false
    @State private var notificationTime: Date                  = Date()
    @State private var notificationDays: Set<Int>              = [2, 3, 4, 5, 6]
    @State private var weeklyReportEnabled: Bool               = false
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined

    private let weekdays: [(Int, String)] = [
        (2, "Lun"), (3, "Mar"), (4, "Mer"), (5, "Jeu"),
        (6, "Ven"), (7, "Sam"), (1, "Dim")
    ]

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {

                // ── En-tête ──────────────────────────────────────────────
                HStack {
                    Text("Paramètres")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(8)
                            .background(Color.cardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // ── Objectifs ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("OBJECTIFS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.2)

                    VStack(spacing: 0) {
                        GoalRow(
                            icon: "sun.max.fill", color: Color.accent,
                            label: "Objectif journalier", subtitle: "Caractères par jour",
                            text: $dailyGoalText
                        )
                        Divider().padding(.leading, 48)
                        GoalRow(
                            icon: "calendar.badge.clock", color: Color.accentWarm,
                            label: "Objectif 30 jours", subtitle: "Caractères sur 30 jours glissants",
                            text: $monthlyGoalText
                        )
                        Divider().padding(.leading, 48)
                        GoalRow(
                            icon: "calendar", color: Color.accentGold,
                            label: "Objectif hebdomadaire", subtitle: "Caractères par semaine",
                            text: $weeklyGoalText
                        )
                    }
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cardBorder, lineWidth: 1))
                }

                // ── Affichage ─────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("AFFICHAGE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.2)

                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Color.accentGold.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "textformat.123")
                                .font(.system(size: 14)).foregroundColor(.accentGold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Afficher en mots")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                            Text("Divise les compteurs par 5 (estimation)")
                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Toggle("", isOn: $useWordCount)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .tint(.accent)
                    }
                    .padding(14)
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cardBorder, lineWidth: 1))
                }

                // ── Thème couleur ─────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("THÈME")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.2)

                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color(hex: selectedAccentHex).opacity(0.15)).frame(width: 34, height: 34)
                                Circle().fill(Color(hex: selectedAccentHex)).frame(width: 16, height: 16)
                            }
                            Text("Couleur d'accent")
                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(14)

                        Divider().padding(.leading, 48)

                        HStack(spacing: 8) {
                            ForEach(accentPresets, id: \.hex) { preset in
                                let isSelected = selectedAccentHex.uppercased() == preset.hex.uppercased()
                                Button {
                                    selectedAccentHex = preset.hex
                                    customColor = Color(hex: preset.hex)
                                } label: {
                                    VStack(spacing: 4) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: preset.hex))
                                                .frame(width: 26, height: 26)
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Text(preset.name)
                                            .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                                            .foregroundColor(isSelected ? .primary : .labelMuted)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            Divider().frame(height: 36)

                            // Color picker libre
                            ColorPicker("", selection: $customColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 26, height: 26)
                                .onChange(of: customColor) { _, newColor in
                                    selectedAccentHex = newColor.toHex()
                                }

                            Text("Perso")
                                .font(.system(size: 9))
                                .foregroundColor(.labelMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cardBorder, lineWidth: 1))
                }

                // ── Rappels ───────────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("RAPPELS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted)
                        .kerning(1.2)

                    VStack(spacing: 0) {

                        // Toggle principal
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 14)).foregroundColor(.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rappel quotidien")
                                    .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                Text("Notification à l'heure choisie")
                                    .font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(.accent)
                        }
                        .padding(14)

                        Divider().padding(.leading, 48)

                        // Rapport hebdomadaire
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 14)).foregroundColor(.accentWarm)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rapport hebdomadaire")
                                    .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                Text("Récap lundi à 9h00")
                                    .font(.system(size: 11)).foregroundColor(.labelMuted)
                            }
                            Spacer()
                            Toggle("", isOn: $weeklyReportEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .tint(.accentWarm)
                                .onChange(of: weeklyReportEnabled) { _, newValue in
                                    NotificationManager.shared.weeklyReportEnabled = newValue
                                    NotificationManager.shared.scheduleWeeklyReport()
                                }
                        }
                        .padding(14)

                        if notificationsEnabled {
                            Divider().padding(.leading, 48)

                            if permissionStatus == .denied {
                                // Permission refusée — lien réglages système
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange).font(.system(size: 13))
                                    Text("Notifications refusées dans les Réglages Système")
                                        .font(.system(size: 12)).foregroundColor(.orange)
                                    Spacer()
                                    Button("Ouvrir") { openSystemPrefs() }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accent)
                                        .buttonStyle(.plain)
                                }
                                .padding(14)

                            } else {

                                // Heure
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accentGreen.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "clock.fill")
                                            .font(.system(size: 13)).foregroundColor(.accentGreen)
                                    }
                                    Text("Heure")
                                        .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                    Spacer()
                                    DatePicker("", selection: $notificationTime,
                                               displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .datePickerStyle(.compact)
                                        .accentColor(.accent)
                                }
                                .padding(14)

                                Divider().padding(.leading, 48)

                                // Jours de la semaine
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "calendar")
                                            .font(.system(size: 13)).foregroundColor(.accentWarm)
                                    }
                                    Text("Jours")
                                        .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        ForEach(weekdays, id: \.0) { weekday, label in
                                            let isOn = notificationDays.contains(weekday)
                                            Button {
                                                if isOn && notificationDays.count > 1 {
                                                    notificationDays.remove(weekday)
                                                } else if !isOn {
                                                    notificationDays.insert(weekday)
                                                }
                                            } label: {
                                                Text(label)
                                                    .font(.system(size: 10, weight: isOn ? .bold : .regular))
                                                    .foregroundColor(isOn ? .white : .labelMuted)
                                                    .frame(width: 34, height: 24)
                                                    .background(isOn ? Color.accent : Color.fieldBg)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    .overlay(RoundedRectangle(cornerRadius: 6)
                                                        .stroke(isOn ? Color.accent : Color.cardBorder,
                                                                lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(14)
                            }
                        }
                    }
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cardBorder, lineWidth: 1))
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: notificationsEnabled)
                }

                // ── Boutons ───────────────────────────────────────────────
                HStack(spacing: 12) {
                    Button("Annuler") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.plain)
                        .keyboardShortcut(.escape)

                    Spacer()

                    Button("Enregistrer") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 440)
        .onAppear {
            // Objectifs
            dailyGoalText   = store.data.dailyGoal   > 0 ? "\(store.data.dailyGoal)"   : ""
            weeklyGoalText  = store.data.weeklyGoal  > 0 ? "\(store.data.weeklyGoal)"  : ""
            monthlyGoalText = store.data.monthlyGoal > 0 ? "\(store.data.monthlyGoal)" : ""
            useWordCount    = store.data.useWordCount
            // Thème
            selectedAccentHex = store.accentColorHex
            customColor = Color(hex: store.accentColorHex)
            // Notifications — valeurs sauvegardées
            notificationsEnabled  = NotificationManager.shared.isEnabled
            weeklyReportEnabled   = NotificationManager.shared.weeklyReportEnabled
            notificationDays      = NotificationManager.shared.activeDays
            let cal  = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.hour   = NotificationManager.shared.hour
            comps.minute = NotificationManager.shared.minute
            notificationTime = cal.date(from: comps) ?? Date()
            // Permission actuelle
            NotificationManager.shared.getAuthorizationStatus { status in
                permissionStatus = status
            }
        }
    }

    // MARK: - Actions

    private func save() {
        // Objectifs
        store.data.dailyGoal   = parseGoal(dailyGoalText)
        store.data.weeklyGoal  = parseGoal(weeklyGoalText)
        store.data.monthlyGoal = parseGoal(monthlyGoalText)
        store.data.useWordCount = useWordCount
        store.save()

        // Thème couleur
        store.setAccentColor(hex: selectedAccentHex)

        // Notifications — sauvegarde les préférences
        let cal = Calendar.current
        NotificationManager.shared.hour                = cal.component(.hour,   from: notificationTime)
        NotificationManager.shared.minute              = cal.component(.minute, from: notificationTime)
        NotificationManager.shared.activeDays          = notificationDays
        NotificationManager.shared.isEnabled           = notificationsEnabled
        NotificationManager.shared.weeklyReportEnabled = weeklyReportEnabled

        if notificationsEnabled {
            if permissionStatus == .authorized {
                NotificationManager.shared.scheduleNotifications()
            } else if permissionStatus == .notDetermined {
                NotificationManager.shared.requestPermission { granted in
                    if granted { NotificationManager.shared.scheduleNotifications() }
                }
            }
        } else {
            NotificationManager.shared.cancelAll()
        }

        dismiss()
    }

    private func parseGoal(_ text: String) -> Int {
        Int(text.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private func openSystemPrefs() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - GoalRow

struct GoalRow: View {
    let icon: String
    let color: Color
    let label: String
    let subtitle: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 14)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 76)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                Text("car.")
                    .font(.system(size: 12)).foregroundColor(.labelMuted)
                    .frame(width: 26)
            }
        }
        .padding(14)
    }
}
