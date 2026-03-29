import SwiftUI

struct PomodoroSessionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var controller: PomodoroAppController

    let session: PomodoroSessionRecord

    @State private var startedAt: Date
    @State private var endedAt: Date
    @State private var categoryID: UUID?
    @State private var projectID: UUID?
    @State private var note: String
    @State private var completionState: SessionCompletionState

    init(session: PomodoroSessionRecord) {
        self.session = session
        _startedAt = State(initialValue: session.startedAt)
        _endedAt = State(initialValue: session.endedAt)
        _categoryID = State(initialValue: session.categoryID)
        _projectID = State(initialValue: session.projectID)
        _note = State(initialValue: session.note)
        _completionState = State(initialValue: session.completionState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Modifier la session")
                .font(.system(size: 24, weight: .heavy, design: .rounded))

            DatePicker("Début", selection: $startedAt)
            DatePicker("Fin", selection: $endedAt, in: startedAt...)

            Picker("État", selection: $completionState) {
                ForEach(SessionCompletionState.allCases, id: \.self) { state in
                    Text(state.displayName).tag(state)
                }
            }

            Picker("Catégorie", selection: $categoryID) {
                Text("Aucune").tag(UUID?.none)
                ForEach(controller.data.categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }

            Picker("Projet", selection: $projectID) {
                Text("Aucun").tag(UUID?.none)
                ForEach(controller.data.projects) { project in
                    Text(project.name).tag(Optional(project.id))
                }
            }

            Text("Note")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            TextEditor(text: $note)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Button("Annuler") {
                    controller.cancelEditingSession()
                    dismiss()
                }
                .buttonStyle(CockpitButtonStyle())

                Spacer()

                Button("Enregistrer") {
                    controller.saveEditedSession(
                        id: session.id,
                        startedAt: startedAt,
                        endedAt: endedAt,
                        categoryID: categoryID,
                        projectID: projectID,
                        note: note,
                        completionState: completionState
                    )
                    dismiss()
                }
                .buttonStyle(CockpitButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
