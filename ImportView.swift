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
            Color.appBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {

                // En-tête
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Importer des données")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
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
                    .buttonStyle(.plain)
                }

                // Zone de saisie
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("DONNÉES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.labelMuted)
                            .kerning(1.2)
                        Spacer()
                        Button("Choisir un fichier CSV…") { openFile() }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.accent)
                            .buttonStyle(.plain)
                        if !pastedText.isEmpty {
                            Button { pastedText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.labelMuted)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
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
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
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
                            .foregroundColor(.orange)
                        Text(error)
                            .foregroundColor(.orange)
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
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.plain)

                    Spacer()

                    Button { doImport() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: importDone ? "checkmark" : "square.and.arrow.down.fill")
                            Text(importDone
                                 ? "Importé !"
                                 : "Importer \(parsedEntries.count) entrée\(parsedEntries.count > 1 ? "s" : "")")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(canImport ? Color.accent : (importDone ? Color.accentGreen : Color.cardBorder))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: canImport ? Color.accent.opacity(0.30) : .clear, radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canImport)
                    .animation(.easeInOut(duration: 0.2), value: importDone)
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
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.accentGreen)
                .kerning(1.0)

            VStack(spacing: 0) {
                HStack {
                    Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Caractères (total)").frame(width: 140, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
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
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
            .background(Color.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
        }
    }

    // MARK: - Picker helper

    private func pickerBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(1.0)
            content()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cardBorder, lineWidth: 1))
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

            var date: String? = nil
            var count: Int? = nil

            for part in cleaned {
                let digits = part
                    .replacingOccurrences(of: "\u{202F}", with: "")
                    .replacingOccurrences(of: "\u{00A0}", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .replacingOccurrences(of: ".", with: "")

                if let n = Int(digits), n > 0, n < 10_000_000 {
                    if count == nil { count = n }
                } else if let d = parseDate(part) {
                    if date == nil { date = d }
                }
            }

            if let d = date, let c = count {
                results.append(ImportEntry(date: d, count: c))
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

    private func parseDate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        if let serial = Int(s), serial > 40000, serial < 55000 {
            let ref = Date(timeIntervalSince1970: -2209161600)
            let date = ref.addingTimeInterval(Double(serial - 1) * 86400)
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: date)
        }

        let outputFmt = DateFormatter()
        outputFmt.dateFormat = "yyyy-MM-dd"

        let formats = [
            ("fr_FR", "yyyy-MM-dd"),
            ("fr_FR", "dd/MM/yyyy"),
            ("fr_FR", "d/MM/yyyy"),
            ("fr_FR", "dd/M/yyyy"),
            ("fr_FR", "d/M/yyyy"),
            ("fr_FR", "dd.MM.yyyy"),
            ("fr_FR", "d.M.yyyy"),
            ("fr_FR", "dd-MM-yyyy"),
            ("fr_FR", "d MMM yyyy"),
            ("fr_FR", "dd MMM yyyy"),
            ("fr_FR", "d MMMM yyyy"),
            ("fr_FR", "dd MMMM yyyy"),
            ("fr_FR", "EEEE d MMMM yyyy"),
            ("en_US", "MM/dd/yyyy"),
            ("en_US", "M/d/yyyy"),
            ("en_US", "d MMM yyyy"),
            ("en_US", "MMM d, yyyy"),
        ]

        for (locale, format) in formats {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: locale)
            fmt.dateFormat = format
            if let date = fmt.date(from: s) {
                return outputFmt.string(from: date)
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
        withAnimation { importDone = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { dismiss() }
    }

    // MARK: - Helpers

    private func formattedDisplayDate(_ dateStr: String) -> String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let date = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "d MMM yyyy"
        return out.string(from: date)
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
