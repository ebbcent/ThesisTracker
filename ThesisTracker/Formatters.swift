import Foundation

// MARK: - Formatters partagés
//
// Créer un DateFormatter coûte cher : à ne pas faire dans un `body` ou dans une
// boucle. Ces instances sont créées une seule fois et réutilisées (main actor).

enum AppFormatters {
    /// Clé de jour "yyyy-MM-dd" (format de stockage des entrées).
    /// en_US_POSIX + calendrier grégorien : indépendant des réglages régionaux
    /// de l'utilisateur ; fuseau horaire courant (jour local).
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.autoupdatingCurrent
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Affichage court en français : "15 janv. 2024".
    static let frDayMonthYear: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    /// Nombre entier avec espace fine insécable comme séparateur de milliers.
    static let groupedInteger: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f
    }()
}
