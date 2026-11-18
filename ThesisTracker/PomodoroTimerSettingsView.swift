import AppKit
import SwiftUI

struct PomodoroTimerSettingsView: View {
    @EnvironmentObject private var controller: PomodoroAppController
    @State private var goalTitle = ""
    @State private var goalPeriod: GoalPeriod = .daily
    @State private var goalMetric: GoalMetric = .minutes
    @State private var goalTarget = ""
    @State private var editingGoalID: UUID?
    @State private var editingGoalTitle = ""
    @State private var editingGoalPeriod: GoalPeriod = .daily
    @State private var editingGoalMetric: GoalMetric = .minutes
    @State private var editingGoalTarget = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Réglages et export")
                    .font(.largeTitle.bold())

                // MARK: Cycle
                InfoCard(title: "Cycle Pomodoro", systemImage: "gearshape.2.fill") {
                    HStack {
                        Stepper(value: $controller.data.settings.focusDuration, in: 5 * 60...120 * 60, step: 5 * 60) {
                            Text("Concentration : \(Int(controller.data.settings.focusDuration / 60)) minutes")
                        }
                        Stepper(value: $controller.data.settings.shortBreakDuration, in: 1 * 60...30 * 60, step: 60) {
                            Text("Pause courte : \(Int(controller.data.settings.shortBreakDuration / 60)) minutes")
                        }
                    }
                    HStack {
                        Stepper(value: $controller.data.settings.longBreakDuration, in: 5 * 60...60 * 60, step: 5 * 60) {
                            Text("Pause longue : \(Int(controller.data.settings.longBreakDuration / 60)) minutes")
                        }
                        Stepper(value: $controller.data.settings.sessionsBeforeLongBreak, in: 2...8) {
                            Text("Sessions avant une pause longue : \(controller.data.settings.sessionsBeforeLongBreak)")
                        }
                    }
                    Stepper(value: $controller.data.settings.workBlockMaxBreakMinutes, in: 15...240, step: 15) {
                        Text("Seuil de bloc de travail : \(controller.data.settings.workBlockMaxBreakMinutes) min sans session")
                    }
                    Button("Enregistrer le cycle") {
                        controller.saveSettings()
                    }
                    .buttonStyle(CockpitButtonStyle(prominent: true))
                }

