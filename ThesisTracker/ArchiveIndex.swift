import Foundation

// MARK: - Archives : rapprochement PDF ↔ fiches ↔ inventaire
//
// Lecture seule. On parcourt le dossier des archives PDF, un ou plusieurs
// dossiers de fiches (Markdown) et, en option, le fichier d'inventaire, puis
// on rapproche par nom de fichier normalisé (minuscules, sans accents ni
// ponctuation). Une archive est « fichée » quand une fiche porte son nom ou
// le cite dans son texte. Rien n'est jamais écrit dans ces dossiers.

nonisolated struct ArchivePDF: Identifiable, Hashable {
    let id: String              // chemin relatif au dossier racine
    let url: URL
    let name: String            // nom sans extension
    let folder: String          // sous-dossier (fonds, farde…) ; "" à la racine
    let key: String             // nom normalisé
    let size: Int64
}

nonisolated struct ArchiveFiche: Identifiable, Hashable {
    let id: String              // chemin complet
    let url: URL
    let name: String            // nom sans extension
    let key: String
    let normalizedText: String  // contenu normalisé (tronqué)
}

nonisolated struct ArchiveMatch: Identifiable {
    let pdf: ArchivePDF
    let fiches: [ArchiveFiche]
    let inInventory: Bool
    var id: String { pdf.id }
    var isFiched: Bool { !fiches.isEmpty }
}

nonisolated struct ArchiveReport {
    let matches: [ArchiveMatch]
    /// Fiches qui ne correspondent à aucun PDF trouvé.
    let orphanFiches: [ArchiveFiche]
    /// Fiches dont le nom normalisé est identique (doublons possibles).
    let duplicateFiches: [[ArchiveFiche]]
    let inventoryLoaded: Bool
    let scannedAt: Date

    var fichedCount: Int { matches.filter(\.isFiched).count }
    var toDoCount: Int { matches.count - fichedCount }

    /// Avancement par sous-dossier, trié par nom.
    var byFolder: [(folder: String, fiched: Int, total: Int)] {
        Dictionary(grouping: matches, by: { $0.pdf.folder })
            .map { (folder: $0.key, fiched: $0.value.filter(\.isFiched).count, total: $0.value.count) }
            .sorted { $0.folder.localizedStandardCompare($1.folder) == .orderedAscending }
    }

    static let empty = ArchiveReport(matches: [], orphanFiches: [], duplicateFiches: [],
                                     inventoryLoaded: false, scannedAt: .distantPast)
}

