import SwiftUI

// MARK: - Réglages · Créneaux d'écriture (5.11)

struct WritingSlotsSettingsView: View {
    @ObservedObject var store: DataStore
    @AppStorage(WritingSlotScheduler.localSwitchKey) private var remindersOnThisMac: Bool = true

    private let days: [(Int, String)] = [
        (2, "L"), (3, "M"), (4, "M"), (5, "J"), (6, "V"), (7, "S"), (1, "D")
    ]

    private var chapters: [(id: UUID, name: String)] {
        store.data.projects.filter { !$0.isArchived }.flatMap { project in
            project.chapters.filter { !$0.isArchived && !$0.isCompleted }.map { ($0.id, $0.name) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: "bell.badge").font(.system(size: 13)).foregroundColor(.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rappels de créneaux sur ce Mac")
                        .font(.system(size: 13, weight: .medium))
                    Text("Les créneaux sont partagés entre tes deux Mac ; les rappels se règlent sur chacun.")
                        .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $remindersOnThisMac)
                    .toggleStyle(.switch).labelsHidden().tint(.accent)
                    .onChange(of: remindersOnThisMac) { _, _ in
                        WritingSlotScheduler.reschedule(store.writingSlots)
                    }
            }
            .padding(14)

            ForEach(store.writingSlots) { slot in
                Divider().padding(.leading, 14)
                slotRow(slot)
            }

            Divider().padding(.leading, 14)
            Button {
                store.updateWritingSlots { $0.append(WritingSlot()) }
            } label: {
                Label("Ajouter un créneau", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accent)
            }
            .buttonStyle(.pressable)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)

            // 5.26 — créneaux lus dans un calendrier (adresse .ics)
            Divider().padding(.leading, 14)
            WritingCalendarSettingsRow()
        }
    }

    private func slotRow(_ slot: WritingSlot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("Nom (ex. Rédaction ch. 4)", text: binding(slot.id, \.labelText, default: ""))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button(role: .destructive) {
                    store.updateWritingSlots { $0.removeAll { $0.id == slot.id } }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12)).foregroundColor(.labelMuted)
                }
                .buttonStyle(.pressable)
                .help("Supprimer ce créneau")
                .accessibilityLabel("Supprimer ce créneau")
            }
            HStack(spacing: 4) {
                ForEach(days, id: \.0) { weekday, label in
                    let isOn = slot.weekdays.contains(weekday)
                    Button {
                        store.updateWritingSlots { slots in
                            guard let i = slots.firstIndex(where: { $0.id == slot.id }) else { return }
                            if isOn { slots[i].weekdays.removeAll { $0 == weekday } } else { slots[i].weekdays.append(weekday) }
                            slots[i].weekdays.sort()
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                            .frame(width: 22, height: 22)
                            .foregroundColor(isOn ? .white : .secondary)
                            .background(Circle().fill(isOn ? Color.accent : Color.fieldBg))
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: isOn ? 0 : 1))
                    }
                    .buttonStyle(.pressable)
                }
                Spacer(minLength: 12)
                DatePicker("", selection: binding(slot.id, \.startDate, default: Date()), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 80)
                Stepper("\(slot.durationMinutes) min", value: binding(slot.id, \.durationMinutes, default: 90), in: 15...480, step: 15)
                    .font(.system(size: 12))
                    .fixedSize()
            }
            Picker("Chapitre", selection: binding(slot.id, \.chapterId, default: nil)) {
                Text("Chapitre actif").tag(UUID?.none)
                ForEach(chapters, id: \.id) { chapter in
                    Text(chapter.name).tag(UUID?.some(chapter.id))
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: 320)
        }
        .padding(14)
    }

    private func binding<T>(_ id: UUID, _ keyPath: WritableKeyPath<WritingSlot, T>, default value: T) -> Binding<T> {
        Binding(
            get: { store.writingSlots.first(where: { $0.id == id })?[keyPath: keyPath] ?? value },
            set: { newValue in
                store.updateWritingSlots { slots in
                    guard let i = slots.firstIndex(where: { $0.id == id }) else { return }
                    slots[i][keyPath: keyPath] = newValue
                }
            }
        )
    }
}

private extension WritingSlot {
    var labelText: String {
        get { label ?? "" }
        set { label = newValue.isEmpty ? nil : newValue }
    }

    var startDate: Date {
        get {
            let time = startTime ?? (9, 0)
            return Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: Date()) ?? Date()
        }
        set {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            start = String(format: "%02d:%02d", comps.hour ?? 9, comps.minute ?? 0)
        }
    }
}

extension PomodoroAppController {
    /// Lance une session depuis un créneau : chapitre du créneau et intention pré-remplie.
    func startWritingSlot(_ slot: WritingSlot, store: DataStore) {
        if let chapterId = slot.chapterId,
           let project = store.data.projects.first(where: { $0.chapters.contains { $0.id == chapterId } }) {
            selectedWritingProjectId = project.id
            selectedWritingChapterId = chapterId
        }
        intentionDraft = slot.displayLabel
        startFocusSession()
    }
}
