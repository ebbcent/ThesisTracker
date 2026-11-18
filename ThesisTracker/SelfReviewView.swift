import SwiftUI

// MARK: - Self-review qualité par chapitre

struct SelfReviewSheet: View {
    @ObservedObject var store: DataStore
    let project: Project
    let chapter: Chapter
    @Environment(\.dismiss) private var dismiss

    @State private var clarity: Int = 3
    @State private var argumentation: Int = 3
    @State private var citations: Int = 3
    @State private var transitions: Int = 3
    @State private var originality: Int = 3
    @State private var notes: String = ""

    private struct Criterion: Identifiable {
        let id: String
        let label: String
        let icon: String
        let description: String
    }

    private let criteria: [Criterion] = [
        .init(id: "clarity", label: "Clarté", icon: "eye.fill",
              description: "Le lecteur comprend du premier coup ?"),
        .init(id: "argumentation", label: "Argumentation", icon: "lightbulb.fill",
              description: "Le raisonnement est solide et nuancé ?"),
        .init(id: "citations", label: "Citations", icon: "book.closed.fill",
              description: "Les sources soutiennent vraiment le propos ?"),
        .init(id: "transitions", label: "Transitions", icon: "arrow.left.arrow.right",
              description: "Les paragraphes s'enchaînent naturellement ?"),
        .init(id: "originality", label: "Originalité", icon: "sparkles",
              description: "Apport personnel suffisamment visible ?")
    ]

    private var previous: SelfReview? {
        store.latestSelfReview(chapterId: chapter.id, in: project.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let prev = previous {
                        previousBanner(prev)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(criteria) { criterion in
                            criterionRow(criterion)
                        }
                    }
                    Divider()
                    Text("NOTES")
                        .font(.system(size: AppLook.fs(10), weight: .bold))
                        .foregroundColor(.labelMuted).kerning(0.6)
                    TextEditor(text: $notes)
                        .font(.system(size: 12))
                        .frame(minHeight: 80)
                        .padding(6)
                        .background(Color.fieldBg)
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .sheetFrame(width: 540, height: 600)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Self-review qualité").font(.system(size: 16, weight: .semibold))
                Text("\(chapter.name) · Draft v\(chapter.draftVersion)")
                    .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
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

    private func previousBanner(_ prev: SelfReview) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundColor(.labelMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text("Précédente : \(prev.date) (draft v\(prev.draftVersion))")
                    .font(.system(size: AppLook.fs(11), weight: .semibold))
                Text("Moyenne : \(String(format: "%.1f", prev.average))/5")
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.labelMuted.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
    }

    private func criterionRow(_ c: Criterion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: c.icon)
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.label)
                        .font(.system(size: 13, weight: .semibold))
                    Text(c.description)
                        .font(.system(size: AppLook.fs(10)))
                        .foregroundColor(.labelMuted)
                }
                Spacer()
                Text("\(currentValue(for: c.id))/5")
                    .font(.system(size: AppLook.fs(11), weight: .semibold))
                    .foregroundColor(scoreColor(currentValue(for: c.id)))
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { lvl in
                    Button { setValue(for: c.id, value: lvl) } label: {
                        ZStack {
                            Circle()
                                .fill(currentValue(for: c.id) >= lvl ? scoreColor(currentValue(for: c.id)) : Color.labelMuted.opacity(0.12))
                                .frame(width: 22, height: 22)
                            Text("\(lvl)")
                                .font(.system(size: AppLook.fs(10), weight: .semibold))
                                .foregroundColor(currentValue(for: c.id) >= lvl ? .white : .labelMuted)
                        }
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(10)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(8, 12)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(8, 12)).stroke(Color.cardBorder, lineWidth: 1))
    }

    private var footer: some View {
        HStack {
            Button("Annuler") { dismiss() }
                .buttonStyle(.pressable)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundColor(.labelMuted)
            Spacer()
            let avg = Double(clarity + argumentation + citations + transitions + originality) / 5.0
            Text("Moyenne : \(String(format: "%.1f", avg))/5")
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
            Button {
                _ = store.addSelfReview(
                    chapterId: chapter.id, in: project.id,
                    clarity: clarity, argumentation: argumentation,
                    citations: citations, transitions: transitions,
                    originality: originality, notes: notes
                )
                dismiss()
            } label: {
                Text("Enregistrer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func currentValue(for id: String) -> Int {
        switch id {
        case "clarity":       return clarity
        case "argumentation": return argumentation
        case "citations":     return citations
        case "transitions":   return transitions
        case "originality":   return originality
        default: return 3
        }
    }

    private func setValue(for id: String, value: Int) {
        switch id {
        case "clarity":       clarity = value
        case "argumentation": argumentation = value
        case "citations":     citations = value
        case "transitions":   transitions = value
        case "originality":   originality = value
        default: break
        }
    }

    private func scoreColor(_ value: Int) -> Color {
        switch value {
        case 1: return Color.semRed
        case 2: return Color.semOrange
        case 3: return Color.semYellow
        case 4: return Color(red: 0.50, green: 0.75, blue: 0.30)
        case 5: return Color.semGreen
        default: return .labelMuted
        }
    }
}

// MARK: - Indice "chapitre qui fait mal"

struct PainfulChaptersWidget: View {
    @ObservedObject var store: DataStore

    private var painful: [DataStore.PainfulChapter] { store.painfulChapters }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color.semRed.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "bandage.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.semRed)
                    }
                    Text("Chapitres qui font mal")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                }
                if painful.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentGreen)
                        Text("Aucun chapitre en souffrance — tout coule.")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(painful.prefix(3)) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: AppLook.fs(10)))
                                        .foregroundColor(severityColor(p.score))
                                    Text(p.chapter.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(p.score)/5")
                                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                                        .foregroundColor(severityColor(p.score))
                                }
                                Text(p.reasons.joined(separator: " · "))
                                    .font(.system(size: AppLook.fs(10)))
                                    .foregroundColor(.labelMuted)
                                    .lineLimit(2)
                            }
                            .padding(8)
                            .background(severityColor(p.score).opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                        }
                        if painful.count > 3 {
                            Text("+ \(painful.count - 3) autre\(painful.count - 3 > 1 ? "s" : "")")
                                .font(.system(size: AppLook.fs(10)))
                                .foregroundColor(.labelMuted.opacity(0.7))
                        }
                    }
                }
            }
        }
    }

    private func severityColor(_ score: Int) -> Color {
        switch score {
        case 5: return Color(red: 0.85, green: 0.10, blue: 0.10)
        case 4: return Color.semRed
        case 3: return Color.semOrange
        default: return Color.semYellow
        }
    }
}
