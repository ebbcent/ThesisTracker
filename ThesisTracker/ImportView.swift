import SwiftUI
import UniformTypeIdentifiers

struct ImportEntry: Identifiable {
    let id = UUID()
    let date: String   // yyyy-MM-dd
    let count: Int
}

struct ImportView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var pastedText: String = ""
    @State private var parsedEntries: [ImportEntry] = []
    @State private var targetProjectId: UUID? = nil
    @State private var targetChapterId: UUID? = nil
    @State private var parseError: String? = nil
    @State private var importDone = false

    private var targetProject: Project? {
        store.data.projects.first(where: { $0.id == effectiveProjectId })
    }
    private var effectiveProjectId: UUID? {
        targetProjectId ?? store.data.projects.first?.id
    }
    private var effectiveChapterId: UUID? {
        guard let proj = store.data.projects.first(where: { $0.id == effectiveProjectId }) else { return nil }
        return targetChapterId ?? proj.chapters.first?.id
    }
    private var canImport: Bool {
        !parsedEntries.isEmpty && effectiveProjectId != nil && effectiveChapterId != nil && !importDone
    }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {

                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Importer des données")
                            .font(.system(size: 20, weight: .bold, design: AppLook.fontDesign))
                            .foregroundColor(.primary)
                        Text("Collez depuis Excel ou choisissez un fichier CSV")
                            .font(.system(size: 12))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.labelMuted)
                            .padding(8)
                            .background(Color.cardBg)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }

                // Zone de saisie
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DONNÉES")
                            .font(.system(size: AppLook.fs(10), weight: .bold))
                            .foregroundColor(.labelMuted)
                            .kerning(1.2)
                        Spacer()
                        Button("Choisir un fichier CSV…") { openFile() }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accent)
                            .buttonStyle(.pressable)
                        if !pastedText.isEmpty {
                            Button { pastedText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.labelMuted)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.pressable)
                            .help("Effacer le texte collé")
                            .accessibilityLabel("Effacer le texte collé")
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if pastedText.isEmpty {
                            Text("Collez ici vos données Excel (⌘V)\n\nFormat attendu : une ligne par jour\n  • Date   Nombre de caractères\n  • 15/01/2024   12450\n  • 16/01/2024   13200")
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $pastedText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.primary)
                            .scrollContentBackground(.hidden)
                            .opacity(pastedText.isEmpty ? 0.01 : 1)
                    }
                    .frame(height: 130)
                    .background(Color.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                    .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
                    .onChange(of: pastedText) { _, _ in parseText() }
                }

                // Sélection projet + chapitre
                if !store.data.projects.isEmpty {
                    HStack(spacing: 12) {
                        pickerBlock(title: "PROJET") {
                            Picker("", selection: Binding(
                                get: { effectiveProjectId ?? UUID() },
                                set: { targetProjectId = $0; targetChapterId = nil }
                            )) {
                                ForEach(store.data.projects) { p in Text(p.name).tag(p.id) }
                            }
                            .labelsHidden()
                        }

                        if let project = targetProject, !project.chapters.isEmpty {
                            pickerBlock(title: "CHAPITRE") {
                                Picker("", selection: Binding(
                                    get: { effectiveChapterId ?? UUID() },
                                    set: { targetChapterId = $0 }
                                )) {
                                    ForEach(project.chapters) { ch in Text(ch.name).tag(ch.id) }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                }

                // Erreur ou aperçu
                if let error = parseError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.semOrange)
                        Text(error)
                            .foregroundColor(.semOrange)
                    }
                    .font(.system(size: 12))
                } else if !parsedEntries.isEmpty {
                    previewTable
                }

                Spacer()

                // Footer
                HStack {
                    Button("Annuler") { dismiss() }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.cardBg)
                        .clipShape(AppLook.buttonShape(10))
                        .overlay(AppLook.buttonShape(10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable)

                    Spacer()

                    Button { doImport() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: importDone ? "checkmark" : "square.and.arrow.down.fill")
                            Text(importDone
                                 ? "Importé !"
                                 : "Importer \(parsedEntries.count) entrée\(parsedEntries.count > 1 ? "s" : "")")
                            .lineLimit(1)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(canImport ? Color.accent : (importDone ? Color.accentGreen : Color.cardBorder))
                        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                        .shadow(color: canImport ? Color.accent.opacity(0.30) : .clear, radius: 6, x: 0, y: 3)
                        .contentShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
                    }
                    .buttonStyle(.pressable)
                    .disabled(!canImport)
                    .appAnimation(.easeInOut(duration: 0.2), value: importDone)
                }
            }
            .padding(28)
        }
        .frame(width: 560)
        .frame(minHeight: 540)
        .onAppear {
            targetProjectId = store.data.activeProjectId ?? store.data.projects.first?.id
            if let proj = store.data.projects.first(where: { $0.id == targetProjectId }) {
                targetChapterId = proj.activeChapterId ?? proj.chapters.first?.id
            }
        }
    }

    // MARK: - Aperçu

    private var previewTable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(parsedEntries.count) ENTRÉES DÉTECTÉES")
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.accentGreen)
                .kerning(1.0)

            VStack(spacing: 0) {
                HStack {
                    Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Caractères (total)").frame(width: 140, alignment: .trailing)
                }
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.labelMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(parsedEntries.prefix(10).enumerated()), id: \.element.id) { idx, entry in
                            HStack {
                                Text(formattedDisplayDate(entry.date))
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(formatNumber(entry.count))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.accent)
                                    .frame(width: 140, alignment: .trailing)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(idx % 2 == 0 ? Color.clear : Color.primary.opacity(0.02))
                        }
                        if parsedEntries.count > 10 {
                            Text("… et \(parsedEntries.count - 10) entrées de plus")
                                .font(.system(size: AppLook.fs(11)))
                                .foregroundColor(.labelMuted)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
            .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Picker helper

    private func pickerBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: AppLook.fs(10), weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.0)
            content()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.cardBg)
                .clipShape(AppLook.buttonShape(8))
                .overlay(AppLook.buttonShape(8).stroke(Color.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Ouverture de fichier

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText, .text]
        panel.allowsMultipleSelection = false
        panel.message = "Sélectionnez votre fichier CSV ou TXT exporté depuis Excel"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            pastedText = content
        } else if let content = try? String(contentsOf: url, encoding: .isoLatin1) {
            pastedText = content
        } else if let content = try? String(contentsOf: url, encoding: .windowsCP1252) {
            pastedText = content
        }
    }

    // MARK: - Parsing

    private func parseText() {
        parseError = nil
        parsedEntries = []
        let raw = pastedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }

        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [ImportEntry] = []

        for line in lines {
            let parts: [String]
            if line.contains("\t") {
                parts = line.components(separatedBy: "\t")
            } else if line.contains(";") {
                parts = line.components(separatedBy: ";")
            } else {
                parts = line.components(separatedBy: ",")
            }
            let cleaned = parts.map { $0.trimmingCharacters(in: .whitespaces) }
            if let entry = Self.parseRow(cleaned) {
                results.append(entry)
            }
        }

        if results.isEmpty {
            if lines.count > 0 {
                parseError = "Aucune donnée reconnue. Vérifiez que chaque ligne contient une date et un nombre."
            }
            return
        }

        var byDate: [String: Int] = [:]
        for entry in results { byDate[entry.date] = entry.count }
        parsedEntries = byDate.map { ImportEntry(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Analyse une ligne : 1) date explicite (texte) dans n'importe quelle cellule,
    /// 2) à défaut, numéro de série Excel — seulement si la cellule est un entier
    /// plausible (20000...80000) ET qu'une autre cellule numérique fournit le nombre,
    /// 3) le nombre = première cellule entière restante.
    static func parseRow(_ cells: [String]) -> ImportEntry? {
        var date: String? = nil
        var dateIndex: Int? = nil
        for (idx, cell) in cells.enumerated() {
            if let d = parseDate(cell) {
                date = d
                dateIndex = idx
                break
            }
        }

        // Cellules entières candidates (hors cellule date)
        var numbers: [(index: Int, value: Int)] = []
        for (idx, cell) in cells.enumerated() where idx != dateIndex {
            if let n = parseCount(cell) { numbers.append((index: idx, value: n)) }
        }

        if date == nil, numbers.count >= 2,
           let serialPos = numbers.firstIndex(where: { candidate in
               let trimmed = cells[candidate.index].trimmingCharacters(in: .whitespaces)
               return Int(trimmed) != nil && (20_000...80_000).contains(candidate.value)
           }),
           let d = excelSerialToDay(numbers[serialPos].value) {
            date = d
            numbers.remove(at: serialPos)
        }

        guard let d = date, let count = numbers.first?.value else { return nil }
        return ImportEntry(date: d, count: count)
    }

    /// Nombre de caractères : espaces, espaces insécables / fines et séparateurs
    /// de milliers (« . » ou « , » suivis de groupes de 3 chiffres) sont acceptés.
    private static func parseCount(_ raw: String) -> Int? {
        var s = raw
        for sep in [" ", "\u{00A0}", "\u{202F}", "\u{2009}", "\u{2007}"] {
            s = s.replacingOccurrences(of: sep, with: "")
        }
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }
        let groups = s.split(separator: ".", omittingEmptySubsequences: false)
            .flatMap { $0.split(separator: ",", omittingEmptySubsequences: false) }
        if groups.count > 1 {
            // Séparateurs de milliers uniquement : 1–3 chiffres puis groupes de 3
            guard let first = groups.first, (1...3).contains(first.count),
                  groups.dropFirst().allSatisfy({ $0.count == 3 }) else { return nil }
        }
        let digits = groups.joined()
        guard let n = Int(digits), n > 0, n < 10_000_000 else { return nil }
        return n
    }

    // MARK: Dates

    private static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.autoupdatingCurrent
        return c
    }()

    /// Numéro de série Excel (système 1900) → "yyyy-MM-dd".
    /// Base 1899-12-30 + serial jours (le jour fictif du 29/02/1900 est
    /// ainsi compensé pour toutes les dates postérieures au 01/03/1900).
    private static func excelSerialToDay(_ serial: Int) -> String? {
        guard let base = gregorian.date(from: DateComponents(year: 1899, month: 12, day: 30, hour: 12)),
              let date = gregorian.date(byAdding: .day, value: serial, to: base) else { return nil }
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Date numérique (séparateurs - / .) : ISO (yyyy-MM-dd, yyyy/MM/dd) ou
    /// ordre français jour/mois/année ; ordre américain mois/jour/année en
    /// dernier recours (si le premier nombre > 12). Validation stricte.
    private static func parseNumericDate(_ s: String) -> String? {
        let separators: Set<Character> = ["-", "/", "."]
        guard s.allSatisfy({ ($0.isASCII && $0.isNumber) || separators.contains($0) }) else { return nil }
        let sepsUsed = Set(s.filter { separators.contains($0) })
        guard sepsUsed.count == 1 else { return nil }
        let groups = s.split(whereSeparator: { separators.contains($0) }).map(String.init)
        guard groups.count == 3,
              let a = Int(groups[0]), let b = Int(groups[1]), let c = Int(groups[2]) else { return nil }

        let candidates: [(y: Int, m: Int, d: Int)]
        if groups[0].count == 4, groups[1].count <= 2, groups[2].count <= 2 {
            candidates = [(y: a, m: b, d: c)]                  // yyyy-MM-dd, yyyy/MM/dd
        } else if groups[2].count == 4, groups[0].count <= 2, groups[1].count <= 2 {
            candidates = [(y: c, m: b, d: a), (y: c, m: a, d: b)]         // dd/MM/yyyy puis MM/dd/yyyy
        } else {
            return nil
        }

        for cand in candidates {
            guard (1900...2200).contains(cand.y), (1...12).contains(cand.m), (1...31).contains(cand.d) else { continue }
            let comps = DateComponents(year: cand.y, month: cand.m, day: cand.d, hour: 12)
            guard let date = gregorian.date(from: comps) else { continue }
            let check = gregorian.dateComponents([.year, .month, .day], from: date)
            // Rejette les dates « corrigées » (ex. 31/02 → 03/03)
            guard check.year == cand.y, check.month == cand.m, check.day == cand.d else { continue }
            return String(format: "%04d-%02d-%02d", cand.y, cand.m, cand.d)
        }
        return nil
    }

    /// Formats textuels (mois en lettres), créés une seule fois.
    private static let textDateFormatters: [DateFormatter] = {
        let formats = [
            ("fr_FR", "d MMM yyyy"),
            ("fr_FR", "dd MMM yyyy"),
            ("fr_FR", "d MMMM yyyy"),
            ("fr_FR", "dd MMMM yyyy"),
            ("fr_FR", "EEEE d MMMM yyyy"),
            ("en_US_POSIX", "d MMM yyyy"),
            ("en_US_POSIX", "MMM d, yyyy"),
        ]
        return formats.map { locale, format in
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: locale)
            fmt.calendar = Calendar(identifier: .gregorian)
            fmt.timeZone = TimeZone.autoupdatingCurrent
            fmt.isLenient = false
            fmt.dateFormat = format
            return fmt
        }
    }()

    /// Date explicite (hors numéro de série Excel) → "yyyy-MM-dd".
    private static func parseDate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        if let numeric = parseNumericDate(s) { return numeric }

        // Formats textuels : il faut au moins une lettre
        guard s.contains(where: { $0.isLetter }) else { return nil }
        for fmt in textDateFormatters {
            if let date = fmt.date(from: s) {
                return AppFormatters.isoDay.string(from: date)
            }
        }
        return nil
    }

    // MARK: - Import

    private func doImport() {
        guard let projectId = effectiveProjectId,
              let chapterId = effectiveChapterId else { return }
        for entry in parsedEntries {
            store.setTotalForDate(entry.count, for: chapterId, in: projectId, date: entry.date)
        }
        withAppAnimation { importDone = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }

    // MARK: - Helpers

    private func formattedDisplayDate(_ dateStr: String) -> String {
        guard let date = AppFormatters.isoDay.date(from: dateStr) else { return dateStr }
        return AppFormatters.frDayMonthYear.string(from: date)
    }

    private func formatNumber(_ n: Int) -> String {
        AppFormatters.groupedInteger.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
