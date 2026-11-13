import SwiftUI

// MARK: - Feature #2 : Suivi du temps de recherche

struct ResearchTimeCard: View {
    @ObservedObject var store: DataStore
    @State private var showLogSheet = false

    private var todayStr: String { DataStore.today }
    private var todayEntries: [ResearchEntry] { store.researchEntries(for: todayStr) }
    private var todayMinutes: Int { store.totalResearchMinutes(for: todayStr) }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: "#0F766E").opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "#0F766E"))
                        }
                        Text("Temps de recherche")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button {
                        showLogSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.accent)
                            .frame(width: 22, height: 22)
                            .background(Color.accent.opacity(0.10))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.pressable)
                    .help("Ajouter une session")
                    .accessibilityLabel("Ajouter une session")
                }

                if todayEntries.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.5))
                        Text("Aucune session aujourd'hui")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Spacer()
                    }
                } else {
                    // Total
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatDuration(todayMinutes))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("aujourd'hui")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Spacer()
                    }

                    // Type breakdown
                    let grouped = Dictionary(grouping: todayEntries) { $0.type }
                    HStack(spacing: 8) {
                        ForEach(ResearchType.allCases.filter { grouped[$0] != nil }, id: \.self) { type in
                            let mins = grouped[type]!.reduce(0) { $0 + $1.durationMinutes }
                            typePill(type: type, minutes: mins)
                        }
                        Spacer()
                    }

                    // Entry list
                    VStack(spacing: 4) {
                        ForEach(todayEntries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            ResearchLogSheet(store: store, isPresented: $showLogSheet)
        }
    }

    private func typePill(type: ResearchType, minutes: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: type.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(formatDuration(minutes))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(Color(hex: type.color))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color(hex: type.color).opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(hex: type.color).opacity(0.22), lineWidth: 1))
    }

    private func entryRow(_ entry: ResearchEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: entry.type.icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: entry.type.color))
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.type.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(formatDuration(entry.durationMinutes))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Button {
                store.deleteResearchEntry(entry.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted.opacity(0.5))
            }
            .buttonStyle(.pressable)
            .help("Supprimer la session")
            .accessibilityLabel("Supprimer la session")
        }
        .padding(.vertical, 3)
    }

    private func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}

// MARK: - Log Sheet

struct ResearchLogSheet: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool

    @State private var selectedType: ResearchType = .lecture
    @State private var durationHours: Int = 0
    @State private var durationMinutes: Int = 30
    @State private var note: String = ""
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedChapterId: UUID? = nil

    private var activeProject: Project? {
        guard let pid = selectedProjectId else { return nil }
        return store.data.projects.first { $0.id == pid }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Ajouter une session")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .padding(7)
                        .background(Color.cardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .help("Fermer")
                .accessibilityLabel("Fermer")
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Type
                    VStack(alignment: .leading, spacing: 8) {
                        label("Type d'activité")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 6) {
                            ForEach(ResearchType.allCases) { type in
                                typeButton(type)
                            }
                        }
                    }

                    // Durée
                    VStack(alignment: .leading, spacing: 8) {
                        label("Durée")
                        HStack(spacing: 12) {
                            durationPicker(value: $durationHours, label: "h", range: 0...12)
                            durationPicker(value: $durationMinutes, label: "min", range: 0...55, step: 5)
                        }
                    }

                    // Note
                    VStack(alignment: .leading, spacing: 8) {
                        label("Note (optionnel)")
                        TextField("Ex : papers sur le chapitre 3, réunion avec directeur…", text: $note)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(10)
                            .background(Color.fieldBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                    }

                    // Projet / Chapitre (optionnel)
                    if !store.data.projects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            label("Associer à (optionnel)")
                            HStack(spacing: 8) {
                                Picker("Projet", selection: $selectedProjectId) {
                                    Text("— Projet —").tag(UUID?.none)
                                    ForEach(store.data.projects.filter { !$0.isArchived }) { p in
                                        Text(p.name).tag(UUID?.some(p.id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity)
                                .onChange(of: selectedProjectId) { _, _ in selectedChapterId = nil }

                                if let project = activeProject, !project.chapters.isEmpty {
                                    Picker("Chapitre", selection: $selectedChapterId) {
                                        Text("— Chapitre —").tag(UUID?.none)
                                        ForEach(project.chapters) { ch in
                                            Text(ch.name).tag(UUID?.some(ch.id))
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("Annuler") { isPresented = false }
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .buttonStyle(.pressable)

                Button("Enregistrer") { save() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(totalMinutes > 0 ? Color.accent : Color.accent.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .buttonStyle(.pressable)
                    .disabled(totalMinutes == 0)
            }
            .padding(20)
        }
        .sheetFrame(width: 420, height: 540)
        .background(Color.cardBg)
    }

    private var totalMinutes: Int { durationHours * 60 + durationMinutes }

    private func save() {
        guard totalMinutes > 0 else { return }
        let entry = ResearchEntry(
            date: DataStore.today,
            durationMinutes: totalMinutes,
            type: selectedType,
            note: note.isEmpty ? nil : note,
            projectId: selectedProjectId,
            chapterId: selectedChapterId
        )
        store.addResearchEntry(entry)
        isPresented = false
    }

    @ViewBuilder
    private func typeButton(_ type: ResearchType) -> some View {
        let isSelected = selectedType == type
        Button { selectedType = type } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 11))
                Text(type.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? Color(hex: type.color) : .labelMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color(hex: type.color).opacity(0.10) : Color.fieldBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color(hex: type.color).opacity(0.35) : Color.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
    }

    private func durationPicker(value: Binding<Int>, label: String, range: ClosedRange<Int>, step: Int = 1) -> some View {
        HStack(spacing: 6) {
            Picker("", selection: value) {
                ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: step)), id: \.self) { v in
                    Text("\(v)").tag(v)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 70)
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.labelMuted)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.labelMuted)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
