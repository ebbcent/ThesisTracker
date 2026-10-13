import SwiftUI

// MARK: - Cooldown post-session

/// Mini-rituel 2 min après une session focus longue (≥45 min) : 3 questions
/// pour capturer la mémoire courte avant qu'elle s'évapore.
/// Le contenu est ajouté au journal de bord + à `nextStep` du chapitre.
struct CooldownSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var accomplishment: String = ""
    @State private var blocker: String = ""
    @State private var nextAction: String = ""
    @State private var focusStep: Int = 0   // 0 → accomplishment, 1 → blocker, 2 → next, 3 → résumé

    private var chapter: Chapter? { store.activeChapter }
    private var project: Project? { store.activeProject }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro
                    questions
                    if focusStep >= 3 { summary }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "wind").foregroundColor(.accent)
                    Text("Cooldown").font(.system(size: 16, weight: .semibold))
                }
                Text("2 minutes pour fixer la mémoire de session.")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.plain)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let chapter {
                Text("CHAPITRE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.6)
                Text(chapter.name)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private var questions: some View {
        VStack(alignment: .leading, spacing: 14) {
            questionBlock(
                index: 0,
                title: "1. Qu'as-tu accompli pendant cette session ?",
                hint: "Sois précis — un paragraphe finalisé, une idée débloquée…",
                text: $accomplishment
            )
            if focusStep >= 1 {
                questionBlock(
                    index: 1,
                    title: "2. Qu'est-ce qui te bloquait ou te ralentissait ?",
                    hint: "Optionnel. Si rien, laisse vide.",
                    text: $blocker
                )
            }
            if focusStep >= 2 {
                questionBlock(
                    index: 2,
                    title: "3. Quelle est la prochaine action concrète ?",
                    hint: "Une phrase. Ça remplacera la « prochaine étape » du chapitre.",
                    text: $nextAction
                )
            }
        }
    }

    private func questionBlock(index: Int, title: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(hint)
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
            TextEditor(text: text)
                .font(.system(size: 12))
                .frame(minHeight: 60)
                .padding(6)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if focusStep == index {
                Button {
                    withAnimation { focusStep += 1 }
                } label: {
                    Text(focusStep == 2 ? "Voir le résumé" : "Continuer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("RÉSUMÉ — ce qui sera enregistré")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.6)
            VStack(alignment: .leading, spacing: 6) {
                if !accomplishment.isEmpty {
                    Label { Text("Journal : \(accomplishment)").font(.system(size: 11)) } icon: {
                        Image(systemName: "book.closed.fill").foregroundColor(Color(red: 0.404, green: 0.224, blue: 0.718))
                    }
                }
                if !blocker.isEmpty {
                    Label { Text("Blockers du chapitre : \(blocker)").font(.system(size: 11)) } icon: {
                        Image(systemName: "exclamationmark.triangle").foregroundColor(Color(red: 0.929, green: 0.329, blue: 0.329))
                    }
                }
                if !nextAction.isEmpty {
                    Label { Text("Prochaine étape : \(nextAction)").font(.system(size: 11)) } icon: {
                        Image(systemName: "arrow.right.circle.fill").foregroundColor(.accent)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Passer") { dismiss() }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundColor(.labelMuted)
            Spacer()
            Button {
                save()
                dismiss()
            } label: {
                Text("Enregistrer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(focusStep < 3)
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
    }

    private func save() {
        let trimmedAcc = accomplishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBlk = blocker.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNxt = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        // Journal : ajoute l'accomplissement comme entrée
        if !trimmedAcc.isEmpty {
            _ = store.addJournalEntry(content: "[Cooldown session] \(trimmedAcc)", tags: ["cooldown"])
        }
        // Chapter : ajoute le blocker et met à jour next step
        guard let chapter = chapter, let project = project else { return }
        if !trimmedBlk.isEmpty {
            let stamp = "[\(DataStore.today)] "
            let newBlockers = (chapter.notesBlockers?.isEmpty == false ? chapter.notesBlockers! + "\n\n" : "")
                + stamp + trimmedBlk
            store.updateChapterNotes(
                plan: chapter.notesPlan,
                ideas: chapter.notesIdeas,
                blockers: newBlockers,
                general: chapter.notes,
                for: chapter.id,
                in: project.id
            )
        }
        if !trimmedNxt.isEmpty {
            store.updateNextStep(trimmedNxt, for: chapter.id, in: project.id)
        }
    }
}