nonisolated enum ArchiveIndex {

    /// Longueur minimale d'un nom pour chercher sa mention dans un texte
    /// (évite qu'un nom très court comme « 12 » corresponde partout).
    static let minimumKeyLengthForTextMatch = 6
    /// Taille maximale lue dans chaque fiche ou dans l'inventaire.
    static let maxTextBytes = 400_000

    /// Minuscules, sans accents, ponctuation et séparateurs remplacés par
    /// une espace, espaces multiples réduites.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                               locale: Locale(identifier: "fr_FR"))
        var out = ""
        var lastWasSpace = true
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Une fiche correspond-elle à ce PDF ?
    static func fiche(_ fiche: ArchiveFiche, matches pdf: ArchivePDF) -> Bool {
        guard !pdf.key.isEmpty else { return false }
        if fiche.key == pdf.key { return true }
        // Nom de la fiche qui contient le nom du PDF (« Fiche - AGR 12 ») :
        // seulement pour des noms assez longs, pour éviter les faux positifs.
        if pdf.key.count >= 4, " \(fiche.key) ".contains(" \(pdf.key) ") { return true }
        if pdf.key.count >= minimumKeyLengthForTextMatch,
           (" \(fiche.normalizedText) ").contains(" \(pdf.key) ") { return true }
        return false
    }

    static func buildReport(pdfs: [ArchivePDF], fiches: [ArchiveFiche], inventoryText: String?) -> ArchiveReport {
        let inventory = inventoryText.map { " \(normalize($0)) " }
        var usedFiches = Set<String>()
        let matches = pdfs.map { pdf -> ArchiveMatch in
            let found = fiches.filter { fiche($0, matches: pdf) }
            found.forEach { usedFiches.insert($0.id) }
            let listed = inventory.map { pdf.key.count >= 3 && $0.contains(" \(pdf.key) ") } ?? false
            return ArchiveMatch(pdf: pdf, fiches: found, inInventory: listed)
        }
        let orphans = fiches.filter { !usedFiches.contains($0.id) }
        let duplicates = Dictionary(grouping: fiches, by: \.key)
            .values
            .filter { $0.count > 1 && !$0[0].key.isEmpty }
            .map { $0.sorted { $0.url.path < $1.url.path } }
            .sorted { $0[0].key < $1[0].key }
        return ArchiveReport(matches: matches, orphanFiches: orphans, duplicateFiches: duplicates,
                             inventoryLoaded: inventoryText != nil, scannedAt: Date())
    }

    // MARK: Parcours des dossiers (hors thread principal)

    static func scanPDFs(root: URL) -> [ArchivePDF] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var result: [ArchivePDF] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "pdf" {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile ?? true else { continue }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) : url.lastPathComponent
            let folder = (relative as NSString).deletingLastPathComponent
            let name = url.deletingPathExtension().lastPathComponent
            result.append(ArchivePDF(id: relative, url: url, name: name, folder: folder,
                                     key: normalize(name), size: Int64(values?.fileSize ?? 0)))
        }
        return result.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    static func scanFiches(roots: [URL]) -> [ArchiveFiche] {
        let fm = FileManager.default
        var seen = Set<String>()
        var result: [ArchiveFiche] = []
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                 options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard ext == "md" || ext == "markdown" || ext == "txt" else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                // L'inventaire lui-même n'est pas une fiche.
                if normalize(name).hasPrefix("inventaire") { continue }
                result.append(ArchiveFiche(id: path, url: url, name: name, key: normalize(name),
                                           normalizedText: normalize(readText(url) ?? "")))
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func readText(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: maxTextBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// Rapport Markdown (copié dans le presse-papiers ou enregistré par l'utilisateur).
    static func markdown(_ report: ArchiveReport) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR")
        df.dateFormat = "d MMMM yyyy 'à' HH:mm"
        var lines: [String] = []
        lines.append("# État des fiches d'archives")
        lines.append("")
        lines.append("Généré par Writing Process le \(df.string(from: report.scannedAt)). Comptages faits par l'app, à partir des noms de fichiers.")
        lines.append("")
        lines.append("- PDF trouvés : \(report.matches.count)")
        lines.append("- Avec au moins une fiche : \(report.fichedCount)")
        lines.append("- Sans fiche : \(report.toDoCount)")
        lines.append("- Fiches sans PDF correspondant : \(report.orphanFiches.count)")
        lines.append("- Groupes de doublons possibles : \(report.duplicateFiches.count)")
        lines.append("")
        lines.append("## Par dossier")
        lines.append("")
        lines.append("| Dossier | Fichés | Total |")
        lines.append("|---|---:|---:|")
        for row in report.byFolder {
            lines.append("| \(row.folder.isEmpty ? "(racine)" : row.folder) | \(row.fiched) | \(row.total) |")
        }
        lines.append("")
        lines.append("## PDF sans fiche")
        lines.append("")
        for m in report.matches where !m.isFiched {
            lines.append("- \(m.pdf.id)\(m.inInventory ? " — dans l'inventaire" : "")")
        }
        if !report.duplicateFiches.isEmpty {
            lines.append("")
            lines.append("## Doublons possibles")
            lines.append("")
            for group in report.duplicateFiches {
                lines.append("- " + group.map { $0.url.path }.joined(separator: " · "))
            }
        }
        if !report.orphanFiches.isEmpty {
            lines.append("")
            lines.append("## Fiches sans PDF correspondant")
            lines.append("")
            for f in report.orphanFiches { lines.append("- \(f.url.path)") }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
