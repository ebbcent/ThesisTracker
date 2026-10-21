import SwiftUI

// MARK: - Options d'objectif du chapitre et état sous la jauge (5.10)

/// Bloc inséré dans la fiche du chapitre : type d'objectif et exclusion du total.
struct ChapterGoalOptionsView: View {
    @Binding var goalKind: ChapterGoalKind
    @Binding var excludedFromTotal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Type d'objectif")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.labelMuted)
                Spacer()
                Picker("", selection: $goalKind) {
                    ForEach(ChapterGoalKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
                .help(goalKind.help)
            }
            Toggle(isOn: $excludedFromTotal) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hors total de la thèse")
                        .font(.system(size: 12, weight: .medium))
                    Text("Annexes, dictionnaire… : exclu du reste à écrire et de la projection, compte toujours pour la série")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .tint(.accent)
        }
    }
}

/// Ligne affichée sous la jauge du chapitre : dépassement, plafond, fourchette, pages.
struct ChapterGoalStatusLine: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter
    let total: Int

    private var message: (text: String, color: Color)? {
        let state = chapter.goalState(total: total)
        let over = chapter.overflow(total: total)
        switch (chapter.effectiveGoalKind, state) {
        case (.atLeast, .reached) where over > 0:
            let pct = Int((Double(total) / Double(chapter.goal) * 100).rounded())
            return ("+\(store.formatCount(over)) au-delà de l'objectif (\(pct) %)", .accentGreen)
        case (.atMost, .inProgress):
            return ("Plafond : encore \(store.formatCount(chapter.goal - total))", .labelMuted)
        case (.atMost, .overCeiling):
            return ("Plafond dépassé de \(store.formatCount(over))", .accentWarm)
        case (.around, .reached):
            return ("Dans la cible (±10 %)", .accentGreen)
        case (.around, .overCeiling):
            return ("Au-dessus de la cible de \(store.formatCount(over))", .accentWarm)
        default:
            return nil
        }
    }

    private var pages: String? {
        guard let current = store.pagesLabel(total) else { return nil }
        guard chapter.goal > 0, let target = store.pagesLabel(chapter.goal) else { return current }
        return "\(current) / \(target.replacingOccurrences(of: "≈ ", with: ""))"
    }

    var body: some View {
        if message != nil || pages != nil {
            HStack(spacing: 8) {
                if let message {
                    Text(message.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(message.color)
                }
                Spacer(minLength: 0)
                if let pages {
                    Text(pages)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .help("Équivalent en pages (Réglages > Calendrier d'écriture)")
                }
            }
            .padding(.top, 4)
        }
    }
}
