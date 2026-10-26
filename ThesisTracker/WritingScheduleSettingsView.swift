import SwiftUI

// MARK: - Réglages · Calendrier d'écriture (5.9)
// Fichier isolé, inséré dans SettingsView. Chaque changement est appliqué
// tout de suite dans data.json (synchronisé entre les deux Mac).

struct WritingScheduleSettingsView: View {
    @ObservedObject var store: DataStore

    private let days: [(Int, String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]

    private var schedule: WritingSchedule { store.data.writingSchedule ?? WritingSchedule() }
    private var workdays: Set<Int> { Set(schedule.workWeekdays ?? []) }
    private var rule: StreakRule { schedule.streakRule ?? .consecutive }

    var body: some View {
        VStack(spacing: 0) {
            settingRow(icon: "calendar", color: .accent,
                       title: "Jours d'écriture",
                       subtitle: workdays.isEmpty
                           ? "Aucun jour coché : tous les jours comptent"
                           : "Quotas d'échéance et objectif adaptatif répartis sur ces jours ; jours de repos exclus") {
                HStack(spacing: 4) {
                    ForEach(days, id: \.0) { weekday, label in
                        dayButton(weekday: weekday, label: label)
                    }
                }
            }
            Divider().padding(.leading, 48)
            settingRow(icon: "flag.checkered", color: .accentWarm,
                       title: "Compter le jour de l'échéance",
                       subtitle: "Le jour J fait partie des jours d'écriture restants") {
                Toggle("", isOn: Binding(
                    get: { schedule.countDeadlineDay ?? true },
                    set: { value in store.updateWritingSchedule { $0.countDeadlineDay = value } }
                ))
                .toggleStyle(.switch).labelsHidden().tint(.accent)
                .disabled(workdays.isEmpty)
            }
            Divider().padding(.leading, 48)
            settingRow(icon: "doc.plaintext", color: .accent,
                       title: "Équivalent en pages",
                       subtitle: "Affiché à côté des totaux du chapitre et du reste à écrire") {
                Picker("", selection: Binding(
                    get: { schedule.charsPerPage ?? 0 },
                    set: { value in store.updateWritingSchedule { $0.charsPerPage = value > 0 ? value : nil } }
                )) {
                    ForEach(DataStore.pagePresets, id: \.chars) { preset in
                        Text(preset.label).tag(preset.chars)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
            Divider().padding(.leading, 48)
            settingRow(icon: "flame.fill", color: .accentWarm,
                       title: "Série",
                       subtitle: rule == .scheduled
                           ? "Jours non prévus, repos et pauses ne cassent pas la série"
                           : "Chaque jour sans écriture casse la série") {
                Picker("", selection: Binding(
                    get: { rule },
                    set: { value in store.updateWritingSchedule { $0.streakRule = value } }
                )) {
                    ForEach(StreakRule.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
            if rule == .scheduled {
                Divider().padding(.leading, 48)
                settingRow(icon: "heart.fill", color: .accentGreen,
                           title: "Jour de grâce",
                           subtitle: "Un jour prévu manqué est toléré si le suivant est tenu ; deux d'affilée cassent la série") {
                    Toggle("", isOn: Binding(
                        get: { schedule.graceDay ?? false },
                        set: { value in store.updateWritingSchedule { $0.graceDay = value } }
                    ))
                    .toggleStyle(.switch).labelsHidden().tint(.accent)
                }
                Divider().padding(.leading, 48)
                settingRow(icon: "pause.circle.fill", color: .labelMuted,
                           title: "Mettre la série en pause",
                           subtitle: store.isStreakPaused
                               ? "Série gelée : les jours sans écriture ne comptent pas"
                               : "Maladie, colloque, vacances imprévues…") {
                    Toggle("", isOn: Binding(
                        get: { store.isStreakPaused },
                        set: { store.setStreakPaused($0) }
                    ))
                    .toggleStyle(.switch).labelsHidden().tint(.accent)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: rule)
    }

    private func dayButton(weekday: Int, label: String) -> some View {
        let isOn = workdays.contains(weekday)
        return Button {
            store.updateWritingSchedule { schedule in
                var selected = Set(schedule.workWeekdays ?? [])
                if selected.contains(weekday) { selected.remove(weekday) } else { selected.insert(weekday) }
                schedule.workWeekdays = selected.sorted()
            }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .foregroundColor(isOn ? .white : .secondary)
                .background(Circle().fill(isOn ? Color.accent : Color.fieldBg))
                .overlay(Circle().stroke(Color.cardBorder, lineWidth: isOn ? 0 : 1))
        }
        .buttonStyle(.plain)
        .help(isOn ? "Jour d'écriture" : "Jour sans écriture prévue")
    }

    private func settingRow<Control: View>(icon: String, color: Color, title: String, subtitle: String,
                                           @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 34, height: 34)
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                Text(subtitle).font(.system(size: 11)).foregroundColor(.labelMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            control()
        }
        .padding(14)
    }
}
