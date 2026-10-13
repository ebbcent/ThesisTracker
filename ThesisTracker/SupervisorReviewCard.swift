import SwiftUI

// MARK: - Carte "Relectures directeur" pour le chapitre actif

/// Affiche l'état du cycle de relecture en cours pour le chapitre actif :
/// non envoyé → envoyé → reçu → intégré. Permet d'ouvrir les sheets d'action.
struct SupervisorReviewCard: View {
    @ObservedObject var store: DataStore
    @State private var showSendSheet = false
    @State private var showReceiveSheet = false
    @State private var showNotesSheet = false

    private var project: Project? { store.activeProject }
    private var chapter: Chapter? { store.activeChapter }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                header
                if let chapter {
                    body(for: chapter)
                } else {
                    Text("Aucun chapitre sélectionné")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
            }
        }
        .sheet(isPresented: $showSendSheet) {
            if let project, let chapter {
                SendForReviewSheet(store: store, project: project, chapter: chapter)
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            if let project, let chapter {
                ReceiveReviewSheet(store: store, project: project, chapter: chapter)
            }
        }
        .sheet(isPresented: $showNotesSheet) {
            if let project, let chapter {
                ReviewNotesSheet(store: store, project: project, chapter: chapter)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(stateColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: chapter?.reviewState.icon ?? "tray")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(stateColor)
            }
            Text("Relecture directeur")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Spacer()
            if let chapter {
                Text(chapter.reviewState.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(stateColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(stateColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(stateColor.opacity(0.25), lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private func body(for chapter: Chapter) -> some View {
        switch chapter.reviewState {
        case .notSent:
            notSentBody(chapter)
        case .sent:
            sentBody(chapter)
        case .received:
            receivedBody(chapter)
        case .addressed:
            addressedBody(chapter)
        }
    }

    private var stateColor: Color { chapter?.reviewState.color ?? .labelMuted }

    // MARK: - States

    @ViewBuilder
    private func notSentBody(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draft v\(chapter.draftVersion) prêt à envoyer ?")
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
            HStack {
                Button { showSendSheet = true } label: {
                    Label("Envoyer en relecture", systemImage: "paperplane.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if !chapter.supervisorReviews.isEmpty {
                    Text("Cycle précédent : v\(chapter.supervisorReviews.last?.draftVersion ?? 1)")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted.opacity(0.7))
                }
            }
        }
    }

    @ViewBuilder
    private func sentBody(_ chapter: Chapter) -> some View {
        let review = chapter.currentReview!
        let days = chapter.daysSinceSent() ?? 0
        VStack(alignment: .leading, spacing: 8) {
            statLine(icon: "paperplane.fill",
                     text: "Envoyé le \(formatDateShort(review.sentDate)) · il y a \(days) j")
            if let expected = review.expectedReturnDate {
                statLine(icon: "calendar",
                         text: "Retour attendu : \(formatDateShort(expected))")
            }
            HStack(spacing: 6) {
                Button { showReceiveSheet = true } label: {
                    Label("Marquer reçu", systemImage: "envelope.open.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    if let proj = project {
                        store.cancelLastChapterReview(chapterId: chapter.id, in: proj.id)
                    }
                } label: {
                    Text("Annuler")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func receivedBody(_ chapter: Chapter) -> some View {
        let review = chapter.currentReview!
        VStack(alignment: .leading, spacing: 8) {
            statLine(icon: "envelope.open.fill",
                     text: "Retour reçu le \(formatDateShort(review.receivedDate))")
            if let notes = review.feedbackNotes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 11))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineLimit(3)
                    .padding(8)
                    .background(stateColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Button { showNotesSheet = true } label: {
                    Label("Ajouter notes du feedback", systemImage: "text.bubble")
                        .font(.system(size: 11))
                        .foregroundColor(.accent)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Button {
                    if let proj = project {
                        store.markChapterReviewAddressed(chapterId: chapter.id, in: proj.id)
                    }
                } label: {
                    Label("Feedback intégré", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accentGreen)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if review.feedbackNotes?.isEmpty == false {
                    Button { showNotesSheet = true } label: {
                        Text("Modifier notes")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func addressedBody(_ chapter: Chapter) -> some View {
        let review = chapter.currentReview!
        VStack(alignment: .leading, spacing: 8) {
            statLine(icon: "checkmark.seal.fill",
                     text: "Feedback v\(review.draftVersion) intégré le \(formatDateShort(review.addressedDate))")
            Text("Draft courant : v\(chapter.draftVersion)")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
            Button { showSendSheet = true } label: {
                Label("Nouveau cycle de relecture", systemImage: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func statLine(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.labelMuted.opacity(0.6))
                .frame(width: 12)
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
        }
    }

    private func formatDateShort(_ dateStr: String?) -> String {
        guard let s = dateStr, let date = DataStore.parseDate(s) else { return "—" }
        return DataStore.formatDate(date)
    }
}

// MARK: - Sheet : envoyer en relecture

private struct SendForReviewSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss
    @State private var hasReturnDate: Bool = true
    @State private var returnDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "paperplane.fill").font(.system(size: 16)).foregroundColor(.accent)
                Text("Envoyer en relecture").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.name).font(.system(size: 13, weight: .semibold))
                Text("Projet : \(project.name) · Draft v\(chapter.draftVersion)")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Toggle(isOn: $hasReturnDate) {
                Text("Date prévue du retour").font(.system(size: 12))
            }
            if hasReturnDate {
                DatePicker("", selection: $returnDate, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
            }
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Spacer()
                Button {
                    let expected = hasReturnDate ? DataStore.dateString(from: returnDate) : nil
                    store.sendChapterForReview(chapterId: chapter.id, in: project.id,
                                                expectedReturnDate: expected)
                    dismiss()
                } label: {
                    Text("Confirmer l'envoi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Sheet : feedback reçu

private struct ReceiveReviewSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackNotes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.open.fill").font(.system(size: 16)).foregroundColor(.accent)
                Text("Retour directeur reçu").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.name).font(.system(size: 13, weight: .semibold))
                Text("Projet : \(project.name)")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Text("Notes du feedback (optionnel)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.labelMuted)
            TextEditor(text: $feedbackNotes)
                .font(.system(size: 12))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Spacer()
                Button {
                    let trimmed = feedbackNotes.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.markChapterReviewReceived(chapterId: chapter.id, in: project.id,
                                                    feedbackNotes: trimmed.isEmpty ? nil : trimmed)
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
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

// MARK: - Sheet : éditer les notes

private struct ReviewNotesSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble").font(.system(size: 16)).foregroundColor(.accent)
                Text("Notes du feedback").font(.system(size: 15, weight: .bold))
                Spacer()
            }
            TextEditor(text: $notes)
                .font(.system(size: 12))
                .frame(minHeight: 200)
                .padding(8)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
            HStack {
                Button("Annuler") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                Spacer()
                Button {
                    store.updateChapterReviewNotes(chapterId: chapter.id, in: project.id, notes: notes)
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
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            notes = chapter.currentReview?.feedbackNotes ?? ""
        }
    }
}
