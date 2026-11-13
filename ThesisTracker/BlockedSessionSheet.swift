import SwiftUI

// MARK: - Mode panne d'écriture (#3)

/// Mini-protocole anti-blocage : quand l'utilisateur clique « Je suis bloqué »,
/// l'app propose 4 options concrètes au lieu de laisser tomber la session.
struct BlockedSessionSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    let onShortSprint: () -> Void          // lancer un sprint 5 min
    let onSwitchChapter: () -> Void        // ouvrir le picker de chapitre
    let onShowChapterNotes: () -> Void     // ouvrir notes blockers du chapitre

    @State private var blockerText: String = ""
    @State private var showBlockerField = false

    private var chapter: Chapter? { store.activeChapter }
    private var project: Project? { store.activeProject }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    intro
                    optionsGrid
                    if showBlockerField {
                        blockerInput
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 540, height: 540)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(red: 0.929, green: 0.329, blue: 0.329))
                    Text("Session bloquée")
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(chapter?.name ?? "Aucun chapitre actif")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
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

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Avant d'abandonner, essaie une de ces options :")
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsGrid: some View {
        VStack(spacing: 10) {
            option(
                icon: "note.text.badge.plus",
                color: Color(red: 0.404, green: 0.224, blue: 0.718),
                title: "Capturer le blocage",
                subtitle: "Note ce qui te bloque exactement — décharge mentale, et reprends quand tu peux.",
                action: { withAppAnimation { showBlockerField = true } }
            )
            option(
                icon: "timer",
                color: .accent,
                title: "Sprint 5 minutes",
                subtitle: "Écris n'importe quoi pendant 5 min, sans pression de qualité. Souvent ça débloque.",
                action: { dismiss(); onShortSprint() }
            )
            option(
                icon: "arrow.left.arrow.right",
                color: Color(red: 0.300, green: 0.650, blue: 0.900),
                title: "Changer de chapitre",
                subtitle: "Tu butes peut-être sur ce chapitre précis. Avance ailleurs et reviens à tête reposée.",
                action: { dismiss(); onSwitchChapter() }
            )
            option(
                icon: "cup.and.saucer.fill",
                color: Color(red: 0.961, green: 0.620, blue: 0.043),
                title: "Pause forcée 15 min",
                subtitle: "Éloigne-toi de l'écran. Pas de scroll. Marche, bois, reviens neuf.",
                action: { dismiss() }
            )
        }
    }

    private func option(icon: String, color: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.labelMuted.opacity(0.4))
            }
            .padding(14)
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var blockerInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Le blocage")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.labelMuted)
            TextEditor(text: $blockerText)
                .font(.system(size: 12))
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button {
                    saveBlocker()
                } label: {
                    Text("Ajouter aux blockers du chapitre")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(blockerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chapter == nil)
            }
        }
    }

    private func saveBlocker() {
        let trimmed = blockerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let chapter, let project else { return }
        let stamp = "[\(DataStore.today)] "
        let newBlocker = (chapter.notesBlockers?.isEmpty == false ? chapter.notesBlockers! + "\n\n" : "")
            + stamp + trimmed
        store.updateChapterNotes(
            plan: chapter.notesPlan,
            ideas: chapter.notesIdeas,
            blockers: newBlocker,
            general: chapter.notes,
            for: chapter.id,
            in: project.id
        )
        dismiss()
    }
}
