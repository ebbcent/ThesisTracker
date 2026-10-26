import SwiftUI

// MARK: - Simulateur d'échéance (5.10)
// Affiché sous le choix de la date dans la fiche du chapitre : ce que la date
// choisie demanderait, sans rien enregistrer.

struct DeadlineSimulatorView: View {
    @ObservedObject var store: DataStore
    let chapter: Chapter?
    let goalText: String
    let deadline: Date

    private var goal: Int { Int(goalText.trimmingCharacters(in: .whitespaces)) ?? 0 }

    private var currentTotal: Int {
        chapter?.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
    }

    var body: some View {
        let remaining = max(0, goal - currentTotal)
        let preview = store.quotaPreview(remaining: remaining, deadline: deadline)
        HStack(spacing: 6) {
            Image(systemName: "function")
                .font(.system(size: 10))
                .foregroundColor(.accent)
            Text(text(remaining: remaining, days: preview.days, perDay: preview.perDay))
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func text(remaining: Int, days: Int, perDay: Int) -> String {
        let unit = store.usesWritingCalendar ? "jour(s) d'écriture" : "jour(s)"
        guard goal > 0 else { return "Indique un objectif pour voir le rythme nécessaire." }
        guard remaining > 0 else { return "Objectif déjà atteint." }
        var line = "Avec cette date : \(days) \(unit), \(store.formatCount(perDay)) par jour"
        if let pages = store.pagesLabel(perDay) { line += " (\(pages))" }
        return line + "."
    }
}
