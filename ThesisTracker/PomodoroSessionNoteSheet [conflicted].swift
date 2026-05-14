import SwiftUI

struct PomodoroSessionNoteSheet: View {
    @EnvironmentObject private var controller: PomodoroAppController
    @ObservedObject var store: DataStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // En-tête avec delta d'écriture (#43)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session terminée")
                        .font(.title2.bold())
                    Text("Ajoute une note et le nombre de mots écrits pendant cette session.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // #43 — badge delta écriture
                if let delta = controller.sessionWritingDelta, delta > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("+" + store.formatCount(delta))
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.accentGreen)
                        Text("pendant cette session")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.accentGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentGreen.opacity(0.25), lineWidth: 1))
                }
            }

            TextEditor(text: $controller.noteDraft)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Image(systemName: "text.word.spacing")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                TextField("Mots écrits (optionnel)", text: $controller.wordCountDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            }

            HStack {
                Spacer()
                Button("Enregistrer") {
                    controller.saveNoteForLastCompletedSession()
                }
                .buttonStyle(CockpitButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
