import SwiftUI

// MARK: - Mode Élan — fenêtre focus minimale

struct FocusEntryView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var inputText: String = ""
    @State private var savedConfirmation: Bool = false

    // Sélection projet / chapitre
    @State private var selectedProjectId: UUID? = nil
    @State private var selectedChapterId: UUID? = nil

    private var today: String { DataStore.today }

    private var selectedProject: Project? {
        guard let id = selectedProjectId else { return nil }
        return store.data.projects.first(where: { $0.id == id })
    }

    private var selectedChapter: Chapter? {
        guard let project = selectedProject, let id = selectedChapterId else { return nil }
        return project.chapters.first(where: { $0.id == id })
    }

    private var dailyProgress: Int { store.dailyProgress }
    private var dailyGoal: Int { store.data.dailyGoal }

    private var progressFraction: Double {
        guard dailyGoal > 0 else { return 0 }
        return min(1.0, Double(dailyProgress) / Double(dailyGoal))
    }

    private var progressColor: Color {
        if progressFraction >= 1.0 { return .accentGreen }
        if progressFraction >= 0.5 { return .accentWarm }
        return .accent
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accent)
                Text("Élan")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .frame(width: 24, height: 24)
                        .background(Color.fieldBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // MARK: Corps
            VStack(spacing: 12) {
                // Sélecteur projet / chapitre
                HStack(spacing: 8) {
                    // Picker projet
                    Menu {
                        ForEach(store.data.projects) { project in
                            Button(project.name) {
                                selectedProjectId = project.id
                                selectedChapterId = project.activeChapterId ?? project.chapters.first?.id
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedProject?.name ?? "Projet")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selectedProject != nil ? .primary : .labelMuted)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.labelMuted)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Picker chapitre
                    if let project = selectedProject, !project.chapters.isEmpty {
                        Menu {
                            ForEach(project.chapters) { chapter in
                                Button(chapter.name) {
                                    selectedChapterId = chapter.id
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(selectedChapter?.name ?? "Chapitre")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedChapter != nil ? .primary : .labelMuted)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.labelMuted)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.fieldBg)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.cardBorder, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }

                // Champ de saisie
                ZStack(alignment: .center) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.fieldBg)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))

                    if inputText.isEmpty {
                        Text("Nombre de caractères aujourd'hui…")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.labelMuted.opacity(0.5))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $inputText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                }
                .frame(height: 64)

                // Bouton Sauvegarder
                Button {
                    save()
                } label: {
                    HStack(spacing: 6) {
                        if savedConfirmation {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accentGreen)
                            Text("Sauvegardé")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.accentGreen)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 12))
                            Text("Sauvegarder")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .foregroundColor(savedConfirmation ? .accentGreen : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(savedConfirmation ? Color.accentGreen.opacity(0.18) : Color.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || selectedChapterId == nil || selectedProjectId == nil)
                .opacity((inputText.isEmpty || selectedChapterId == nil || selectedProjectId == nil) ? 0.5 : 1.0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // MARK: Footer
            HStack(spacing: 10) {
                // Barre de progression
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("\(store.formatCount(dailyProgress))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        if dailyGoal > 0 {
                            Text("/ \(store.formatCount(dailyGoal))")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                        }
                        Spacer()
                        Text("\(Int(progressFraction * 100))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(progressColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.fieldBg)
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progressColor)
                                .frame(width: geo.size.width * progressFraction, height: 5)
                                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: progressFraction)
                        }
                    }
                    .frame(height: 5)
                }

                // Streak badge
                if store.currentStreak > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color(red: 0.961, green: 0.455, blue: 0.114))
                        Text("\(store.currentStreak)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.961, green: 0.455, blue: 0.114))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.961, green: 0.455, blue: 0.114).opacity(0.10))
                            .overlay(Capsule().stroke(Color(red: 0.961, green: 0.455, blue: 0.114).opacity(0.20), lineWidth: 1))
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .frame(width: 340, height: 220)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .onAppear {
            // Initialiser avec le projet/chapitre actif
            if let activeProjectId = store.data.activeProjectId {
                selectedProjectId = activeProjectId
                if let project = store.data.projects.first(where: { $0.id == activeProjectId }) {
                    selectedChapterId = project.activeChapterId ?? project.chapters.first?.id
                }
            } else {
                selectedProjectId = store.data.projects.first?.id
                if let project = store.data.projects.first {
                    selectedChapterId = project.activeChapterId ?? project.chapters.first?.id
                }
            }
            // Pré-remplir avec la valeur du jour si elle existe
            if let chapter = selectedChapter,
               let entry = chapter.entryForDate(today) {
                inputText = "\(entry.totalCount)"
            }
        }
    }

    // MARK: - Save

    private func save() {
        guard let projectId = selectedProjectId,
              let chapterId = selectedChapterId,
              let count = Int(inputText.trimmingCharacters(in: .whitespaces)) else { return }

        store.setTotalForDate(count, for: chapterId, in: projectId, date: today)

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            savedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation { savedConfirmation = false }
            dismiss()
        }
    }
}
