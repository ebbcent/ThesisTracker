import SwiftUI

struct PomodoroJournalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var controller: PomodoroAppController

    private var groupedEntries: [(Date, [PomodoroSessionRecord])] {
        let grouped = Dictionary(grouping: controller.journalEntries) { session in
            Calendar.current.startOfDay(for: session.startedAt)
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Journal")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                        Text("Historique complet des sessions, notes et interruptions.")
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    }
                    Spacer()
                    if let selectedDay = controller.selectedJournalDate {
                        HStack(spacing: 8) {
                            Text(selectedDay.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                            Button("Effacer le jour") {
                                controller.clearJournalDateSelection()
                            }
                            .buttonStyle(CockpitButtonStyle())
                        }
                    }
                    TextField("Rechercher dans les notes", text: $controller.journalSearchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280)
                }

                if groupedEntries.isEmpty {
                    InfoCard(title: "Aucune entrée", systemImage: "book.closed") {
                        Text("Aucune session ne correspond aux filtres actifs.")
                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    }
                } else {
                    ForEach(groupedEntries, id: \.0) { day, entries in
                        InfoCard(title: day.formatted(date: .complete, time: .omitted), systemImage: "calendar") {
                            ForEach(entries) { session in
                                HStack(alignment: .top, spacing: 14) {
                                    Circle()
                                        .fill(session.kind == .focus ? CockpitTheme.accent : CockpitTheme.glow)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(session.kind.displayName)
                                                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                                            Spacer()
                                            Text("\(session.startedAt.formatted(date: .omitted, time: .shortened)) - \(session.endedAt.formatted(date: .omitted, time: .shortened))")
                                                .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
                                        }
                                        Text("\(session.completionState.displayName) • \(Int(session.duration / 60)) min • \(controller.categoryName(for: session.categoryID)) • \(controller.projectName(for: session.projectID))")
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                                        if !session.note.isEmpty {
                                            Text(session.note)
                                                .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                                                .padding(.top, 2)
                                        }
                                        HStack(spacing: 8) {
                                            Button("Modifier") {
                                                controller.beginEditingSession(session)
                                            }
                                            .buttonStyle(CockpitButtonStyle())

                                            Button("Supprimer") {
                                                controller.deleteSession(id: session.id)
                                            }
                                            .buttonStyle(CockpitButtonStyle())
                                        }
                                        .padding(.top, 6)
                                    }
                                }
                                if session.id != entries.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(
            LinearGradient(
                colors: [CockpitTheme.backgroundTop(for: colorScheme), CockpitTheme.backgroundBottom(for: colorScheme)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .sheet(item: $controller.editingSessionDraft) { session in
            PomodoroSessionEditorSheet(session: session)
                .environmentObject(controller)
        }
    }
}
