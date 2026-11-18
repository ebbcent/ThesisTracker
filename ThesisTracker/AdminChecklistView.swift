import SwiftUI

// MARK: - Checklist administrative

struct AdminChecklistWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var upcoming: [AdminTask] { store.upcomingAdminTasks }
    private var dueSoon: [AdminTask] {
        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())
        return upcoming.filter { t in
            guard let str = t.dueDate, let d = DataStore.parseDate(str) else { return false }
            let days = cal.dateComponents([.day], from: today, to: d).day ?? 0
            return days <= 14
        }
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.semSky.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "tray.full.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.semSky)
                    }
                    Text("Administratif")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !upcoming.isEmpty {
                        Text("\(upcoming.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.labelMuted.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                if upcoming.isEmpty {
                    Text("Pas de tâche administrative en cours.")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(upcoming.prefix(3)) { task in
                            taskMini(task)
                        }
                        if upcoming.count > 3 {
                            Text("+ \(upcoming.count - 3) autre\(upcoming.count - 3 > 1 ? "s" : "")")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }
                }
                Button { showSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: upcoming.isEmpty ? "plus.circle.fill" : "list.bullet.rectangle")
                            .font(.system(size: 11))
                        Text(upcoming.isEmpty ? "Ajouter une tâche" : "Voir tout")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.semSky)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showSheet) {
            AdminChecklistSheet(store: store)
        }
    }

    private func taskMini(_ task: AdminTask) -> some View {
        HStack(spacing: 6) {
            Image(systemName: task.kind.icon)
                .font(.system(size: 10))
                .foregroundColor(task.kind.color)
                .frame(width: 14)
            Text(task.title)
                .font(.system(size: 11))
                .foregroundColor(.primary)
                .lineLimit(1)
            Spacer()
            if let dueStr = task.dueDate {
                Text(dueLabel(dueStr))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(dueColor(dueStr))
            }
        }
    }

    private func dueLabel(_ str: String) -> String {
        guard let d = DataStore.parseDate(str) else { return str }
        let cal = DataStore.gregorianCal
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days == 0 { return "Aujourd'hui" }
        if days < 0 { return "−\(abs(days)) j" }
        return "J−\(days)"
    }
    private func dueColor(_ str: String) -> Color {
        guard let d = DataStore.parseDate(str) else { return .labelMuted }
        let cal = DataStore.gregorianCal
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days < 0 { return Color.semRed }
        if days <= 7 { return Color.semRed }
        if days <= 30 { return Color.semOrange }
        return .labelMuted
    }
}

// MARK: - Sheet

struct AdminChecklistSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSheet = false
    @State private var showCompleted = false

    private var tasks: [AdminTask] {
        let base = showCompleted
            ? store.data.adminTasks.filter { $0.isCompleted }
            : store.upcomingAdminTasks
        return base
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if tasks.isEmpty {
                emptyState
            } else {
                listView
            }
        }
        .sheetFrame(width: 580, height: 580)
        .sheet(isPresented: $showAddSheet) {
            AddAdminTaskSheet(store: store)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Administratif").font(.system(size: 16, weight: .semibold))
                Text("\(store.upcomingAdminTasks.count) tâche\(store.upcomingAdminTasks.count > 1 ? "s" : "") en cours")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Toggle(isOn: $showCompleted) {
                Text("Terminées").font(.system(size: 11))
            }
            .toggleStyle(.switch)
            Button { showAddSheet = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Ajouter").font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.semSky)
                .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text(showCompleted ? "Aucune tâche terminée" : "Aucune tâche en cours")
                .font(.system(size: 13))
                .foregroundColor(.labelMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(tasks) { task in
                    taskRow(task)
                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: AdminTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { store.toggleAdminTask(task.id) } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(task.isCompleted ? .accentGreen : .labelMuted.opacity(0.5))
            }
            .buttonStyle(.pressable)
            .help(task.isCompleted ? "Marquer comme non fait" : "Marquer comme fait")
            .accessibilityLabel(task.isCompleted ? "Marquer comme non fait" : "Marquer comme fait")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: task.kind.icon)
                        .font(.system(size: 10))
                        .foregroundColor(task.kind.color)
                    Text(task.kind.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(task.kind.color)
                        .kerning(0.5)
                }
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(task.isCompleted ? .labelMuted : .primary)
                    .strikethrough(task.isCompleted, color: .labelMuted)
                if let due = task.dueDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted.opacity(0.7))
                        Text(due)
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }
                }
                if let notes = task.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
            Button { store.deleteAdminTask(task.id) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted.opacity(0.5))
            }
            .buttonStyle(.pressable)
            .help("Supprimer la tâche")
            .accessibilityLabel("Supprimer la tâche")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }
}

private struct AddAdminTaskSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var kind: AdminTask.Kind = .form
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date().addingTimeInterval(60*60*24*14)
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nouvelle tâche administrative")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Type").font(.system(size: 11, weight: .medium)).foregroundColor(.labelMuted)
                Picker("", selection: $kind) {
                    ForEach(AdminTask.Kind.allCases, id: \.self) { k in
                        Label(k.label, systemImage: k.icon).tag(k)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Titre").font(.system(size: 11, weight: .medium)).foregroundColor(.labelMuted)
                TextField("ex. rendre le rapport d'avancement…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
            }
            Toggle(isOn: $hasDueDate) {
                Text("Échéance").font(.system(size: 12))
            }
            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (optionnel)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.labelMuted)
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .frame(minHeight: 60)
                    .padding(6)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
            }
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Spacer()
                Button {
                    _ = store.addAdminTask(
                        title: title,
                        kind: kind,
                        dueDate: hasDueDate ? DataStore.dateString(from: dueDate) : nil,
                        notes: notes.isEmpty ? nil : notes
                    )
                    dismiss()
                } label: {
                    Text("Ajouter")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
