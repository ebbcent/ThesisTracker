import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Archives (section 6)
//
// « Cette archive est-elle déjà fichée ? » : croise le dossier des PDF
// d'archives, les dossiers de fiches et l'inventaire. Lecture seule.
// Les chemins sont propres à chaque Mac (UserDefaults, pas iCloud) :
// le disque externe n'a pas forcément le même chemin partout.

struct ArchivesView: View {
    @Binding var showSidebar: Bool

    @AppStorage("archives.pdfRoot") private var pdfRootPath: String = ""
    @AppStorage("archives.ficheRoots") private var ficheRootsJoined: String = ""
    @AppStorage("archives.inventoryFile") private var inventoryPath: String = ""

    @State private var report: ArchiveReport = .empty
    @State private var isScanning = false
    @State private var scanError: String?
    @State private var filter: Filter = .toDo
    @State private var query: String = ""

    enum Filter: String, CaseIterable, Identifiable {
        case toDo = "À ficher"
        case fiched = "Fichées"
        case all = "Toutes"
        case orphans = "Fiches sans PDF"
        case duplicates = "Doublons possibles"
        var id: String { rawValue }
    }

    private var ficheRoots: [String] {
        ficheRootsJoined.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if pdfRootPath.isEmpty || ficheRoots.isEmpty {
                setupPanel
            } else {
                content
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { if report.scannedAt == .distantPast { scan() } }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            if !showSidebar {
                Button { withAnimation { showSidebar = true } } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(.borderless)
                    .help("Afficher la barre latérale")
                    .accessibilityLabel("Afficher la barre latérale")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Archives").font(.title2.weight(.bold))
                Text("PDF d'archives, fiches et inventaire : ce qui est fiché, ce qui reste à faire.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if isScanning { ProgressView().controlSize(.small) }
            Button("Analyser") { scan() }
                .disabled(isScanning || pdfRootPath.isEmpty || ficheRoots.isEmpty)
                .keyboardShortcut("r", modifiers: .command)
                .help("Relire les dossiers (⌘R)")
            Menu {
                Button("Choisir le dossier des PDF…") { pickPDFRoot() }
                Button("Ajouter un dossier de fiches…") { addFicheRoot() }
                Button("Choisir le fichier d'inventaire…") { pickInventory() }
                Divider()
                Button("Copier le rapport (Markdown)") { copyReport() }
                    .disabled(report.matches.isEmpty)
                Button("Enregistrer le rapport…") { saveReport() }
                    .disabled(report.matches.isEmpty)
                Divider()
                Button("Réinitialiser les dossiers", role: .destructive) {
                    pdfRootPath = ""; ficheRootsJoined = ""; inventoryPath = ""; report = .empty
                }
            } label: {
                Image(systemName: "folder.badge.gearshape")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Dossiers et rapport")
            .accessibilityLabel("Dossiers et rapport")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: Premier réglage

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Indique une fois, sur ce Mac, où se trouvent tes fichiers. Rien n'est modifié : l'app ne fait que lire.")
                .foregroundStyle(.secondary)
            setupRow(title: "Dossier des archives PDF",
                     detail: pdfRootPath.isEmpty ? "Par exemple : SEAGATE › 04. Thèse › RECHERCHES › ARCHIVES › PDF" : pdfRootPath,
                     done: !pdfRootPath.isEmpty, action: pickPDFRoot, label: "Choisir…")
            setupRow(title: "Dossiers de fiches (un ou plusieurs)",
                     detail: ficheRoots.isEmpty ? "Par exemple : Bureau › NOTES › ARCHIVES, et Thèse › 02 Fiches d'archives" : ficheRoots.joined(separator: "\n"),
                     done: !ficheRoots.isEmpty, action: addFicheRoot, label: "Ajouter…")
            setupRow(title: "Inventaire (facultatif)",
                     detail: inventoryPath.isEmpty ? "_Inventaire des archives PDF.md" : inventoryPath,
                     done: !inventoryPath.isEmpty, action: pickInventory, label: "Choisir…")
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func setupRow(title: String, detail: String, done: Bool, action: @escaping () -> Void, label: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button(label, action: action)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
    }

    // MARK: Contenu

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            summary
            HStack(spacing: 12) {
                Picker("Filtre", selection: $filter) {
                    ForEach(Filter.allCases) { f in Text(f.rawValue).tag(f) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                TextField("Existe-t-il déjà une fiche pour… (nom, cote)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Rechercher une archive ou une fiche")
            }
            list
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var summary: some View {
        let total = report.matches.count
        let ratio = total > 0 ? Double(report.fichedCount) / Double(total) : 0
        return HStack(alignment: .top, spacing: 16) {
            stat("PDF trouvés", "\(total)")
            stat("Fichés", "\(report.fichedCount)", detail: total > 0 ? "\(Int((ratio * 100).rounded())) %" : nil)
            stat("À ficher", "\(report.toDoCount)")
            stat("Fiches sans PDF", "\(report.orphanFiches.count)")
            stat("Doublons possibles", "\(report.duplicateFiches.count)")
        }
    }

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.title2.weight(.bold)).monospacedDigit()
                if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var list: some View {
        let q = ArchiveIndex.normalize(query)
        switch filter {
        case .orphans:
            ficheList(report.orphanFiches.filter { q.isEmpty || $0.key.contains(q) || $0.normalizedText.contains(q) },
                      empty: "Aucune fiche sans PDF correspondant.")
        case .duplicates:
            List {
                ForEach(report.duplicateFiches, id: \.first!.id) { group in
                    Section(group[0].name) {
                        ForEach(group) { fiche in ficheRow(fiche) }
                    }
                }
            }
            .overlay { if report.duplicateFiches.isEmpty { emptyState("Aucun doublon de nom de fiche.") } }
        default:
            let rows = report.matches.filter { m in
                switch filter {
                case .toDo: return !m.isFiched
                case .fiched: return m.isFiched
                default: return true
                }
            }.filter { q.isEmpty || $0.pdf.key.contains(q) || ArchiveIndex.normalize($0.pdf.folder).contains(q)
                       || $0.fiches.contains { $0.key.contains(q) } }
            List(rows) { match in matchRow(match) }
                .overlay {
                    if rows.isEmpty {
                        emptyState(query.isEmpty ? "Rien dans cette catégorie." : "Aucune archive ni fiche ne correspond à « \(query) ».")
                    }
                }
        }
    }

    private func matchRow(_ match: ArchiveMatch) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: match.isFiched ? "checkmark.circle.fill" : "doc.text")
                .foregroundStyle(match.isFiched ? Color.green : Color.secondary)
                .accessibilityLabel(match.isFiched ? "Fichée" : "À ficher")
            VStack(alignment: .leading, spacing: 3) {
                Text(match.pdf.name).font(.body.weight(.medium)).textSelection(.enabled)
                HStack(spacing: 8) {
                    if !match.pdf.folder.isEmpty { Text(match.pdf.folder) }
                    Text(ByteCountFormatter.string(fromByteCount: match.pdf.size, countStyle: .file))
                    if report.inventoryLoaded {
                        Text(match.inInventory ? "dans l'inventaire" : "absent de l'inventaire")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                ForEach(match.fiches) { fiche in
                    Button("Fiche : \(fiche.name)") { NSWorkspace.shared.open(fiche.url) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            Spacer()
            Button("Ouvrir") { NSWorkspace.shared.open(match.pdf.url) }
                .help("Ouvrir le PDF")
            Button { NSWorkspace.shared.activateFileViewerSelecting([match.pdf.url]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Afficher dans le Finder")
            .accessibilityLabel("Afficher le PDF dans le Finder")
        }
        .padding(.vertical, 4)
    }

    private func ficheList(_ fiches: [ArchiveFiche], empty: String) -> some View {
        List(fiches) { fiche in ficheRow(fiche) }
            .overlay { if fiches.isEmpty { emptyState(empty) } }
    }

    private func ficheRow(_ fiche: ArchiveFiche) -> some View {
        HStack {
            Image(systemName: "note.text").foregroundStyle(.secondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(fiche.name).font(.body.weight(.medium)).textSelection(.enabled)
                Text(fiche.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Ouvrir") { NSWorkspace.shared.open(fiche.url) }
                .help("Ouvrir la fiche")
        }
        .padding(.vertical, 3)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).padding()
    }

    // MARK: Actions

    private func scan() {
        guard !pdfRootPath.isEmpty, !ficheRoots.isEmpty else { return }
        let pdfRoot = URL(fileURLWithPath: pdfRootPath)
        let roots = ficheRoots.map { URL(fileURLWithPath: $0) }
        let inventory = inventoryPath.isEmpty ? nil : URL(fileURLWithPath: inventoryPath)
        isScanning = true
        scanError = nil
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var problems: [String] = []
            if !fm.fileExists(atPath: pdfRoot.path) {
                problems.append("Dossier des PDF introuvable (disque externe débranché ?)")
            }
            for root in roots where !fm.fileExists(atPath: root.path) {
                problems.append("Dossier de fiches introuvable : \(root.lastPathComponent)")
            }
            let pdfs = ArchiveIndex.scanPDFs(root: pdfRoot)
            let fiches = ArchiveIndex.scanFiches(roots: roots)
            let inventoryText = inventory.flatMap { ArchiveIndex.readText($0) }
            if inventory != nil && inventoryText == nil { problems.append("Inventaire illisible") }
            let built = ArchiveIndex.buildReport(pdfs: pdfs, fiches: fiches, inventoryText: inventoryText)
            await MainActor.run {
                report = built
                scanError = problems.isEmpty ? nil : problems.joined(separator: " · ")
                isScanning = false
            }
        }
    }

    private func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func pickPDFRoot() {
        if let url = chooseFolder(prompt: "Choisir") { pdfRootPath = url.path; scan() }
    }

    private func addFicheRoot() {
        if let url = chooseFolder(prompt: "Ajouter"), !ficheRoots.contains(url.path) {
            ficheRootsJoined = (ficheRoots + [url.path]).joined(separator: "\n")
            scan()
        }
    }

    private func pickInventory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.prompt = "Choisir"
        if panel.runModal() == .OK, let url = panel.url { inventoryPath = url.path; scan() }
    }

    private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ArchiveIndex.markdown(report), forType: .string)
    }

    private func saveReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "État des fiches d'archives.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? ArchiveIndex.markdown(report).write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
