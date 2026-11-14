import SwiftUI

// MARK: - Chapter templates

enum ChapterTemplate: String, CaseIterable, Identifiable {
    case none    = "Aucun"
    case these   = "Thèse"
    case memoire = "Mémoire"
    case roman   = "Roman"
    case article = "Article scientifique"
    case scenario = "Scénario"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .none:    return "xmark.circle"
        case .these:   return "graduationcap.fill"
        case .memoire: return "bookmark.fill"
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
        case .memoire: return [
            ("Introduction", 5000),
            ("Partie I", 15000),
            ("Partie II", 15000),
            ("Partie III", 15000),
            ("Conclusion", 5000),
            ("Bibliographie", 3000)
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
    @State private var selectedProjectTemplate: ProjectTemplate? = nil   // #39 — modèle enrichi
    @State private var showTemplatePicker: Bool = false
    @State private var selectedType: ProjectType? = nil      // V5
    @State private var supervisorText: String = ""           // V5
    @State private var projectNotesText: String = ""         // #16

    var isEditing: Bool { project != nil }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(isEditing ? "Renommer le projet" : "Nouveau projet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                DarkFormField(label: "Nom du projet", placeholder: "ex: Ma thèse, Article Nature…", text: $name, onSubmit: save)

                // V5 — Type de projet
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type de document")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.labelMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // Option "Aucun"
                            Button {
                                withAppAnimation(.easeInOut(duration: 0.15)) { selectedType = nil }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "minus.circle").font(.system(size: 11))
                                    Text("Aucun").font(.system(size: 11, weight: selectedType == nil ? .semibold : .regular))
                                }
                                .foregroundColor(selectedType == nil ? .white : .labelMuted)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(selectedType == nil ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(selectedType == nil ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                            ForEach(ProjectType.allCases, id: \.self) { type in
                                let isSelected = selectedType == type
                                Button {
                                    withAppAnimation(.easeInOut(duration: 0.15)) { selectedType = type }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: type.icon).font(.system(size: 11))
                                        Text(type.label).font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                    }
                                    .foregroundColor(isSelected ? .white : .labelMuted)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(isSelected ? Color.accentWarm.opacity(0.85) : Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(isSelected ? Color.accentWarm : Color.white.opacity(0.1), lineWidth: 1))
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                }

                // V5 — Directeur / co-auteur
                DarkFormField(label: "Directeur / co-auteur (optionnel)", placeholder: "ex: Pr. Martin, Dr. Dupont…", text: $supervisorText)

                // #16 — Notes libres de projet
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes de projet (optionnel)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.labelMuted)
                    TextEditor(text: $projectNotesText)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                        .scrollContentBackground(.hidden)
                        .frame(height: 60)
                        .padding(8)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
                }

