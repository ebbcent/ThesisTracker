import SwiftUI

// MARK: - Chapter templates

enum ChapterTemplate: String, CaseIterable, Identifiable {
    case none    = "Aucun"
    case these   = "Thèse"
    case roman   = "Roman"
    case article = "Article scientifique"
    case scenario = "Scénario"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none:    return "xmark.circle"
        case .these:   return "graduationcap.fill"
        case .roman:   return "book.fill"
        case .article: return "doc.text.fill"
        case .scenario: return "film.fill"
        }
    }

    var chapters: [(name: String, goal: Int)] {
        switch self {
        case .none: return []
        case .these: return [
            ("Introduction", 10000),
            ("État de l'art", 30000),
            ("Méthodologie", 20000),
            ("Résultats", 25000),
            ("Discussion", 20000),
            ("Conclusion", 8000),
            ("Bibliographie", 5000)
        ]
        case .roman: return [
            ("Acte I — Exposition", 15000),
            ("Acte II — Développement", 40000),
            ("Acte III — Climax", 20000),
            ("Acte IV — Dénouement", 10000),
            ("Épilogue", 5000)
        ]
        case .article: return [
            ("Abstract", 1000),
            ("Introduction", 4000),
            ("Méthodes", 5000),
            ("Résultats", 6000),
            ("Discussion", 5000),
            ("Conclusion", 2000)
        ]
        case .scenario: return [
            ("Acte 1 (pages 1–30)", 0),
            ("Acte 2a (pages 30–60)", 0),
            ("Acte 2b (pages 60–90)", 0),
            ("Acte 3 (pages 90–120)", 0)
        ]
        }
    }
}

// MARK: - Project form

struct ProjectFormView: View {
    @ObservedObject var store: DataStore
    let project: Project?
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var selectedTemplate: ChapterTemplate = .none

    var isEditing: Bool { project != nil }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(isEditing ? "Renommer le projet" : "Nouveau projet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                DarkFormField(label: "Nom du projet", placeholder: "ex: Ma thèse, Article Nature…", text: $name, onSubmit: save)

                if !isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template de structure (optionnel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.labelMuted)
                        HStack(spacing: 8) {
                            ForEach(ChapterTemplate.allCases) { template in
                                let isSelected = selectedTemplate == template
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        selectedTemplate = template
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: template.icon)
                                            .font(.system(size: 14))
                                            .foregroundColor(isSelected ? .white : .labelMuted)
                                        Text(template.rawValue)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(isSelected ? .white : .secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(isSelected ? Color.accent : Color.cardBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(isSelected ? Color.accent : Color.cardBorder, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if selectedTemplate != .none {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.accentGreen)
                                Text("\(selectedTemplate.chapters.count) chapitres seront créés automatiquement")
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }
                        }
                    }
                }

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

                    Button(isEditing ? "Enregistrer" : "Créer") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(isValid ? Color.accent : Color.cardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                        .disabled(!isValid)
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: isEditing ? 400 : 480)
        .onAppear { name = project?.name ?? "" }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if var existing = project {
            existing.name = trimmed
            store.updateProject(existing)
        } else if selectedTemplate != .none {
            store.addProjectWithChapters(name: trimmed, chapters: selectedTemplate.chapters)
        } else {
            store.addProject(name: trimmed)
        }
        dismiss()
    }
}

// MARK: - Chapter form

struct ChapterFormView: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter?
    let projectId: UUID
    var chapterFolderId: UUID? = nil
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var goalText: String = ""
    @State private var hasDeadline: Bool = false
    @State private var deadlineDate: Date = Date()
    @State private var notesText: String = ""

    var isEditing: Bool { chapter != nil }

    var body: some View {
        ZStack {
            Color.appBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(isEditing ? "Modifier le chapitre" : "Nouveau chapitre")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                DarkFormField(label: "Nom du chapitre", placeholder: "ex: Chapitre 1 — Introduction", text: $name)
                DarkFormField(label: "Objectif (en caractères, optionnel)", placeholder: "ex: 20000 — laisser vide si aucun", text: $goalText)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes (optionnel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.labelMuted)
                    TextEditor(text: $notesText)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Ajouter une deadline", isOn: $hasDeadline)
                        .toggleStyle(.switch)
                        .tint(.accent)

                    if hasDeadline {
                        HStack(spacing: 10) {
                            Text("Deadline")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.labelMuted)
                            CompactDatePicker(
                                date: $deadlineDate,
                                maxDate: Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date(),
                                minDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            )
                        }
                    }
                }

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

                    Button(isEditing ? "Enregistrer" : "Créer") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(isValid ? Color.accent : Color.cardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.plain)
                        .disabled(!isValid)
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 400)
        .onAppear {
            if let ch = chapter {
                name = ch.name
                goalText = ch.goal > 0 ? "\(ch.goal)" : ""
                notesText = ch.notes ?? ""
                if let deadline = ch.deadline, let parsed = DataStore.parseDate(deadline) {
                    hasDeadline = true
                    deadlineDate = parsed
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let goal = Int(goalText.trimmingCharacters(in: .whitespaces)) ?? 0
        let deadline = hasDeadline ? DataStore.dateString(from: deadlineDate) : nil
        let notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let chapterId = chapter?.id {
            // Récupère le chapitre frais depuis le store pour préserver les entrées
            guard let projIdx = store.data.projects.firstIndex(where: { $0.id == projectId }),
                  let chapIdx = store.data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId })
            else { dismiss(); return }
            var updated = store.data.projects[projIdx].chapters[chapIdx]
            updated.name = trimmed
            updated.goal = goal
            updated.deadline = deadline
            updated.notes = notes.isEmpty ? nil : notes
            store.updateChapter(updated, in: projectId)
        } else {
            store.addChapter(name: trimmed, goal: goal, deadline: deadline, notes: notes.isEmpty ? nil : notes, to: projectId, chapterFolderId: chapterFolderId)
        }
        dismiss()
    }
}

// MARK: - Shared form field

struct DarkFormField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.labelMuted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                .onSubmit { onSubmit?() }
        }
    }
}
