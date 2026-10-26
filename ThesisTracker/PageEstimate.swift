import Foundation

// MARK: - Équivalent en pages (5.10)
// Les comptes sont toujours stockés en caractères ; une page vaut
// `writingSchedule.charsPerPage` caractères (réglage vide = pas d'affichage).

extension DataStore {

    static let pagePresets: [(chars: Int, label: String)] = [
        (0, "Pas d'affichage"),
        (1_500, "1 500 signes (feuillet)"),
        (1_800, "1 800 signes (60 × 30)"),
        (2_000, "2 000 signes"),
        (2_500, "2 500 signes"),
        (3_000, "3 000 signes")
    ]

    var charsPerPage: Int? {
        guard let value = data.writingSchedule?.charsPerPage, value > 0 else { return nil }
        return value
    }

    static func pages(chars: Int, charsPerPage: Int) -> Double {
        guard charsPerPage > 0 else { return 0 }
        return Double(max(0, chars)) / Double(charsPerPage)
    }

    private static func pageFormatter(fractionDigits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = fractionDigits
        return f
    }
    private static let shortPageFormatter = pageFormatter(fractionDigits: 1)
    private static let longPageFormatter = pageFormatter(fractionDigits: 0)

    /// « ≈ 3,5 p. » sous 10 pages, « ≈ 42 p. » au-delà.
    static func pagesLabel(chars: Int, charsPerPage: Int) -> String {
        let value = pages(chars: chars, charsPerPage: charsPerPage)
        let formatter = value < 10 ? shortPageFormatter : longPageFormatter
        let text = formatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
        return "≈ \(text) p."
    }

    /// Nil quand aucun format de page n'est réglé.
    func pagesLabel(_ chars: Int) -> String? {
        guard let cpp = charsPerPage else { return nil }
        return DataStore.pagesLabel(chars: chars, charsPerPage: cpp)
    }
}
