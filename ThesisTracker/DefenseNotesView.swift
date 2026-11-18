import SwiftUI

// MARK: - Notes de soutenance (#2)

/// Widget compact pour le Dashboard montrant le total de notes de soutenance
/// sur le projet actif et permettant d'ouvrir la vue consolidée.
struct DefenseNotesWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var allNotes: [(chapter: Chapter, notes: [DefenseNote])] {
        store.allDefenseNotesForActiveProject
    }
    private var totalNotes: Int { allNotes.reduce(0) { $0 + $1.notes.count } }
    private var byKind: [DefenseNote.Kind: Int] {
        var result: [DefenseNote.Kind: Int] = [:]
        for (_, notes) in allNotes {
            for note in notes { result[note.kind, default: 0] += 1 }
        }
        return result
    }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.semPurple.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.semPurple)
                    }
                    Text("Notes de soutenance")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if totalNotes > 0 {
                        Text("\(totalNotes)")
                            .font(.system(size: AppLook.fs(10), weight: .semibold))
                            .foregroundColor(Color.semPurple)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.semPurple.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if totalNotes == 0 {
                    Text("Capture au fil de la rédaction les points à défendre, les questions probables et les contre-arguments — pour préparer la soutenance dès maintenant.")
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                } else {
                    HStack(spacing: 10) {
                        ForEach(DefenseNote.Kind.allCases, id: \.self) { kind in
                            let count = byKind[kind] ?? 0
                            HStack(spacing: 4) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: AppLook.fs(10)))
                                    .foregroundColor(kind.color)
                                Text("\(count)")
                                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                                    .foregroundColor(.labelMuted)
                            }
                            .help(kind.label)
                        }
                    }
                }

                Button { showSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: totalNotes == 0 ? "plus.circle.fill" : "doc.text.magnifyingglass")
                            .font(.system(size: AppLook.fs(11)))
                        Text(totalNotes == 0 ? "Première note" : "Voir toutes les notes")
                            .font(.system(size: AppLook.fs(11), weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.semPurple)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showSheet) {
            DefenseNotesSheet(store: store)
        }
    }
}

// MARK: - Sheet consolidée

struct DefenseNotesSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: DefenseNote.Kind = .point
    @State private var selectedChapterId: UUID? = nil
    @State private var newNoteText: String = ""
    @State private var editingNoteId: UUID? = nil
    @State private var editingText: String = ""

    private var project: Project? { store.activeProject }
    private var chapters: [Chapter] { project?.chapters ?? [] }
    private var allNotes: [(chapter: Chapter, notes: [DefenseNote])] {
        store.allDefenseNotesForActiveProject
    }

    private var filteredNotes: [(chapter: Chapter, notes: [DefenseNote])] {
        allNotes.compactMap { entry in
            let filtered = entry.notes.filter { $0.kind == selectedKind }
            return filtered.isEmpty ? nil : (entry.chapter, filtered)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            kindTabs
            Divider()
            content
            Divider()
            addBar
        }
        .sheetFrame(width: 640, height: 600)
        .onAppear {
            if selectedChapterId == nil, let first = chapters.first { selectedChapterId = first.id }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes de soutenance").font(.system(size: 16, weight: .semibold))
                Text(project?.name ?? "Aucun projet")
                    .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var kindTabs: some View {
        HStack(spacing: 6) {
            ForEach(DefenseNote.Kind.allCases, id: \.self) { kind in
                let isActive = selectedKind == kind
                Button { selectedKind = kind } label: {
                    HStack(spacing: 5) {
                        Image(systemName: kind.icon).font(.system(size: AppLook.fs(11)))
                        Text(kind.label).font(.system(size: AppLook.fs(11), weight: .semibold))
                    }
                    .foregroundColor(isActive ? .white : kind.color)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isActive ? kind.color : kind.color.opacity(0.10))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if filteredNotes.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: selectedKind.icon)
                    .font(.system(size: 32))
                    .foregroundColor(selectedKind.color.opacity(0.4))
                Text("Aucune note de type « \(selectedKind.label) »")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(30)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(filteredNotes, id: \.chapter.id) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.chapter.name)
                                .font(.system(size: AppLook.fs(11), weight: .bold))
                                .foregroundColor(.labelMuted)
                                .kerning(0.5)
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(entry.notes) { note in
                                    noteRow(note, in: entry.chapter)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.vertical, 14)
            }
        }
    }

    private func noteRow(_ note: DefenseNote, in chapter: Chapter) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundColor(note.kind.color)
                .padding(.top, 6)
            if editingNoteId == note.id {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $editingText)
                        .font(.system(size: 12))
                        .frame(minHeight: 60)
                        .padding(6)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                    HStack(spacing: 6) {
                        Button("Annuler") { editingNoteId = nil }
                            .buttonStyle(.pressable).font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                        Button("Enregistrer") {
                            if let proj = project {
                                store.updateDefenseNote(noteId: note.id, chapterId: chapter.id, in: proj.id, text: editingText)
                            }
                            editingNoteId = nil
                        }
                        .buttonStyle(.pressable)
                        .font(.system(size: AppLook.fs(11), weight: .semibold)).foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.accent)
                        .clipShape(Capsule())
                    }
                }
            } else {
                Text(note.text)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture(count: 2) {
                        editingNoteId = note.id
                        editingText = note.text
                    }
            }
            Button {
                if let proj = project {
                    store.deleteDefenseNote(noteId: note.id, chapterId: chapter.id, in: proj.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted.opacity(0.5))
            }
            .buttonStyle(.pressable)
            .help("Supprimer")
            .accessibilityLabel("Supprimer")
        }
    }

    private var addBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: selectedKind.icon)
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(selectedKind.color)
                Text("Pour")
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted)
                Picker("", selection: $selectedChapterId) {
                    ForEach(chapters) { chapter in
                        Text(chapter.name).tag(Optional(chapter.id))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            HStack(spacing: 8) {
                TextField("Nouvelle note de soutenance…", text: $newNoteText, onCommit: addNote)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                Button(action: addNote) {
                    Text("Ajouter")
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selectedKind.color)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(selectedChapterId == nil || newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func addNote() {
        guard let cid = selectedChapterId, let proj = project else { return }
        store.addDefenseNote(chapterId: cid, in: proj.id, kind: selectedKind, text: newNoteText)
        newNoteText = ""
    }
}
