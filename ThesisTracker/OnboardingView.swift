import SwiftUI

// MARK: - #30 · Onboarding First Run
// Affiché une seule fois au premier lancement de l'app.
// 3 étapes : bienvenue → créer un projet → objectif journalier.

struct OnboardingView: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool

    @State private var step: Int = 0
    @State private var projectName: String = ""
    @State private var goalText: String = ""
    @State private var slideOffset: CGFloat = 0

    private let totalSteps = 3

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 6) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Capsule()
                            .fill(i <= step ? Color.accent : Color.cardBorder)
                            .frame(width: i == step ? 20 : 6, height: 6)
                            .appAnimation(Motion.panel, value: step)
                    }
                }
                .padding(.top, 28)

                Spacer()

                // Step content
                Group {
                    switch step {
                    case 0: stepWelcome
                    case 1: stepProject
                    default: stepGoal
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .appAnimation(Motion.panel, value: step)

                Spacer()

                // Navigation
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Retour") {
                            withAppAnimation { step -= 1 }
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .buttonStyle(.pressable)
                    }

                    Spacer()

                    if step < totalSteps - 1 {
                        Button {
                            applyStep()
                            withAppAnimation { step += 1 }
                        } label: {
                            HStack(spacing: 6) {
                                Text(step == 0 ? "Commencer" : "Suivant")
                                    .lineLimit(1)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.pressable)
                        .disabled(step == 1 && projectName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            applyStep()
                            isPresented = false
                        } label: {
                            HStack(spacing: 6) {
                                Text("C'est parti !")
                                    .lineLimit(1)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.accentGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 28)
            }
        }
        .frame(width: 480, height: 380)
    }

    // MARK: - Step 0 — Bienvenue

    private var stepWelcome: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.accent)
            }
            VStack(spacing: 8) {
                Text("Bienvenue dans ThesisTracker")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                Text("Ton compagnon quotidien pour la rédaction de thèse.\nSuivi des progrès, Pomodoro, deadlines — tout au même endroit.")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 1 — Créer un projet

    private var stepProject: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentWarm.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "folder.fill.badge.plus")
                    .font(.system(size: 36))
                    .foregroundColor(.accentWarm)
            }
            VStack(spacing: 8) {
                Text("Nomme ton premier projet")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("En général, le titre de ta thèse ou une version courte.")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
            }
            TextField("Ex : « Thèse de doctorat »", text: $projectName)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(projectName.isEmpty ? Color.cardBorder : Color.accent.opacity(0.4), lineWidth: 1.5))
                .padding(.horizontal, 40)
                .onSubmit {
                    if !projectName.trimmingCharacters(in: .whitespaces).isEmpty {
                        applyStep()
                        withAppAnimation { step += 1 }
                    }
                }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2 — Objectif journalier

    private var stepGoal: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentGreen.opacity(0.12))
                    .frame(width: 80, height: 80)
                Image(systemName: "target")
                    .font(.system(size: 36))
                    .foregroundColor(.accentGreen)
            }
            VStack(spacing: 8) {
                Text("Définis un objectif journalier")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("Combien de caractères veux-tu écrire par jour ? Tu pourras modifier ça plus tard.")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                TextField("Ex : 1500", text: $goalText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cardBorder, lineWidth: 1.5))
                Text("car. / jour")
                    .font(.system(size: 13))
                    .foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 40)

            // Quick presets
            HStack(spacing: 8) {
                ForEach([("500", "Léger"), ("1000", "Régulier"), ("2000", "Intensif")], id: \.0) { value, label in
                    Button {
                        goalText = value
                    } label: {
                        VStack(spacing: 2) {
                            Text(value)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(goalText == value ? .white : .accent)
                            Text(label)
                                .font(.system(size: 10))
                                .foregroundColor(goalText == value ? .white.opacity(0.8) : .labelMuted)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(goalText == value ? Color.accent : Color.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .appAnimation(.easeInOut(duration: 0.15), value: goalText)
                }
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Apply step actions

    private func applyStep() {
        switch step {
        case 1:
            let name = projectName.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            if store.data.projects.isEmpty {
                var project = Project(name: name)
                project.chapters = [Chapter(name: "Chapitre 1", goal: 0)]
                store.data.projects.append(project)
                store.data.activeProjectId = project.id
                store.save()
            }
        case 2:
            if let goal = Int(goalText.trimmingCharacters(in: .whitespaces)), goal > 0 {
                store.data.dailyGoal = goal
                store.save()
            }
        default:
            break
        }
    }
}
