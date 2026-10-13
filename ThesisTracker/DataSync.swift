import Foundation

// MARK: - Décodage tolérant
//
// Un seul élément illisible (champ obligatoire manquant, valeur d'un type
// inattendu…) ne doit jamais faire disparaître tout un tableau : on ignore
// l'élément fautif, on garde les autres, et on le signale via le rapport
// passé dans `decoder.userInfo[.lossyReport]` pour que le DataStore mette
// le fichier d'origine de côté avant toute écriture.

final class LossyDecodingReport: @unchecked Sendable {
    private let lock = NSLock()
    private var _droppedCount = 0

    var droppedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _droppedCount
    }

    func recordDrop() {
        lock.lock(); _droppedCount += 1; lock.unlock()
    }
}

extension CodingUserInfoKey {
    static let lossyReport = CodingUserInfoKey(rawValue: "lossyReport")!
}

/// Décode n'importe quelle valeur sans rien lire : sert à faire avancer un
/// conteneur non clé après l'échec du décodage d'un élément.
private struct SkippedElement: Decodable {
    init(from decoder: Decoder) throws {}
}

struct LossyArray<Element: Decodable>: Decodable {
    var elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        if let count = container.count { result.reserveCapacity(count) }
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                result.append(value)
            } else {
                (decoder.userInfo[.lossyReport] as? LossyDecodingReport)?.recordDrop()
                // Sans ce décodage « vide », l'index du conteneur n'avance pas.
                if (try? container.decode(SkippedElement.self)) == nil { break }
            }
        }
        elements = result
    }
}

// MARK: - Fusion à trois voies (deux Mac, un fichier iCloud)
//
// `base`   = contenu du fichier tel qu'on l'a lu ou écrit la dernière fois ;
// `mine`   = état en mémoire sur ce Mac ;
// `theirs` = contenu actuel du fichier (écrit entre-temps par l'autre Mac).
//
// La fusion travaille sur le JSON lui-même, donc elle couvre automatiquement
// tous les champs, y compris ceux ajoutés plus tard au modèle :
// - objets : fusion clé par clé ;
// - tableaux d'objets portant un "id" : fusion élément par élément ;
// - tableaux de valeurs simples : ajouts et suppressions des deux côtés ;
// - même valeur modifiée des deux côtés : ce Mac l'emporte.
// Une modification l'emporte toujours sur une suppression (aucune perte).

enum DataSync {

