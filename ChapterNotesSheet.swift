import SwiftUI

// MARK: - ChapterNotesSheet
// Feuille de notes enrichies par chapitre (Feature 3).
// Déclenchée depuis SidebarView sur chaque ligne de chapitre.

struct ChapterNotesSheet: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let projectId: UUID
    @Environment(\.dismiss) var dismiss

    // Copies locales mutables
    @State private var notesText: String = ""
    @State private var noteTags: [NoteTag] = []

    // Création d'un nouveau tag
    @State private var newTagKind: NoteTag.NoteTagKind = .todo
    @State private var newTagText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    freeNotesSection
                    tagsSection
                }
                .padding(20)
            }
            .background(Color.fieldBg.opacity(0.5))
        }
        .frame(width: 520, height: 580)
        .background(Color.cardBg)
        .onAppear {
            notesText = chapter.notes ?? ""
            noteTags  = chapter.noteTags
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accent.opacity(0.12)).frame(width: 36, height: 36)
                Image(systemName: "note.text")
                    .font(.system(size: 15))
                    .foregroundColor(.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Notes — \(chapter.name)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("Notes libres et étiquettes")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .padding(7)
                    .background(Circle().fill(Color.glassFill))
                    .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    // MARK: - Section 1 : Notes libres

    private var freeNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notes libres", systemImage: "text.alignleft")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.5)

            TextEditor(text: $notesText)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 100, maxHeight: 160)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                .onChange(of: notesText) { _ in saveNotes() }
        }
    }

    // MARK: - Section 2 : Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tags", systemImage: "tag")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.5)

            // Liste des tags existants
            if noteTags.isEmpty {
                Text("Aucun tag pour l'instant.")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
                    .padding(.leading, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(noteTags) { tag in
                        HStack(spacing: 8) {
                            Image(systemName: tag.kind.icon)
                                .font(.system(size: 12))
                                .foregroundColor(tag.kind.color)
                                .frame(width: 18)
                            Text(tag.kind.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(tag.kind.color)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(tag.kind.color.opacity(0.12))
                                .clipShape(Capsule())
                            Text(tag.text)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Spacer()
                            Button {
                                deleteTag(tag)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.labelMuted)
                                    .padding(5)
                                    .background(Circle().fill(Color.glassFill))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                    }
                }
            }

            Divider().padding(.vertical, 4)

            // Ligne d'ajout : 4 boutons de type + champ texte + bouton Ajouter
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(NoteTag.NoteTagKind.allCases, id: \.self) { kind in
                        Button {
                            newTagKind = kind
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: kind.icon)
                                    .font(.system(size: 10))
                                Text(kind.rawValue)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(newTagKind == kind ? .white : kind.color)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                Capsule().fill(newTagKind == kind ? kind.color : kind.color.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 8) {
                    TextField("Texte du tag…", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                        .onSubmit { addTag() }

                    Button("Ajouter") { addTag() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(newTagText.trimmingCharacters(in: .whitespaces).isEmpty
                                      ? Color.cardBorder : Color.accent)
                        )
                        .buttonStyle(.plain)
                        .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func saveNotes() {
        var updated = chapter
        updated.notes = notesText.isEmpty ? nil : notesText
        updated.noteTags = noteTags
        store.updateChapter(updated, in: projectId)
    }

    private func addTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = NoteTag(kind: newTagKind, text: trimmed)
        noteTags.append(tag)
        newTagText = ""
        saveTags()
    }

    private func deleteTag(_ tag: NoteTag) {
        noteTags.removeAll { $0.id == tag.id }
        saveTags()
    }

    private func saveTags() {
        var updated = chapter
        updated.notes = notesText.isEmpty ? nil : notesText
        updated.noteTags = noteTags
        store.updateChapter(updated, in: projectId)
    }
}
