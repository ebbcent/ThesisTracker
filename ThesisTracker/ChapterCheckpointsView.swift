import SwiftUI

// MARK: - Points de sauvegarde du chapitre (#3)

/// Sheet listant les points de sauvegarde du chapitre actif, avec actions
/// de création manuelle, restauration et suppression.
struct ChapterCheckpointsSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss

    @State private var showSaveSheet = false
    @State private var showSelfReview = false
    @State private var pendingRestoreId: UUID? = nil
    @State private var pendingDeleteId: UUID? = nil

    private var sortedCheckpoints: [ChapterCheckpoint] {
        chapter.checkpoints.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if sortedCheckpoints.isEmpty {
                emptyState
            } else {
                checkpointsList
            }
        }
        .sheetFrame(width: 540, height: 520)
        .sheet(isPresented: $showSaveSheet) {
            SaveCheckpointSheet(store: store, project: project, chapter: chapter)
        }
        .sheet(isPresented: $showSelfReview) {
            SelfReviewSheet(store: store, project: project, chapter: chapter)
        }
        .confirmationDialog(
            "Restaurer ce point de sauvegarde ?",
            isPresented: Binding(
                get: { pendingRestoreId != nil },
                set: { if !$0 { pendingRestoreId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restaurer", role: .destructive) {
                if let id = pendingRestoreId {
                    store.restoreCheckpoint(checkpointId: id, chapterId: chapter.id, in: project.id)
                }
                pendingRestoreId = nil
            }
            Button("Annuler", role: .cancel) { pendingRestoreId = nil }
        } message: {
            Text("Les notes, le plan, les idées et les blockers seront remplacés. Un point « Avant restauration » est créé automatiquement.")
        }
        .confirmationDialog(
            "Supprimer ce point ?",
            isPresented: Binding(
                get: { pendingDeleteId != nil },
                set: { if !$0 { pendingDeleteId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Supprimer", role: .destructive) {
                if let id = pendingDeleteId {
                    store.deleteCheckpoint(checkpointId: id, chapterId: chapter.id, in: project.id)
                }
                pendingDeleteId = nil
            }
            Button("Annuler", role: .cancel) { pendingDeleteId = nil }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Points de sauvegarde")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(chapter.name) · \(sortedCheckpoints.count) point\(sortedCheckpoints.count > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            Button { showSelfReview = true } label: {
                Label("Self-review", systemImage: "star.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accent.opacity(0.10))
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
            Button { showSaveSheet = true } label: {
                Label("Nouveau point", systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
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

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 36))
                .foregroundColor(.labelMuted.opacity(0.5))
            Text("Aucun point de sauvegarde")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.labelMuted)
            Text("Crée un point avant une grosse refonte ou un envoi en relecture pour pouvoir revenir à l'état actuel.")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }

    // MARK: - List

    private var checkpointsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedCheckpoints) { checkpoint in
                    checkpointRow(checkpoint)
                    if checkpoint.id != sortedCheckpoints.last?.id {
                        Divider().padding(.leading, 52)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func checkpointRow(_ checkpoint: ChapterCheckpoint) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(triggerColor(checkpoint.trigger).opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: triggerIcon(checkpoint.trigger))
                    .font(.system(size: 13))
                    .foregroundColor(triggerColor(checkpoint.trigger))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(checkpoint.label)
                        .font(.system(size: 13, weight: .semibold))
                    Text("v\(checkpoint.draftVersion)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.labelMuted.opacity(0.1))
                        .clipShape(Capsule())
                }
                Text(formattedTimestamp(checkpoint.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                HStack(spacing: 10) {
                    if checkpoint.latestTotal > 0 {
                        Label("\(checkpoint.latestTotal.formatted()) car.",
                              systemImage: "text.alignleft")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }
                    if let plan = checkpoint.notesPlan, !plan.isEmpty {
                        Label("Plan", systemImage: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }
                    if let ideas = checkpoint.notesIdeas, !ideas.isEmpty {
                        Label("Idées", systemImage: "lightbulb")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                    }
                    if let blockers = checkpoint.notesBlockers, !blockers.isEmpty {
                        Label("Blockers", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundColor(Color(red: 0.929, green: 0.329, blue: 0.329))
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Button { pendingRestoreId = checkpoint.id } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.accent)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help("Restaurer ce point")
                .accessibilityLabel("Restaurer ce point")
                Button { pendingDeleteId = checkpoint.id } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help("Supprimer")
                .accessibilityLabel("Supprimer")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func triggerColor(_ trigger: ChapterCheckpoint.Trigger) -> Color {
        switch trigger {
        case .manual:         return .accent
        case .beforeReview:   return Color(red: 0.95, green: 0.60, blue: 0.15)
        case .afterAddressed: return Color(red: 0.22, green: 0.75, blue: 0.44)
        }
    }

    private func triggerIcon(_ trigger: ChapterCheckpoint.Trigger) -> String {
        switch trigger {
        case .manual:         return "bookmark.fill"
        case .beforeReview:   return "paperplane.fill"
        case .afterAddressed: return "checkmark.seal.fill"
        }
    }

    private static let timestampDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static let frenchDisplayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy 'à' HH:mm"
        return f
    }()

    private func formattedTimestamp(_ raw: String) -> String {
        if let date = Self.timestampDisplayFormatter.date(from: raw) {
            return Self.frenchDisplayFormatter.string(from: date)
        }
        return raw
    }
}

// MARK: - Sheet : créer un point de sauvegarde manuel

private struct SaveCheckpointSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bookmark.fill").font(.system(size: 16)).foregroundColor(.accent)
                Text("Nouveau point de sauvegarde").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.name).font(.system(size: 13, weight: .semibold))
                Text("Projet : \(project.name) · Draft v\(chapter.draftVersion)")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Étiquette")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.labelMuted)
                TextField("ex. avant refonte du plan, fin du cas d'étude…", text: $label)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(8)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
            }
            Text("Le plan, les idées, les blockers, la prochaine action et le compteur courant seront figés.")
                .font(.system(size: 10))
                .foregroundColor(.labelMuted.opacity(0.7))
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Spacer()
                Button {
                    _ = store.saveCheckpoint(chapterId: chapter.id, in: project.id,
                                             label: label, trigger: .manual)
                    dismiss()
                } label: {
                    Text("Créer le point")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Widget compact pour le Dashboard

struct CheckpointsWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var chapter: Chapter? { store.activeChapter }
    private var project: Project? { store.activeProject }
    private var checkpoints: [ChapterCheckpoint] { chapter?.checkpoints ?? [] }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accent.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accent)
                    }
                    Text("Points de sauvegarde")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !checkpoints.isEmpty {
                        Text("\(checkpoints.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                if chapter == nil {
                    Text("Aucun chapitre sélectionné")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                } else if checkpoints.isEmpty {
                    Text("Crée un point avant une refonte ou un envoi en relecture.")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                } else if let latest = checkpoints.max(by: { $0.timestamp < $1.timestamp }) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted.opacity(0.6))
                        Text("Dernier : \(latest.label) (v\(latest.draftVersion))")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                            .lineLimit(1)
                    }
                }
                Button { showSheet = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: chapter == nil ? "bookmark" : "plus.circle.fill")
                            .font(.system(size: 11))
                        Text(chapter == nil ? "Ouvrir" : (checkpoints.isEmpty ? "Créer un point" : "Voir les points"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(chapter == nil)
            }
        }
        .sheet(isPresented: $showSheet) {
            if let project, let chapter {
                ChapterCheckpointsSheet(store: store, project: project, chapter: chapter)
            }
        }
    }
}