    /// Fusionne trois versions encodées en JSON. `base == nil` signifie qu'on
    /// ne connaît pas d'ancêtre commun (copies en conflit d'iCloud) : on fait
    /// alors l'union des deux versions.
    static func merge(base: Data?, mine: Data, theirs: Data) -> Data? {
        guard let mineObj = try? JSONSerialization.jsonObject(with: mine, options: [.fragmentsAllowed]),
              let theirsObj = try? JSONSerialization.jsonObject(with: theirs, options: [.fragmentsAllowed])
        else { return nil }
        let baseObj = base.flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
        guard let merged = merge3(base: baseObj, mine: mineObj, theirs: theirsObj) else { return nil }
        return try? JSONSerialization.data(withJSONObject: merged, options: [.fragmentsAllowed])
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (x?, y?): return (x as AnyObject).isEqual(y as AnyObject)
        }
    }

    /// Renvoie `nil` quand la valeur doit être absente du résultat.
    static func merge3(base: Any?, mine: Any?, theirs: Any?) -> Any? {
        if same(mine, theirs) { return mine }
        if base != nil {
            if same(base, mine) { return theirs }
            if same(base, theirs) { return mine }
        }

        // Les deux côtés ont changé (ou pas d'ancêtre commun).
        if let m = mine as? [String: Any], let t = theirs as? [String: Any] {
            let b = base as? [String: Any] ?? [:]
            var out: [String: Any] = [:]
            let keys = Set(m.keys).union(t.keys).union(b.keys)
            for key in keys {
                // Sans ancêtre, une clé absente d'un côté n'est pas une suppression.
                let value = base == nil
                    ? (m[key] != nil && t[key] != nil ? merge3(base: nil, mine: m[key], theirs: t[key]) : (m[key] ?? t[key]))
                    : merge3(base: b[key], mine: m[key], theirs: t[key])
                if let value { out[key] = value }
            }
            return out
        }

        if let m = mine as? [Any], let t = theirs as? [Any] {
            let b = base as? [Any]
            if let merged = mergeIdentifiedArrays(base: b, mine: m, theirs: t) { return merged }
            return mergeScalarArrays(base: b ?? [], mine: m, theirs: t)
        }

        // Valeur simple modifiée des deux côtés, ou supprimée d'un côté et
        // modifiée de l'autre : on garde ce qui existe, priorité à ce Mac.
        return mine ?? theirs
    }

    private static func elementID(_ value: Any) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let id = dict["id"] as? String { return id }
        if let id = dict["id"] as? NSNumber { return id.stringValue }
        return nil
    }

    private static func mergeIdentifiedArrays(base: [Any]?, mine: [Any], theirs: [Any]) -> [Any]? {
        let all = mine + theirs + (base ?? [])
        guard !all.isEmpty, all.allSatisfy({ elementID($0) != nil }) else { return nil }

        func index(_ array: [Any]) -> [String: Any] {
            var map: [String: Any] = [:]
            for element in array { if let id = elementID(element), map[id] == nil { map[id] = element } }
            return map
        }
        let b = index(base ?? [])
        let m = index(mine)
        let t = index(theirs)

        var order: [String] = []
        var seen = Set<String>()
        for element in mine + theirs {
            if let id = elementID(element), seen.insert(id).inserted { order.append(id) }
        }

        var out: [Any] = []
        for id in order {
            let value: Any?
            if base == nil {
                if let mv = m[id], let tv = t[id] {
                    value = merge3(base: nil, mine: mv, theirs: tv)
                } else {
                    value = m[id] ?? t[id]
                }
            } else {
                value = merge3(base: b[id], mine: m[id], theirs: t[id])
            }
            if let value { out.append(value) }
        }
        return out
    }

    private static func mergeScalarArrays(base: [Any], mine: [Any], theirs: [Any]) -> [Any] {
        func contains(_ array: [Any], _ value: Any) -> Bool {
            array.contains { same($0, value) }
        }
        // Éléments de ce Mac, sauf ceux que l'autre Mac a retirés.
        var out = mine.filter { !(contains(base, $0) && !contains(theirs, $0)) }
        // Ajouts de l'autre Mac.
        for value in theirs where !contains(base, value) && !contains(out, value) {
            out.append(value)
        }
        return out
    }

    // MARK: - Normalisation après fusion

    /// Deux Mac peuvent créer chacun une entrée pour le même jour (avec deux
    /// identifiants différents). On n'en garde qu'une : le total le plus élevé
    /// (les compteurs sont cumulés), en conservant une note éventuelle.
    static func normalize(_ data: inout AppData) {
        for p in data.projects.indices {
            for c in data.projects[p].chapters.indices {
                normalize(chapter: &data.projects[p].chapters[c])
            }
        }
    }

    private static func normalize(chapter: inout Chapter) {
        var byDate: [String: DailyEntry] = [:]
        var hadDuplicate = false
        for entry in chapter.entries {
            if var existing = byDate[entry.date] {
                hadDuplicate = true
                var kept = entry.totalCount > existing.totalCount ? entry : existing
                let other = entry.totalCount > existing.totalCount ? existing : entry
                if (kept.note ?? "").isEmpty, let note = other.note, !note.isEmpty { kept.note = note }
                existing = kept
                byDate[entry.date] = existing
            } else {
                byDate[entry.date] = entry
            }
        }
        if hadDuplicate {
            chapter.entries = byDate.values.sorted { $0.date < $1.date }
        }
        for s in chapter.subchapters.indices {
            normalize(chapter: &chapter.subchapters[s])
        }
    }
}
