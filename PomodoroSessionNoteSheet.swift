import SwiftUI

struct PomodoroSessionNoteSheet: View {
    @EnvironmentObject private var controller: PomodoroAppController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Session terminée")
                .font(.title2.bold())
            Text("Ajoute une note et le nombre de mots écrits pendant cette session.")
                .foregroundStyle(.secondary)

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
