import SwiftUI

// MARK: - Historique de contexte par chapitre (V5 — amélioration #9)
// Journal chronologique des modifications significatives d'un chapitre.

struct ChapterHistoryView: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let projectId: UUID
    @Environment(\.dismiss) var dismiss

    @State private var newNoteText: String = ""
    @FocusState private var noteFocused: Bool

    private var entries: [ChapterLogEntry] {
        // Affiche les plus récentes en premier
        chapter.logEntries.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {

                // En-tête
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Historique")
                            .font(.system(size: 20, weight: .bold, design: AppLook.fontDesign))
                            .foregroundColor(.primary)
                        Text(chapter.name)
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button("Fermer") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.cardBg)
                        .clipShape(AppLook.buttonShape(8))
                        .overlay(AppLook.buttonShape(8).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable)
                        .keyboardShortcut(.escape)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Divider().opacity(0.5)

                // Champ d'ajout de note
                HStack(spacing: 10) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 13))
                        .foregroundColor(.accent)
                    TextField("Ajouter une note de contexte…", text: $newNoteText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .focused($noteFocused)
                        .onSubmit { addManualNote() }
                    if !newNoteText.isEmpty {
                        Button(action: addManualNote) {
                            Image(systemName: "return")
                                .font(.system(size: AppLook.fs(11), weight: .semibold))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.accent)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.pressable)
                        .help("Ajouter la note")
                        .accessibilityLabel("Ajouter la note")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.cardBg.opacity(0.6))

                Divider().opacity(0.4)

                // Liste des entrées
                if entries.isEmpty {
                    VStack(spacing: 10) {
                        Spacer()
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundColor(.labelMuted.opacity(0.3))
                        Text("Aucune entrée dans l'historique")
                            .font(.system(size: 13))
                            .foregroundColor(.labelMuted.opacity(0.5))
                        Text("Les mises à jour de compteur, changements de statut\net tes notes apparaîtront ici.")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted.opacity(0.4))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                logRow(entry)
                                Divider()
                                    .padding(.leading, 50)
                                    .opacity(0.3)
                            }
                        }
                        .padding(.bottom, 16)
                    }
                }
            }
        }
        .frame(width: 480)
        .frame(minHeight: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { noteFocused = true }
        }
    }

    // ── Ligne d'entrée ────────────────────────────────────────────

    private func logRow(_ entry: ChapterLogEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Icône
            ZStack {
                Circle()
                    .fill(iconColor(entry.type).opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: entry.icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor(entry.type))
            }

            // Contenu
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(formattedTimestamp(entry.timestamp))
                    .font(.system(size: AppLook.fs(11)))
                    .foregroundColor(.labelMuted.opacity(0.6))
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func iconColor(_ type: ChapterLogEntry.LogType) -> Color {
        switch type {
        case .manual:       return .accent
        case .wordUpdate:   return .accentGreen
        case .statusChange: return .blue
        case .draftBump:    return .orange
        case .noteSession:  return .purple
        }
    }

    // ── Helpers ───────────────────────────────────────────────────

    private func addManualNote() {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let entry = ChapterLogEntry(
            timestamp: ChapterLogEntry.nowTimestamp(),
            type: .manual,
            content: text
        )
        store.addLogEntry(entry, for: chapter.id, in: projectId)
        newNoteText = ""
    }

    private func formattedTimestamp(_ ts: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        guard let date = fmt.date(from: ts) else { return ts }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }
}