                // MARK: Écriture
                InfoCard(title: "Écriture & rappels", systemImage: "text.word.spacing") {
                    Stepper(value: $controller.data.settings.wordsPerSessionGoal, in: 0...2000, step: 50) {
                        if controller.data.settings.wordsPerSessionGoal == 0 {
                            Text("Objectif de mots par session : désactivé")
                        } else {
                            Text("Objectif de mots par session : \(controller.data.settings.wordsPerSessionGoal)")
                        }
                    }
                    Stepper(value: $controller.data.settings.pauseReminderMinutes, in: 1...30) {
                        Text("Rappel de pause non démarrée : \(controller.data.settings.pauseReminderMinutes) min")
                    }
                    Toggle(isOn: $controller.data.settings.deepWorkEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mode deep work (Concentration via Raccourcis)")
                                .font(.system(size: 13, weight: .medium))
                            Text("Crée dans l'app Raccourcis deux raccourcis qui activent/désactivent ta Concentration, puis indique leurs noms ci-dessous. Ils seront lancés au début et à la fin de chaque session.")
                                .font(.system(size: AppLook.fs(11))).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if controller.data.settings.deepWorkEnabled {
                        TextField("Raccourci d'activation (ex. « Concentration ON »)", text: $controller.data.settings.focusShortcutOnName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Raccourci de désactivation (ex. « Concentration OFF »)", text: $controller.data.settings.focusShortcutOffName)
                            .textFieldStyle(.roundedBorder)
                    }
                    Button("Enregistrer") {
                        controller.saveSettings()
                    }
                    .buttonStyle(CockpitButtonStyle(prominent: true))
                }

                // MARK: Sons
                InfoCard(title: "Sons de fin de session", systemImage: "speaker.wave.2.fill") {
                    HStack(spacing: 20) {
                        soundRow(label: "Concentration", sound: $controller.data.settings.focusCompletionSound)
                        soundRow(label: "Pause courte", sound: $controller.data.settings.shortBreakCompletionSound)
                        soundRow(label: "Pause longue", sound: $controller.data.settings.longBreakCompletionSound)
                    }
                    HStack {
                        Text("Volume : \(Int(controller.data.settings.soundVolume * 100))%")
                            .font(.system(size: 13, weight: .medium, design: AppLook.fontDesign))
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $controller.data.settings.soundVolume, in: 0...1, step: 0.05)
                    }
                    Button("Enregistrer les sons") {
                        controller.saveSettings()
                    }
                    .buttonStyle(CockpitButtonStyle(prominent: true))
                }

                HStack(alignment: .top, spacing: 20) {
                    // MARK: Objectifs
                    InfoCard(title: "Objectifs", systemImage: "target") {
                        ForEach(controller.data.goals) { goal in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("\(goal.title) : \(goal.target) \(goal.metric.displayName) par période \(goal.period.displayName.lowercased())")
                                    Spacer()
                                    Button("Modifier") {
                                        editingGoalID = goal.id
                                        editingGoalTitle = goal.title
                                        editingGoalPeriod = goal.period
                                        editingGoalMetric = goal.metric
                                        editingGoalTarget = String(goal.target)
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                    Button("Supprimer") {
                                        controller.deleteGoal(id: goal.id)
                                        if editingGoalID == goal.id { editingGoalID = nil }
                                    }
                                    .buttonStyle(CockpitButtonStyle())
                                }
                                if editingGoalID == goal.id {
                                    TextField("Titre de l'objectif", text: $editingGoalTitle)
                                    Picker("Période", selection: $editingGoalPeriod) {
                                        ForEach(GoalPeriod.allCases) { period in
                                            Text(period.displayName).tag(period)
                                        }
                                    }
                                    Picker("Mesure", selection: $editingGoalMetric) {
                                        ForEach(GoalMetric.allCases) { metric in
                                            Text(metric.displayName).tag(metric)
                                        }
                                    }
                                    TextField("Cible (nombre)", text: $editingGoalTarget)
                                    HStack {
                                        Button("Enregistrer") {
                                            let error = controller.updateGoal(
                                                id: goal.id,
                                                title: editingGoalTitle,
                                                period: editingGoalPeriod,
                                                metric: editingGoalMetric,
                                                target: Int(editingGoalTarget) ?? 0
                                            )
                                            if error == nil { editingGoalID = nil }
                                        }
                                        .buttonStyle(CockpitButtonStyle(prominent: true))
                                        Button("Annuler") { editingGoalID = nil }
                                            .buttonStyle(CockpitButtonStyle())
                                    }
                                }
                            }
                            Divider()
                        }
                        TextField("Titre de l'objectif", text: $goalTitle)
                        Picker("Période", selection: $goalPeriod) {
                            ForEach(GoalPeriod.allCases) { period in
                                Text(period.displayName).tag(period)
                            }
                        }
                        Picker("Mesure", selection: $goalMetric) {
                            ForEach(GoalMetric.allCases) { metric in
                                Text(metric.displayName).tag(metric)
                            }
                        }
                        TextField("Cible (nombre)", text: $goalTarget)
                            .onChange(of: goalTitle) { _, _ in controller.clearGoalValidationError() }
                            .onChange(of: goalTarget) { _, _ in controller.clearGoalValidationError() }
                        if let error = controller.goalValidationError {
                            Text(error)
                                .font(.system(size: 12, weight: .medium, design: AppLook.fontDesign))
                                .foregroundStyle(.red)
                        }
                        Button("Ajouter l'objectif") {
                            let error = controller.addGoal(
                                title: goalTitle,
                                period: goalPeriod,
                                metric: goalMetric,
                                target: Int(goalTarget) ?? 0
                            )
                            if error == nil {
                                goalTitle = ""
                                goalTarget = ""
                            }
                        }
                        .buttonStyle(CockpitButtonStyle())
                    }

                    // MARK: Export
                    InfoCard(title: "Export", systemImage: "square.and.arrow.up") {
                        Text("Exporte le fichier JSON principal ou un extrait CSV de toutes les sessions.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Exporter en JSON") { controller.exportJSON() }
                                .buttonStyle(CockpitButtonStyle())
                            Button("Exporter en CSV") { controller.exportCSV() }
                                .buttonStyle(CockpitButtonStyle())
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    // MARK: - Sound row

    private func soundRow(label: String, sound: Binding<PomodoroSound>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: AppLook.fontDesign))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Picker("", selection: sound) {
                    ForEach(PomodoroSound.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Button {
                    PomodoroSoundPreview.play(sound.wrappedValue, volume: controller.data.settings.soundVolume)
                } label: {
                    Image(systemName: "play.circle")
                }
                .buttonStyle(CockpitButtonStyle())
                .disabled(sound.wrappedValue == .none)
                .help("Écouter le son")
                .accessibilityLabel("Écouter le son")
            }
        }
    }
}

// MARK: - Sound preview helper

private enum PomodoroSoundPreview {
    private static var activeSound: NSSound?

    static func play(_ sound: PomodoroSound, volume: Float) {
        guard sound != .none else { return }
        activeSound?.stop()
        guard let s = NSSound(named: NSSound.Name(sound.rawValue)) else { return }
        s.volume = max(0, min(1, volume))
        s.play()
        activeSound = s
    }
}