                if !isEditing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template de structure (optionnel)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.labelMuted)
                        HStack(spacing: 8) {
                            ForEach(ChapterTemplate.allCases) { template in
                                let isSelected = selectedTemplate == template
                                Button {
                                    withAppAnimation(.easeInOut(duration: 0.15)) {
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
                                .buttonStyle(.pressable)
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
                        // #39 — Modèles enrichis
                        Divider()
                        Button {
                            showTemplatePicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles").font(.system(size: 11)).foregroundColor(.accent)
                                if let t = selectedProjectTemplate {
                                    Text("Modèle : \(t.name)").font(.system(size: 11, weight: .medium)).foregroundColor(.accent)
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundColor(.labelMuted)
                                        .onTapGesture { selectedProjectTemplate = nil; selectedTemplate = .none }
                                } else {
                                    Text("Choisir parmi les modèles enrichis →").font(.system(size: 11, weight: .medium)).foregroundColor(.accent)
                                }
                            }
                        }
                        .buttonStyle(.pressable)
                        .sheet(isPresented: $showTemplatePicker) {
                            ProjectTemplatePickerSheet { tmpl in
                                selectedProjectTemplate = tmpl
                                selectedTemplate = .none
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
                        .buttonStyle(.pressable)
                        .keyboardShortcut(.escape)

                    Spacer()

                    Button(isEditing ? "Enregistrer" : "Créer") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(isValid ? Color.accent : Color.cardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.pressable)
                        .disabled(!isValid)
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: isEditing ? 400 : 480)
        .onAppear {
            name              = project?.name ?? ""
            selectedType      = project?.projectType
            supervisorText    = project?.supervisor ?? ""
            projectNotesText  = project?.notes ?? ""
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let supervisor = supervisorText.trimmingCharacters(in: .whitespaces)
        let notes = projectNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if var existing = project {
            existing.name        = trimmed
            existing.projectType = selectedType
            existing.supervisor  = supervisor.isEmpty ? nil : supervisor
            existing.notes       = notes.isEmpty ? nil : notes
            store.updateProject(existing)
        } else if let tmpl = selectedProjectTemplate {
            // #39 — Modèle enrichi
            store.addProjectWithChapters(name: trimmed, chapters: tmpl.chapters,
                                         type: selectedType,
                                         supervisor: supervisor.isEmpty ? nil : supervisor)
            if !notes.isEmpty, let newId = store.data.projects.last?.id {
                store.updateProjectNotes(notes, for: newId)
            }
        } else if selectedTemplate != .none {
            store.addProjectWithChapters(name: trimmed, chapters: selectedTemplate.chapters,
                                         type: selectedType,
                                         supervisor: supervisor.isEmpty ? nil : supervisor)
            // Apply notes post-creation (#16)
            if !notes.isEmpty, let newId = store.data.projects.last?.id {
                store.updateProjectNotes(notes, for: newId)
            }
        } else {
            store.addProject(name: trimmed, type: selectedType,
                             supervisor: supervisor.isEmpty ? nil : supervisor)
            if !notes.isEmpty, let newId = store.data.projects.last?.id {
                store.updateProjectNotes(notes, for: newId)
            }
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
    @State private var draftVersion: Int = 1   // V5
    @State private var showHistory: Bool = false  // V5 — historique de contexte (#9)
    @State private var chapterPriority: ChapterPriority = .normal  // #35
    @State private var tagsText: String = ""                        // #36 — comma-separated
    @State private var goalKind: ChapterGoalKind = .atLeast           // 5.10
    @State private var excludedFromTotal: Bool = false                // 5.10

    var isEditing: Bool { chapter != nil }

    private var pagesLine: String? {
        let goal = Int(goalText.trimmingCharacters(in: .whitespaces)) ?? 0
        let written = chapter?.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
        guard let calibration = store.pageCalibrationLabel, written > 0 || goal > 0 else { return nil }
        let goalPart = goal > 0 ? store.pagesNumber(goal, digits: 0).map { " sur \($0)" } ?? "" : ""
        let writtenPart = store.pagesNumber(written) ?? "0"
        return "≈ \(writtenPart) pages rédigées\(goalPart) (\(calibration))"
    }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                Text(isEditing ? "Modifier le chapitre" : "Nouveau chapitre")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                DarkFormField(label: "Nom du chapitre", placeholder: "ex: Chapitre 1 — Introduction", text: $name)
                DarkFormField(label: "Objectif (en caractères, optionnel)", placeholder: "ex: 20000 — laisser vide si aucun", text: $goalText)
                if let line = pagesLine {   // 5.12 — équivalent en pages de thèse
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
                ChapterGoalOptionsView(goalKind: $goalKind, excludedFromTotal: $excludedFromTotal)
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
                // V5 — Version de brouillon
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version de brouillon")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.labelMuted)
                        Text("Numéro du draft en cours")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted.opacity(0.6))
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button {
                            if draftVersion > 1 { draftVersion -= 1 }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(draftVersion > 1 ? .accent : .labelMuted.opacity(0.3))
                        }
                        .buttonStyle(.pressable)
                        .help("Diminuer le numéro de version")
                        .accessibilityLabel("Diminuer le numéro de version")
                        Text("v\(draftVersion)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .frame(width: 36)
                        Button {
                            draftVersion += 1
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.accent)
                        }
                        .buttonStyle(.pressable)
                        .help("Augmenter le numéro de version")
                        .accessibilityLabel("Augmenter le numéro de version")
                    }
                }
                .padding(.vertical, 4)

                // #35 — Priorité
                VStack(alignment: .leading, spacing: 8) {
                    Text("Priorité")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.labelMuted)
                    HStack(spacing: 8) {
                        ForEach(ChapterPriority.allCases, id: \.self) { p in
                            let sel = chapterPriority == p
                            Button {
                                chapterPriority = p
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: p.icon).font(.system(size: 10))
                                    Text(p.label).font(.system(size: 11, weight: sel ? .semibold : .regular))
                                }
                                .foregroundColor(sel ? .white : .labelMuted)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(sel ? Color(hex: p.color) : Color.cardBg)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(sel ? Color(hex: p.color) : Color.cardBorder, lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }

                // #36 — Tags libres
                DarkFormField(label: "Tags (séparés par virgule, optionnel)",
                               placeholder: "ex: à relire, validé directeur, brouillon", text: $tagsText)

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Ajouter une échéance", isOn: $hasDeadline)
                        .toggleStyle(.switch)
                        .tint(.accent)

                    if hasDeadline {
                        HStack(spacing: 10) {
                            Text("Échéance")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.labelMuted)
                            CompactDatePicker(
                                date: $deadlineDate,
                                maxDate: Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date(),
                                minDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
                            )
                        }
                        DeadlineSimulatorView(store: store, chapter: chapter, goalText: goalText, deadline: deadlineDate)
                    }
                }

                HStack(spacing: 12) {
                    Button("Annuler") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable)
                        .keyboardShortcut(.escape)

                    // V5 — Historique de contexte (mode édition seulement)
                    if isEditing {
                        Button {
                            showHistory = true
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12))
                                Text("Historique")
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundColor(.accent)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(Color.accent.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accent.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.pressable)
                        .fixedSize()
                    }

                    Spacer()

                    Button(isEditing ? "Enregistrer" : "Créer") { save() }
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.white)
                        .padding(.horizontal, 22).padding(.vertical, 10)
                        .background(isValid ? Color.accent : Color.cardBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .buttonStyle(.pressable)
                        .disabled(!isValid)
                        .fixedSize()
                        .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 400)
        .sheet(isPresented: $showHistory) {
            if let ch = chapter.flatMap({ c in
                store.data.projects.first(where: { $0.id == projectId })?.chapters.first(where: { $0.id == c.id })
            }) {
                ChapterHistoryView(store: store, chapter: ch, projectId: projectId)
            }
        }
        .onAppear {
            if let ch = chapter {
                name             = ch.name
                goalText         = ch.goal > 0 ? "\(ch.goal)" : ""
                notesText        = ch.notes ?? ""
                draftVersion     = ch.draftVersion
                chapterPriority  = ch.priority
                tagsText         = ch.customTags.joined(separator: ", ")
                goalKind         = ch.effectiveGoalKind
                excludedFromTotal = !ch.countsInThesisTotal
                if let deadline = ch.deadline, let parsed = DataStore.parseDate(deadline) {
                    hasDeadline  = true
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
        let parsedTags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let chapterId = chapter?.id {
            guard let projIdx = store.data.projects.firstIndex(where: { $0.id == projectId }),
                  let chapIdx = store.data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId })
            else { dismiss(); return }
            var updated = store.data.projects[projIdx].chapters[chapIdx]
            updated.name         = trimmed
            updated.goal         = goal
            updated.deadline     = deadline
            updated.notes        = notes.isEmpty ? nil : notes
            updated.draftVersion = draftVersion
            updated.priority     = chapterPriority
            updated.customTags   = parsedTags
            updated.goalKind     = goalKind == .atLeast ? nil : goalKind
            updated.excludedFromThesisTotal = excludedFromTotal ? true : nil
            store.updateChapter(updated, in: projectId)
        } else {
            store.addChapter(name: trimmed, goal: goal, deadline: deadline,
                             notes: notes.isEmpty ? nil : notes,
                             draftVersion: draftVersion,
                             to: projectId, chapterFolderId: chapterFolderId)
            // Apply priority and tags post-creation
            if chapterPriority != .normal || !parsedTags.isEmpty,
               let projIdx = store.data.projects.firstIndex(where: { $0.id == projectId }),
               let chapIdx = store.data.projects[projIdx].chapters.indices.last {
                store.data.projects[projIdx].chapters[chapIdx].priority = chapterPriority
                store.data.projects[projIdx].chapters[chapIdx].customTags = parsedTags
                store.save()
            }
            if goalKind != .atLeast || excludedFromTotal,
               let projIdx = store.data.projects.firstIndex(where: { $0.id == projectId }),
               let chapIdx = store.data.projects[projIdx].chapters.indices.last {
                store.data.projects[projIdx].chapters[chapIdx].goalKind = goalKind == .atLeast ? nil : goalKind
                store.data.projects[projIdx].chapters[chapIdx].excludedFromThesisTotal = excludedFromTotal ? true : nil
                store.save()
            }
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
