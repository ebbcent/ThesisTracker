import SwiftUI
import UserNotifications
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

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
    @State private var customColor: Color = Color.semAmber
    @AppStorage("forceDarkMode") private var forceDarkMode: Bool = false

    private let accentPresets: [(name: String, hex: String)] = [
        ("Encre",    "#1F3FD1"),   // 5.25 — accent par défaut de l'apparence Tuiles
        ("Amber",    "#F59E0B"),
        ("Slate",    "#6B8EF0"),
        ("Indigo",   "#6366F1"),
        ("Violet",   "#8B5CF6"),
        ("Rose",     "#F43F5E"),
        ("Teal",     "#14B8A6"),
        ("Emeraude", "#10B981"),
        ("Cyan",     "#06B6D4"),
        ("Orange",   "#F97316"),
        ("Fuchsia",  "#D946EF"),
        ("Sky",      "#0EA5E9"),
        ("Lime",     "#84CC16"),
    ]

    // Mode Focus — taille du compteur (#10)
    @AppStorage("focusCounterSize") private var focusCounterSize: Double = 72

    // #40 — Raccourcis configurables
    @AppStorage("shortcutFocusKey")  private var shortcutFocusKeySettings:  String = "i"
    @AppStorage("shortcutSprintKey") private var shortcutSprintKeySettings: String = "t"

    // #44 — Objectif sessions Pomodoro par semaine
    @AppStorage("weeklyPomodoroGoal") private var weeklyPomodoroGoalSettings: Int = 5

    // #46 — Lancement au démarrage
    @State private var launchAtLogin: Bool = false

    // #48 — Hotkey globale mode focus
    @AppStorage("globalFocusKey") private var globalFocusKeySettings: String = "f"

    // #24 — Buffer de sécurité deadlines
    @State private var deadlineBuffer: Int = 0

    // Objectif variable par jour de semaine
    @State private var weekdayGoalsEnabled: Bool = false
    @State private var wdGoalTexts: [Int: String] = [:]   // weekday → texte saisie

    // Notifications
    @State private var notificationsEnabled: Bool              = false
    @State private var streakWarningEnabled: Bool              = true
    @State private var ntfDailyRecapEnabled: Bool              = true
    @State private var ntfWeeklyReportEnabled: Bool            = true
    @State private var ntfEmptyDayEnabled: Bool                = true
    @State private var ntfBgGoalEnabled: Bool                  = true
    @State private var notificationTime: Date                  = Date()
    @State private var notificationDays: Set<Int>              = [2, 3, 4, 5, 6]
    @State private var permissionStatus: UNAuthorizationStatus = .notDetermined
    @State private var notificationDiagnostic: String          = ""
    // Heures configurables (#66 / #67)
    @State private var emptyDayReminderTime: Date              = Date()
    @State private var streakWarningTime: Date                 = Date()

    private let weekdays: [(Int, String)] = [
        (2, "Lun"), (3, "Mar"), (4, "Mer"), (5, "Jeu"),
        (6, "Ven"), (7, "Sam"), (1, "Dim")
    ]

    // Données & Sauvegarde states
    @State private var showSnapshotBrowser: Bool = false
    @State private var jsonExportSuccess: Bool = false
    @State private var showCompactConfirm: Bool = false
    @State private var compactResult: Int? = nil
    @State private var snapshotCount: Int = 0

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {

                // ── En-tête (fixe) ───────────────────────────────────────
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Réglages")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Objectifs · Apparence · Comportement")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
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
                    .buttonStyle(.pressable)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Divider()

                // ── Corps scrollable (molette souris) ────────────────────
                ScrollView(.vertical, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 20) {

                    // ╔══════════════════╗
                    // ║  Colonne gauche  ║  Objectifs & Raccourcis
                    // ╚══════════════════╝
                    VStack(alignment: .leading, spacing: 16) {

                        // ── Objectifs ──────────────────────────────────
                        settingsSection("OBJECTIFS") {
                            VStack(spacing: 0) {
                                GoalRow(
                                    icon: "sun.max.fill", color: Color.accent,
                                    label: "Objectif journalier",
                                    subtitle: useWordCount ? "Mots par jour" : "Caractères par jour",
                                    text: $dailyGoalText, useWordCount: useWordCount
                                )
                                Divider().padding(.leading, 48)
                                GoalRow(
                                    icon: "calendar.badge.clock", color: Color.accentWarm,
                                    label: "Objectif 30 jours",
                                    subtitle: useWordCount ? "Mots sur 30 jours glissants" : "Caractères sur 30 jours glissants",
                                    text: $monthlyGoalText, useWordCount: useWordCount
                                )
                                Divider().padding(.leading, 48)
                                GoalRow(
                                    icon: "calendar", color: Color.accentGold,
                                    label: "Objectif hebdomadaire",
                                    subtitle: useWordCount ? "Mots par semaine" : "Caractères par semaine",
                                    text: $weeklyGoalText, useWordCount: useWordCount
                                )
                                Divider().padding(.leading, 48)
                                // #24 — Buffer de sécurité
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.red.opacity(0.10)).frame(width: 34, height: 34)
                                        Image(systemName: "shield.lefthalf.filled")
                                            .font(.system(size: 13)).foregroundColor(.red.opacity(0.7))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Buffer de sécurité")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(deadlineBuffer == 0
                                             ? "Échéances affichées sans marge"
                                             : "Échéances avancées de \(deadlineBuffer) jour\(deadlineBuffer > 1 ? "s" : "")")
                                            .font(.system(size: 11))
                                            .foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Stepper("\(deadlineBuffer) j", value: $deadlineBuffer, in: 0...14)
                                        .labelsHidden()
                                    Text("\(deadlineBuffer) j")
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .frame(width: 32, alignment: .trailing)
                                }
                                .padding(14)
                            }
                        }

                        // ── Objectif variable ──────────────────────────
                        settingsSection("OBJECTIF PAR JOUR") {
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "calendar.badge.checkmark")
                                            .font(.system(size: 13)).foregroundColor(.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Objectif variable selon le jour")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Objectif différent pour chaque jour")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $weekdayGoalsEnabled)
                                        .toggleStyle(.switch).labelsHidden().tint(.accent)
                                }
                                .padding(14)

                                if weekdayGoalsEnabled {
                                    Divider().padding(.leading, 48)
                                    let days: [(Int, String)] = [
                                        (2,"Lun"),(3,"Mar"),(4,"Mer"),(5,"Jeu"),
                                        (6,"Ven"),(7,"Sam"),(1,"Dim")
                                    ]
                                    VStack(spacing: 0) {
                                        ForEach(days, id: \.0) { wd, label in
                                            HStack(spacing: 12) {
                                                Text(label)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundColor(.secondary)
                                                    .frame(width: 32, alignment: .leading)
                                                TextField(
                                                    useWordCount ? "mots" : "car.",
                                                    text: Binding(
                                                        get: { wdGoalTexts[wd] ?? "" },
                                                        set: { wdGoalTexts[wd] = $0 }
                                                    )
                                                )
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                                .multilineTextAlignment(.trailing)
                                                .frame(width: 80)
                                                .padding(.horizontal, 8).padding(.vertical, 5)
                                                .background(Color.fieldBg)
                                                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                                .overlay(RoundedRectangle(cornerRadius: AppLook.r(7, 10))
                                                    .stroke(Color.cardBorder, lineWidth: 1))
                                                Text(useWordCount ? "mots" : "car.")
                                                    .font(.system(size: 11)).foregroundColor(.labelMuted)
                                                Spacer()
                                                if wdGoalTexts[wd]?.isEmpty ?? true {
                                                    Text("= global")
                                                        .font(.system(size: 10))
                                                        .foregroundColor(.labelMuted.opacity(0.6))
                                                }
                                            }
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            if wd != 1 { Divider().padding(.leading, 14) }
                                        }
                                    }
                                }
                            }
                            .appAnimation(Motion.panel, value: weekdayGoalsEnabled)
                        }

                        // ── Calendrier d'écriture (5.9) ────────────────
                        settingsSection("CALENDRIER D'ÉCRITURE") {
                            WritingScheduleSettingsView(store: store)
                        }

                        // ── Créneaux d'écriture (5.11) ─────────────────
                        settingsSection("CRÉNEAUX D'ÉCRITURE") {
                            WritingSlotsSettingsView(store: store)
                        }

                        // ── Raccourcis clavier (#40) ──────────────��────
                        settingsSection("RACCOURCIS CLAVIER (⌘⇧ + …)") {
                            VStack(spacing: 0) {
                                shortcutRow(
                                    icon: "pencil.and.outline",
                                    label: "Mode focus",
                                    keyBinding: $shortcutFocusKeySettings,
                                    placeholder: "i"
                                )
                                Divider()
                                shortcutRow(
                                    icon: "timer",
                                    label: "Sprint d'écriture",
                                    keyBinding: $shortcutSprintKeySettings,
                                    placeholder: "t"
                                )
                            }
                        }

                        // ── Données & Sauvegarde (#64 #66 #67 #68 #69) ────
                        settingsSection("DONNÉES & SAUVEGARDE") {
                            VStack(spacing: 0) {

                                // #64 — Snapshots
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.system(size: 14)).foregroundColor(.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Snapshots automatiques")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("\(snapshotCount) sauvegarde(s) disponible(s)")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Button("Parcourir") { showSnapshotBrowser = true }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.accent)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.accent.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                        .buttonStyle(.pressable)
                                }
                                .padding(14)
                                .sheet(isPresented: $showSnapshotBrowser) {
                                    SnapshotBrowserView(store: store)
                                }

                                Divider().padding(.leading, 48)

                                // #66 — Export JSON
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.blue.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "square.and.arrow.up.fill")
                                            .font(.system(size: 14)).foregroundColor(.blue)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Exporter le fichier JSON")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Sauvegarde complète de toutes les données")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    if jsonExportSuccess {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentGreen).font(.system(size: 16))
                                    } else {
                                        Button("Exporter") { exportJSON() }
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                            .buttonStyle(.pressable)
                                    }
                                }
                                .padding(14)

                                Divider().padding(.leading, 48)

                                // #68 — Compaction
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.orange.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "archivebox.fill")
                                            .font(.system(size: 14)).foregroundColor(.semOrange)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Compacter les anciennes entrées")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        if let n = compactResult {
                                            Text(n == 0 ? "Aucune entrée compactée" : "\(n) entrée(s) compactée(s)")
                                                .font(.system(size: 11)).foregroundColor(.accentGreen)
                                        } else {
                                            Text("Agrège les données de plus de 2 ans par mois")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                    }
                                    Spacer()
                                    Button("Compacter") { showCompactConfirm = true }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.semOrange)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color.orange.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(7, 10)))
                                        .buttonStyle(.pressable)
                                }
                                .padding(14)
                                .confirmationDialog(
                                    "Compacter les anciennes entrées ?",
                                    isPresented: $showCompactConfirm,
                                    titleVisibility: .visible
                                ) {
                                    Button("Compacter", role: .destructive) {
                                        compactResult = store.compactOldEntries(olderThanYears: 2)
                                    }
                                    Button("Annuler", role: .cancel) {}
                                } message: {
                                    Text("Les entrées de plus de 2 ans seront regroupées par mois (1 entrée par mois). Cette opération est irréversible.")
                                }

                                // #67 — Corruption warnings
                                if !store.corruptionIssues.isEmpty {
                                    Divider().padding(.leading, 48)
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.red).font(.system(size: 12))
                                            Text("\(store.corruptionIssues.count) problème(s) détecté(s)")
                                                .font(.system(size: 12, weight: .semibold)).foregroundColor(.red)
                                        }
                                        ForEach(store.corruptionIssues) { issue in
                                            HStack(alignment: .top, spacing: 6) {
                                                Image(systemName: issue.severity == .error ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                                                    .foregroundColor(issue.severity == .error ? .red : .orange)
                                                    .font(.system(size: 10))
                                                Text(issue.message)
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.primary.opacity(0.8))
                                            }
                                        }
                                    }
                                    .padding(14)
                                }

                                Divider().padding(.leading, 48)

                                // #69 — Usage stats
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accentGreen.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "chart.bar.xaxis")
                                            .font(.system(size: 14)).foregroundColor(.accentGreen)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Statistiques d'utilisation")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Ouvertures ce mois-ci")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Text("\(store.appOpensThisMonth)")
                                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                                        .foregroundColor(.accentGreen)
                                }
                                .padding(14)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // ╔══════════════════╗
                    // ║  Colonne droite  ║  Apparence · Rappels · Focus
                    // ╚══════════════════╝
                    VStack(alignment: .leading, spacing: 16) {

                        // ── Mises à jour ───────────────────────────────
                        UpdatesSettingsSection()

                        // ── Verre (5.16) ──────────────────────────────
                        GlassSettingsSection()

                        // ── Fond de l'apparence Tuiles (5.25) ─────────
                        TilesLookSettingsSection()

                        // ── Professeur (5.13) ──────────────────────────
                        ProfessorSettingsSection()

                        // ── Affichage ──────────────────────────────────
                        settingsSection("AFFICHAGE") {
                            VStack(spacing: 0) {
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
                                        .toggleStyle(.switch).labelsHidden().tint(.accent)
                                }
                                .padding(14)

                                Divider().padding(.leading, 48)

                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color(hex: "#6B8EF0").opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "moon.fill")
                                            .font(.system(size: 14)).foregroundColor(Color(hex: "#6B8EF0"))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Forcer le mode sombre")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Ignore l'apparence du système")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $forceDarkMode)
                                        .toggleStyle(.switch).labelsHidden()
                                        // 5.24 — ce réglage reprend la main sur le bouton clair/sombre des Tuiles
                                        .onChange(of: forceDarkMode) { _, _ in
                                            UserDefaults.standard.set(false, forKey: "forceLightMode")
                                        }
                                        .tint(Color(hex: "#6B8EF0"))
                                }
                                .padding(14)
                            }
                        }

                        // ── Thème couleur ──────────────────────────────
                        settingsSection("THÈME") {
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
                                                    Circle().fill(Color(hex: preset.hex)).frame(width: 26, height: 26)
                                                    if isSelected {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 10, weight: .bold))
                                                            .foregroundColor(.white)
                                                    }
                                                }
                                                Text(preset.name)
                                                    .font(.system(size: 10, weight: isSelected ? .bold : .regular))
                                                    .foregroundColor(isSelected ? .primary : .labelMuted)
                                            }
                                        }
                                        .buttonStyle(.pressable)
                                    }

                                    Divider().frame(height: 36)

                                    ColorPicker("", selection: $customColor, supportsOpacity: false)
                                        .labelsHidden()
                                        .frame(width: 26, height: 26)
                                        .onChange(of: customColor) { _, newColor in
                                            selectedAccentHex = newColor.toHex()
                                        }
                                    Text("Perso")
                                        .font(.system(size: 10))
                                        .foregroundColor(.labelMuted)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                            }
                        }

                        // ── Mode focus (#10) ───────────────────────────
                        settingsSection("MODE FOCUS") {
                            VStack(spacing: 0) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Taille du compteur")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Taille de l'affichage principal (⌘⇧I)")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Text("\(Int(focusCounterSize)) pt")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.accent)
                                        .frame(width: 48)
                                }
                                .padding(14)
                                Divider()
                                HStack(spacing: 10) {
                                    Text("48").font(.system(size: 10, design: .monospaced)).foregroundColor(.labelMuted)
                                    Slider(value: $focusCounterSize, in: 48...96, step: 4).tint(.accent)
                                    Text("96").font(.system(size: 10, design: .monospaced)).foregroundColor(.labelMuted)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                            }
                        }

                        // ── Pomodoro & focus (#44 #46 #48) ────────────
                        settingsSection("POMODORO & FOCUS") {
                            VStack(spacing: 0) {
                                // #44 — Objectif sessions par semaine
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "timer")
                                            .font(.system(size: 14)).foregroundColor(.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Sessions Pomodoro par semaine")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Objectif affiché dans le tableau de bord")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    HStack(spacing: 6) {
                                        TextField("5", value: $weeklyPomodoroGoalSettings, format: .number)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 48)
                                            .padding(.horizontal, 8).padding(.vertical, 6)
                                            .background(Color.fieldBg)
                                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
                                        Text("/ sem.")
                                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                                    }
                                }
                                .padding(14)

                                Divider().padding(.leading, 48)

                                // #48 — Hotkey globale focus
                                shortcutRow(
                                    icon: "keyboard.badge.eye",
                                    label: "Ouvrir mode focus (hotkey globale ⌃⌥)",
                                    keyBinding: $globalFocusKeySettings,
                                    placeholder: "f",
                                    prefix: "⌃⌥"
                                )

                                Divider().padding(.leading, 48)

                                // #46 — Lancement au démarrage
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accentGreen.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "power.circle.fill")
                                            .font(.system(size: 14)).foregroundColor(.accentGreen)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Démarrer avec macOS")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Lance Writing Process au démarrage de la session")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $launchAtLogin)
                                        .toggleStyle(.switch).labelsHidden().tint(.accentGreen)
                                        .onChange(of: launchAtLogin) { _, enabled in
                                            if enabled {
                                                try? SMAppService.mainApp.register()
                                            } else {
                                                try? SMAppService.mainApp.unregister()
                                            }
                                        }
                                }
                                .padding(14)
                            }
                        }

                        // ── Rappels ────────────────────────────────────
                        settingsSection("RAPPELS") {
                            VStack(spacing: 0) {
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "bell.fill")
                                            .font(.system(size: 14)).foregroundColor(.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Rappel quotidien")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text("Notification à l'heure choisie — active aussi les rappels ci-dessous (série, récap, objectif…)")
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Toggle("", isOn: $notificationsEnabled)
                                        .toggleStyle(.switch).labelsHidden().tint(.accent)
                                }
                                .padding(14)

                                Divider().padding(.leading, 48)

                                // Diagnostic : état réel dans macOS + notification de test
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                                        Image(systemName: "bell.badge")
                                            .font(.system(size: 13)).foregroundColor(.accent)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("État dans macOS")
                                            .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                        Text(notificationDiagnostic.isEmpty ? "…" : notificationDiagnostic)
                                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    Button("Tester") {
                                        NotificationManager.shared.ensureAuthorization()
                                        NotificationManager.shared.sendTestNotification()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { refreshNotificationDiagnostic() }
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.accent).buttonStyle(.pressable)
                                    .help("Envoie une notification dans 5 secondes")
                                    Button("Réglages macOS") { openSystemPrefs() }
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.accent).buttonStyle(.pressable)
                                }
                                .padding(14)

                                if notificationsEnabled {
                                    Divider().padding(.leading, 48)

                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.orange.opacity(0.12)).frame(width: 34, height: 34)
                                            Image(systemName: "flame.fill")
                                                .font(.system(size: 14)).foregroundColor(.semOrange)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Alerte série en danger")
                                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                            Text("Si la série n'est pas maintenue ce jour-là")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                        Spacer()
                                        if streakWarningEnabled {
                                            DatePicker("", selection: $streakWarningTime,
                                                       displayedComponents: .hourAndMinute)
                                                .labelsHidden()
                                                .datePickerStyle(.compact)
                                                .accentColor(.orange)
                                                .onChange(of: streakWarningTime) { _, t in
                                                    let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                                    NotificationManager.shared.streakWarningHour   = c.hour ?? 23
                                                    NotificationManager.shared.streakWarningMinute = c.minute ?? 0
                                                }
                                        }
                                        Toggle("", isOn: $streakWarningEnabled)
                                            .toggleStyle(.switch).labelsHidden().tint(.orange)
                                    }
                                    .padding(14)

                                    Divider().padding(.leading, 48)

                                    // #57 Récap quotidien
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.blue.opacity(0.12)).frame(width: 34, height: 34)
                                            Image(systemName: "doc.text.fill")
                                                .font(.system(size: 13)).foregroundColor(.blue)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Récapitulatif quotidien")
                                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                            Text("Bilan à 19h avec le total du jour et la série")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                        Spacer()
                                        Toggle("", isOn: $ntfDailyRecapEnabled)
                                            .toggleStyle(.switch).labelsHidden().tint(.blue)
                                    }
                                    .padding(14)

                                    Divider().padding(.leading, 48)

                                    // #60 Rapport hebdomadaire
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.purple.opacity(0.12)).frame(width: 34, height: 34)
                                            Image(systemName: "chart.bar.fill")
                                                .font(.system(size: 13)).foregroundColor(.purple)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Rapport hebdomadaire")
                                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                            Text("Synthèse de la semaine chaque dimanche à 19h")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                        Spacer()
                                        Toggle("", isOn: $ntfWeeklyReportEnabled)
                                            .toggleStyle(.switch).labelsHidden().tint(.purple)
                                    }
                                    .padding(14)

                                    Divider().padding(.leading, 48)

                                    // #66 Rappel configurable si aucune saisie
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.accentWarm.opacity(0.12)).frame(width: 34, height: 34)
                                            Image(systemName: "bell.badge.fill")
                                                .font(.system(size: 13)).foregroundColor(.accentWarm)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Rappel de saisie")
                                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                            Text("Si aucune écriture enregistrée dans la journée")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                        Spacer()
                                        if ntfEmptyDayEnabled {
                                            DatePicker("", selection: $emptyDayReminderTime,
                                                       displayedComponents: .hourAndMinute)
                                                .labelsHidden()
                                                .datePickerStyle(.compact)
                                                .accentColor(.accentWarm)
                                                .onChange(of: emptyDayReminderTime) { _, t in
                                                    let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                                    NotificationManager.shared.emptyDayReminderHour   = c.hour ?? 20
                                                    NotificationManager.shared.emptyDayReminderMinute = c.minute ?? 0
                                                }
                                        }
                                        Toggle("", isOn: $ntfEmptyDayEnabled)
                                            .toggleStyle(.switch).labelsHidden().tint(.accentWarm)
                                    }
                                    .padding(14)

                                    Divider().padding(.leading, 48)

                                    // #63 Notification arrière-plan objectif atteint
                                    HStack(spacing: 14) {
                                        ZStack {
                                            Circle().fill(Color.accentGreen.opacity(0.12)).frame(width: 34, height: 34)
                                            Image(systemName: "checkmark.seal.fill")
                                                .font(.system(size: 13)).foregroundColor(.accentGreen)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Objectif atteint (arrière-plan)")
                                                .font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                                            Text("Notification quand l'objectif est franchi hors de l'app")
                                                .font(.system(size: 11)).foregroundColor(.labelMuted)
                                        }
                                        Spacer()
                                        Toggle("", isOn: $ntfBgGoalEnabled)
                                            .toggleStyle(.switch).labelsHidden().tint(.accentGreen)
                                    }
                                    .padding(14)

                                    Divider().padding(.leading, 48)

                                    if permissionStatus == .denied {
                                        HStack(spacing: 10) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.semOrange).font(.system(size: 13))
                                            Text("Notifications refusées dans les Réglages Système")
                                                .font(.system(size: 12)).foregroundColor(.semOrange)
                                            Spacer()
                                            Button("Ouvrir") { openSystemPrefs() }
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.accent).buttonStyle(.pressable)
                                        }
                                        .padding(14)
                                    } else {
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
                                                .labelsHidden().datePickerStyle(.compact).accentColor(.accent)
                                        }
                                        .padding(14)

                                        Divider().padding(.leading, 48)

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
                                                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                                                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(6, 10))
                                                                .stroke(isOn ? Color.accent : Color.cardBorder, lineWidth: 1))
                                                    }
                                                    .buttonStyle(.pressable)
                                                }
                                            }
                                        }
                                        .padding(14)
                                    }
                                }
                            }
                            .appAnimation(Motion.panel, value: notificationsEnabled)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }   // HStack colonnes
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                }   // ScrollView

                Divider()

                // ── Pied de page fixe : diagnostic + boutons ─────────────
                VStack(spacing: 8) {
                    // Diagnostic stockage
                    let activeURL = store.activeFileURLPublic
                    let fileExists = FileManager.default.fileExists(atPath: activeURL.path)
                    HStack(spacing: 8) {
                        Image(systemName: store.isUsingICloud ? "icloud.fill" : "internaldrive.fill")
                            .font(.system(size: 10))
                            .foregroundColor(store.isUsingICloud ? .accent : .labelMuted)
                        Text(store.isUsingICloud ? "iCloud Drive" : "Local")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(store.isUsingICloud ? .accent : .labelMuted)
                        Text("·").foregroundColor(.labelMuted).font(.system(size: 10))
                        Text(activeURL.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1).truncationMode(.middle)
                        Circle()
                            .fill(fileExists ? Color.accentGreen : Color.red)
                            .frame(width: 5, height: 5)
                        Spacer()
                        Text("\(store.data.projects.count) projet(s)")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.labelMuted)
                        Text("·").foregroundColor(.labelMuted).font(.system(size: 10))
                        let totalEntries = store.data.projects.flatMap(\.chapters).flatMap(\.entries).count
                        Text("\(totalEntries) entrée(s)")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.labelMuted)
                        Button("↺ Recharger") { store.load() }
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.accent).buttonStyle(.pressable)
                    }
                    if let err = store.loadErrorMessage {
                        Text("⚠ \(err)")
                            .font(.system(size: 10, design: .monospaced)).foregroundColor(.red).lineLimit(2)
                    }

                    // Boutons Annuler / Enregistrer
                    HStack(spacing: 12) {
                        Button("Annuler") { dismiss() }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.labelMuted)
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                            .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
                            .buttonStyle(.pressable)
                            .keyboardShortcut(.escape)

                        Spacer()

                        Button("Enregistrer") { save() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22).padding(.vertical, 9)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                            .buttonStyle(.pressable)
                            .keyboardShortcut(.return)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

            }   // VStack principal
        }   // ZStack
        .sheetFrame(width: 900, height: 580)
        .onAppear {
            snapshotCount = store.listSnapshots().count
            // #46 — sync état réel du login item
            launchAtLogin = SMAppService.mainApp.status == .enabled
            // Objectifs
            dailyGoalText   = store.data.dailyGoal   > 0 ? "\(store.data.dailyGoal)"   : ""
            weeklyGoalText  = store.data.weeklyGoal  > 0 ? "\(store.data.weeklyGoal)"  : ""
            monthlyGoalText = store.data.monthlyGoal > 0 ? "\(store.data.monthlyGoal)" : ""
            useWordCount    = store.data.useWordCount
            deadlineBuffer  = store.deadlineBuffer
            // Objectif variable
            let saved = store.weekdayGoals
            weekdayGoalsEnabled = !saved.isEmpty
            wdGoalTexts = Dictionary(uniqueKeysWithValues: saved.map { (String($0.key), "\($0.value)") }
                .compactMap { (k, v) in guard let i = Int(k) else { return nil }; return (i, v) })
            // Thème
            selectedAccentHex = store.accentColorHex
            customColor = Color(hex: store.accentColorHex)
            // Notifications — valeurs sauvegardées
            notificationsEnabled    = NotificationManager.shared.isEnabled
            streakWarningEnabled    = UserDefaults.standard.object(forKey: "ntfStreakWarning") == nil
                                      ? true
                                      : UserDefaults.standard.bool(forKey: "ntfStreakWarning")
            ntfDailyRecapEnabled    = UserDefaults.standard.object(forKey: "ntfDailyRecap") == nil   ? true : UserDefaults.standard.bool(forKey: "ntfDailyRecap")
            ntfWeeklyReportEnabled  = UserDefaults.standard.object(forKey: "ntfWeeklyReport") == nil ? true : UserDefaults.standard.bool(forKey: "ntfWeeklyReport")
            ntfEmptyDayEnabled      = UserDefaults.standard.object(forKey: "ntfEmptyDay") == nil     ? true : UserDefaults.standard.bool(forKey: "ntfEmptyDay")
            ntfBgGoalEnabled        = UserDefaults.standard.object(forKey: "ntfBgGoal") == nil       ? true : UserDefaults.standard.bool(forKey: "ntfBgGoal")
            notificationDays      = NotificationManager.shared.activeDays
            let cal  = Calendar.current
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.hour   = NotificationManager.shared.hour
            comps.minute = NotificationManager.shared.minute
            notificationTime = cal.date(from: comps) ?? Date()
            // Heures configurables #66/#67
            var emptyComps = cal.dateComponents([.year, .month, .day], from: Date())
            emptyComps.hour   = NotificationManager.shared.emptyDayReminderHour
            emptyComps.minute = NotificationManager.shared.emptyDayReminderMinute
            emptyDayReminderTime = cal.date(from: emptyComps) ?? Date()
            var streakComps = cal.dateComponents([.year, .month, .day], from: Date())
            streakComps.hour   = NotificationManager.shared.streakWarningHour
            streakComps.minute = NotificationManager.shared.streakWarningMinute
            streakWarningTime = cal.date(from: streakComps) ?? Date()
            // Permission actuelle
            refreshNotificationDiagnostic()
        }
    }

    private func refreshNotificationDiagnostic() {
        NotificationManager.shared.diagnostic { status, text in
            permissionStatus = status
            notificationDiagnostic = text
        }
    }

    // MARK: - Section helper

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.2)
            content()
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(14, 20)))
                .overlay(RoundedRectangle(cornerRadius: AppLook.r(14, 20)).stroke(Color.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func exportJSON() {
        guard let data = store.exportJSONData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ThesisTracker-backup-\(DataStore.today).json"
        panel.message = "Choisissez où enregistrer la sauvegarde JSON"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
        jsonExportSuccess = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { jsonExportSuccess = false }
    }

    private func save() {
        // Objectifs
        store.data.dailyGoal    = parseGoal(dailyGoalText)
        store.data.weeklyGoal   = parseGoal(weeklyGoalText)
        store.data.monthlyGoal  = parseGoal(monthlyGoalText)
        store.data.useWordCount = useWordCount
        store.deadlineBuffer    = deadlineBuffer
        store.save()
        // Objectif variable par jour
        if weekdayGoalsEnabled {
            store.weekdayGoals = Dictionary(uniqueKeysWithValues: wdGoalTexts.compactMap { wd, text in
                let v = parseGoal(text)
                guard v > 0 else { return nil }
                return (wd, v)
            })
        } else {
            store.weekdayGoals = [:]
        }

        // Thème couleur
        store.setAccentColor(hex: selectedAccentHex)

        // Notifications — sauvegarde les préférences
        let cal = Calendar.current
        NotificationManager.shared.hour       = cal.component(.hour,   from: notificationTime)
        NotificationManager.shared.minute     = cal.component(.minute, from: notificationTime)
        NotificationManager.shared.activeDays = notificationDays
        NotificationManager.shared.isEnabled  = notificationsEnabled
        UserDefaults.standard.set(streakWarningEnabled,   forKey: "ntfStreakWarning")
        UserDefaults.standard.set(ntfDailyRecapEnabled,   forKey: "ntfDailyRecap")
        UserDefaults.standard.set(ntfWeeklyReportEnabled, forKey: "ntfWeeklyReport")
        UserDefaults.standard.set(ntfEmptyDayEnabled,     forKey: "ntfEmptyDay")
        UserDefaults.standard.set(ntfBgGoalEnabled,       forKey: "ntfBgGoal")
        // Heures configurables #66/#67
        NotificationManager.shared.emptyDayReminderHour   = cal.component(.hour,   from: emptyDayReminderTime)
        NotificationManager.shared.emptyDayReminderMinute = cal.component(.minute, from: emptyDayReminderTime)
        NotificationManager.shared.streakWarningHour      = cal.component(.hour,   from: streakWarningTime)
        NotificationManager.shared.streakWarningMinute    = cal.component(.minute, from: streakWarningTime)

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
        // 5.23 — « 10 000 » (espace, espace insécable ou fine) est un nombre valide
        Int(text.filter { !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" }) ?? 0
    }

    // #40 — Ligne de raccourci configurable
    private func shortcutRow(icon: String, label: String, keyBinding: Binding<String>, placeholder: String, prefix: String = "⌘⇧") -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.accent)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.primary)
            Spacer()
            HStack(spacing: 3) {
                Text(prefix)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.labelMuted)
                TextField(placeholder, text: keyBinding)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .frame(width: 28)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(6, 10)).stroke(Color.cardBorder, lineWidth: 1))
                    .onChange(of: keyBinding.wrappedValue) { _, new in
                        // Garder seulement 1 caractère minuscule
                        let filtered = String(new.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(1))
                        if filtered != new { keyBinding.wrappedValue = filtered }
                    }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func openSystemPrefs() {
        NotificationManager.openSystemNotificationSettings()
    }
}

// MARK: - GoalRow

struct GoalRow: View {
    let icon: String
    let color: Color
    let label: String
    let subtitle: String
    @Binding var text: String
    var useWordCount: Bool = false

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
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
                Text(useWordCount ? "mots" : "car.")
                    .font(.system(size: 12)).foregroundColor(.labelMuted)
                    .frame(width: 30)
            }
        }
        .padding(14)
    }
}
