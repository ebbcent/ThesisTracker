import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Format d'export

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv        = "CSV / Excel"
    case xlsx       = "Excel .xlsx"
    case pdfReport  = "PDF Rapport"
    case pdfWeekly  = "PDF Hebdo"
    case pdfTable   = "PDF Tableau"
    case markdown   = "Markdown"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .csv:       return "tablecells"
        case .xlsx:      return "tablecells.badge.ellipsis"
        case .pdfReport: return "doc.richtext"
        case .pdfWeekly: return "calendar.badge.checkmark"
        case .pdfTable:  return "list.bullet.rectangle"
        case .markdown:  return "doc.plaintext"
        }
    }
    var description: String {
        switch self {
        case .csv:
            return "Une ligne par jour et par chapitre, séparateur point-virgule. Inclut la note du jour. S'ouvre directement dans Excel (BOM UTF-8 inclus)."
        case .xlsx:
            return "Classeur Excel natif avec une feuille d'export complète."
        case .pdfReport:
            return "Rapport mise en page avec barre de progression par chapitre, statistiques et activité récente."
        case .pdfWeekly:
            return "Rapport PDF de la semaine écoulée (lundi → dimanche) : total, meilleur jour, jours actifs, chapitres touchés."
        case .pdfTable:
            return "Tableau simple de toutes les entrées, idéal pour archivage ou impression."
        case .markdown:
            return "Rapport structuré en Markdown (titres, tableau par chapitre, stats) — à coller dans Obsidian, Notion, ou un mail."
        }
    }
}

// MARK: - Vue principale

struct ExportView: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var format: ExportFormat = .csv
    @State private var selectedProjectId: UUID? = nil
    @State private var isExporting = false
    @State private var successMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var showEmailCompose: Bool = false
    @State private var showPresentation: Bool = false

    private var projectsToExport: [Project] {
        if let id = selectedProjectId {
            return store.data.projects.filter { $0.id == id }
        }
        return store.data.projects
    }

    private var exportRows: [ExportRow] {
        projectsToExport.flatMap { project in
            project.chapters.flatMap { chapter in
                chapter.entries
                    .sorted { $0.date < $1.date }
                    .compactMap { entry in
                        let increment = chapter.increment(for: entry.date)
                        guard entry.totalCount > 0 || increment > 0 else { return nil }
                        return ExportRow(
                            date: entry.date,
                            project: project.name,
                            chapter: chapter.name,
                            total: entry.totalCount,
                            increment: increment,
                            note: entry.note,
                            chapterGoal: chapter.goal,
                            chapterCompleted: chapter.isCompleted,
                            chapterTag: chapter.tag,
                            deadline: chapter.deadline,
                            chapterStatus: chapter.status
                        )
                    }
            }
        }
        .sorted {
            if $0.date == $1.date {
                if $0.project == $1.project { return $0.chapter < $1.chapter }
                return $0.project < $1.project
            }
            return $0.date < $1.date
        }
    }

    var body: some View {
        ZStack {
            AppBackdrop().ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exporter les données")
                            .font(TypeScale.sheetTitle)
                            .foregroundColor(.primary)
                        Text("\(totalEntries) entrées · \(store.data.projects.count) projet(s)")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                    }
                    Spacer()

                    // #34 — Mode présentation
                    Button { showPresentation = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "play.rectangle.fill").font(.system(size: 12))
                            Text("Présentation")
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.cardBorder, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.pressable)

                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.pressable)
                    .help("Fermer")
                    .accessibilityLabel("Fermer")
                }
                .sheet(isPresented: $showPresentation) {
                    PresentationView(store: store, isPresented: $showPresentation)
                        .frame(minWidth: 960, minHeight: 640)
                }

                // Format
                VStack(alignment: .leading, spacing: 8) {
                    Label("FORMAT", systemImage: "").font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted).kerning(1.2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ExportFormat.allCases) { f in
                                Button { format = f } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: f.icon).font(.system(size: 13))
                                        Text(f.rawValue)
                                            .font(.system(size: 12, weight: format == f ? .semibold : .regular))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(format == f ? .white : .labelMuted)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .background(format == f ? Color.accent : Color.cardBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(format == f ? Color.accent : Color.cardBorder, lineWidth: 1))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                // Périmètre
                VStack(alignment: .leading, spacing: 8) {
                    Text("PÉRIMÈTRE")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.labelMuted).kerning(1.2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            scopeChip(id: nil, name: "Tous les projets", icon: "globe")
                            ForEach(store.data.projects) { p in
                                scopeChip(id: p.id, name: p.name, icon: "folder.fill")
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }

                // Description du format
                GlassCard {
                    HStack(spacing: 14) {
                        Image(systemName: format.icon)
                            .font(.system(size: 26)).foregroundColor(.accent)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(format.rawValue)
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
                            Text(format.description)
                                .font(.system(size: 12)).foregroundColor(.labelMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // Feedback
                if let msg = successMessage {
                    feedbackRow(msg, icon: "checkmark.circle.fill", color: .accentGreen)
                } else if let err = errorMessage {
                    feedbackRow(err, icon: "exclamationmark.triangle.fill", color: .accentWarm)
                }

                Spacer()

                // Boutons
                HStack(spacing: 12) {
                    Button("Annuler") { dismiss() }
                        .font(.system(size: 13, weight: .medium)).foregroundColor(.labelMuted)
                        .padding(.horizontal, 18).padding(.vertical, 10).background(Color.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
                        .buttonStyle(.pressable).keyboardShortcut(.escape)

                    // Bouton email directeur
                    Button { sendEmailToDirector() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "envelope").font(.system(size: 12))
                            Text("Envoyer par mail")
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.pressable)

                    Spacer()
                    Button { doExport() } label: {
                        HStack(spacing: 8) {
                            if isExporting {
                                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                            }
                            Text("Exporter")
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(isExporting ? Color.accent.opacity(0.5) : Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.pressable).disabled(isExporting)
                    .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 660)   // 5.36 : formats et périmètres moins coupés
        .frame(minHeight: 440)
    }

    // MARK: - Chips

    private func scopeChip(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = selectedProjectId == id
        return Button { selectedProjectId = id } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(name)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    private func feedbackRow(_ msg: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(msg).font(.system(size: 12)).foregroundColor(color)
        }
        .padding(12)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Totaux

    private var totalEntries: Int {
        store.data.projects.flatMap { $0.chapters }.flatMap { $0.entries }.count
    }

    // MARK: - Weekly PDF (#31)

    private func exportWeeklyPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        panel.nameFieldStringValue = "Writing_Process_\(dateTag)_semaine.pdf"
        panel.begin { response in
            isExporting = false
            guard response == .OK, let url = panel.url else { return }
            let weekRows = weeklyExportRows()
            let content = AnyView(PDFWeeklyReportContent(rows: weekRows))
            renderPDF(content: content, to: url)
        }
    }

    private func weeklyExportRows() -> [ExportRow] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        // Semaine précédente : lundi → dimanche
        let today = Date()
        guard let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start,
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let lastWeekEnd   = cal.date(byAdding: .day, value: 6, to: lastWeekStart) else { return [] }
        let startStr = DataStore.dateString(from: lastWeekStart)
        let endStr   = DataStore.dateString(from: lastWeekEnd)
        return exportRows.filter { $0.date >= startStr && $0.date <= endStr }
    }

    private func renderPDF(content: AnyView, to url: URL) {
        let host = NSHostingView(rootView: content)
        let width: CGFloat = 794
        host.setFrameOrigin(.zero)
        host.setFrameSize(NSSize(width: width, height: 10))
        host.layoutSubtreeIfNeeded()
        let fitH = max(host.fittingSize.height, 1123)
        host.setFrameSize(NSSize(width: width, height: fitH))
        host.layoutSubtreeIfNeeded()
        host.display()
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: width, height: fitH)
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            errorMessage = "Erreur : génération PDF impossible"
            return
        }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = graphicsContext
        host.layer?.render(in: context)
        if host.layer == nil { host.displayIgnoringOpacity(host.bounds, in: graphicsContext) }
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        do {
            try (pdfData as Data).write(to: url)
            successMessage = "✓ \(url.lastPathComponent) exporté"
        } catch {
            errorMessage = "Erreur : \(error.localizedDescription)"
        }
    }

    // MARK: - Markdown (#35)

    private func exportMarkdown() {
        isExporting = false
        let md = buildMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        successMessage = "✓ Rapport Markdown copié dans le presse-papier"
    }

    private func buildMarkdown() -> String {
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR"); fmt.dateStyle = .long
        let today = fmt.string(from: Date())

        // Global stats
        var byDate = [String: Int]()
        for row in exportRows { byDate[row.date, default: 0] += row.increment }
        let totalChars   = exportRows.reduce(0) { $0 + $1.increment }
        let activeDays   = byDate.values.filter { $0 > 0 }.count
        let bestDay      = byDate.values.max() ?? 0
        let streak       = store.currentStreak

        // Chapter summaries
        let grouped = Dictionary(grouping: exportRows, by: { "\($0.project)||\($0.chapter)" })
        let chapters: [(project: String, name: String, total: Int, goal: Int, pct: Int)] = grouped.values.compactMap { rows in
            guard let first = rows.first else { return nil }
            let latest = rows.max(by: { $0.date < $1.date })?.total ?? 0
            let pct = first.chapterGoal > 0 ? min(100, Int(Double(latest) / Double(first.chapterGoal) * 100)) : -1
            return (first.project, first.chapter, latest, first.chapterGoal, pct)
        }.sorted { $0.project == $1.project ? $0.name < $1.name : $0.project < $1.project }

        let projects = Array(Set(chapters.map(\.project))).sorted()

        var lines: [String] = []
        lines.append("# Rapport de progression — \(today)")
        lines.append("")
        lines.append("## Statistiques globales")
        lines.append("")
        lines.append("| Indicateur | Valeur |")
        lines.append("|:-----------|-------:|")
        lines.append("| Total écrit | \(DataStore.formatNumber(totalChars)) car. |")
        lines.append("| Jours d'écriture | \(activeDays) j |")
        lines.append("| Meilleur jour | \(DataStore.formatNumber(bestDay)) car. |")
        lines.append("| Série actuelle | \(streak) j |")
        lines.append("| Vitesse (14 j) | \(DataStore.formatNumber(store.velocity14Days)) car./j |")
        lines.append("")

        for project in projects {
            lines.append("## \(project)")
            lines.append("")
            lines.append("| Chapitre | Total | Objectif | % |")
            lines.append("|:---------|------:|---------:|--:|")
            for ch in chapters.filter({ $0.project == project }) {
                let goalStr = ch.goal > 0 ? "\(DataStore.formatNumber(ch.goal)) car." : "—"
                let pctStr  = ch.pct >= 0 ? "\(ch.pct)%" : "—"
                lines.append("| \(ch.name) | \(DataStore.formatNumber(ch.total)) car. | \(goalStr) | \(pctStr) |")
            }
            lines.append("")
        }

        // Upcoming milestones
        let upcomingMilestones = store.data.projects.flatMap { p in
            p.milestones.filter { !$0.isCompleted }.compactMap { m -> (String, String)? in
                guard let d = DataStore.parseDate(m.date) else { return nil }
                return (m.title, DataStore.formatDate(d))
            }
        }
        if !upcomingMilestones.isEmpty {
            lines.append("## Jalons à venir")
            lines.append("")
            for (title, date) in upcomingMilestones.prefix(5) {
                lines.append("- **\(title)** — \(date)")
            }
            lines.append("")
        }

        lines.append("---")
        lines.append("*Généré par ThesisTracker · \(today)*")
        return lines.joined(separator: "\n")
    }

    // MARK: - Email directeur (#32)

    private func sendEmailToDirector() {
        let fmt = DateFormatter(); fmt.locale = Locale(identifier: "fr_FR"); fmt.dateStyle = .long
        let today = fmt.string(from: Date())

        // Semaine (semaine courante)
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        let weekStr: String
        if let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
           let weekEnd = cal.date(byAdding: .day, value: 6, to: thisWeekStart) {
            let wFmt = DateFormatter(); wFmt.locale = Locale(identifier: "fr_FR"); wFmt.dateFormat = "d MMM"
            weekStr = "\(wFmt.string(from: thisWeekStart)) au \(wFmt.string(from: weekEnd))"
        } else {
            weekStr = today
        }

        let totalChars = exportRows.reduce(0) { $0 + $1.increment }
        let activeDays = Set(exportRows.filter { $0.increment > 0 }.map(\.date)).count

        // Progression globale
        let grouped = Dictionary(grouping: exportRows, by: { "\($0.project)||\($0.chapter)" })
        let chapLines: [String] = grouped.values.compactMap { rows in
            guard let first = rows.first else { return nil }
            let latest = rows.max(by: { $0.date < $1.date })?.total ?? 0
            if first.chapterGoal > 0 {
                let pct = min(100, Int(Double(latest) / Double(first.chapterGoal) * 100))
                return "  • \(first.chapter) (\(first.project)) : \(DataStore.formatNumber(latest)) / \(DataStore.formatNumber(first.chapterGoal)) car. (\(pct)%)"
            } else {
                return "  • \(first.chapter) (\(first.project)) : \(DataStore.formatNumber(latest)) car."
            }
        }.sorted()

        let milestones = store.data.projects.flatMap { p in
            p.milestones.filter { !$0.isCompleted }.compactMap { m -> String? in
                guard let d = DataStore.parseDate(m.date) else { return nil }
                return "  • \(m.title) — \(DataStore.formatDate(d))"
            }
        }

        let subject = "Rapport de progression — \(weekStr)"
        var body = """
Bonjour,

Voici mon rapport de progression pour la semaine du \(weekStr).

─ RÉSUMÉ ─────────────────────────────────
Total écrit    : \(DataStore.formatNumber(totalChars)) car.
Jours actifs   : \(activeDays) / 7
Série actuelle : \(store.currentStreak) jour(s)
Vitesse 14 j   : \(DataStore.formatNumber(store.velocity14Days)) car./j

─ CHAPITRES ──────────────────────────────
\(chapLines.joined(separator: "\n"))
"""
        if !milestones.isEmpty {
            body += """


─ JALONS À VENIR ─────────────────────────
\(milestones.prefix(5).joined(separator: "\n"))
"""
        }
        body += """


Cordialement,
"""

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let mailtoString   = "mailto:?subject=\(encodedSubject)&body=\(encodedBody)"
        if let url = URL(string: mailtoString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Dispatch

    private func doExport() {
        successMessage = nil
        errorMessage = nil
        isExporting = true
        switch format {
        case .csv:       exportCSV()
        case .xlsx:      exportXLSX()
        case .pdfReport: exportPDF(visual: true)
        case .pdfWeekly: exportWeeklyPDF()
        case .pdfTable:  exportPDF(visual: false)
        case .markdown:  exportMarkdown()
        }
    }

    // MARK: - CSV

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        panel.nameFieldStringValue = "Writing_Process_\(dateTag).csv"
        panel.begin { response in
            isExporting = false
            guard response == .OK, let url = panel.url else { return }
            var data = Data([0xEF, 0xBB, 0xBF])  // BOM UTF-8 pour Excel
            if let csv = buildCSV().data(using: .utf8) { data.append(csv) }
            do {
                try data.write(to: url)
                successMessage = "✓ \(url.lastPathComponent) exporté"
            } catch {
                errorMessage = "Erreur : \(error.localizedDescription)"
            }
        }
    }

    private func buildCSV() -> String {
        var lines = ["Date;Projet;Chapitre;Total caractères;Caractères du jour;Note"]
        for row in exportRows {
            let note = row.note ?? ""
            let textFields = [row.date, row.project, row.chapter].map { Self.csvTextField($0) }
            let numberFields = ["\(row.total)", "\(row.increment)"]   // colonnes numériques : pas de neutralisation
            let csvRow = (textFields + numberFields + [Self.csvTextField(note)])
                .map { field -> String in
                    // Scalaires (et non Character) : "\r\n" forme un seul Character
                    let needsQuote = field.unicodeScalars.contains {
                        $0 == ";" || $0 == "\"" || $0 == "\n" || $0 == "\r"
                    }
                    let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
                    return needsQuote ? "\"\(escaped)\"" : field
                }
                .joined(separator: ";")
            lines.append(csvRow)
        }
        return lines.joined(separator: "\r\n")
    }

    /// Neutralise l'injection de formules (CSV injection) : un champ texte
    /// commençant par =, +, -, @ (ou tabulation / retour chariot) est préfixé
    /// d'une apostrophe pour qu'Excel / Numbers l'affichent comme du texte.
    private static func csvTextField(_ field: String) -> String {
        guard let first = field.unicodeScalars.first else { return field }
        let dangerous: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
        return dangerous.contains(first) ? "'" + field : field
    }

    private func exportXLSX() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx") ?? .data]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        panel.nameFieldStringValue = "Writing_Process_\(dateTag).xlsx"
        panel.begin { response in
            isExporting = false
            guard response == .OK, let url = panel.url else { return }
            let data = XLSXWriter.workbookData(rows: exportRows)
            do {
                try data.write(to: url)
                successMessage = "✓ \(url.lastPathComponent) exporté"
            } catch {
                errorMessage = "Erreur : \(error.localizedDescription)"
            }
        }
    }

    // MARK: - PDF

    private func exportPDF(visual: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        let dateTag = DataStore.today.replacingOccurrences(of: "-", with: "")
        let suffix = visual ? "_rapport" : "_tableau"
        panel.nameFieldStringValue = "Writing_Process_\(dateTag)\(suffix).pdf"
        panel.begin { response in
            isExporting = false
            guard response == .OK, let url = panel.url else { return }
            let content: AnyView = visual
                ? AnyView(PDFReportContent(rows: exportRows, projectCount: projectsToExport.count))
                : AnyView(PDFTableContent(rows: exportRows))
            renderPDF(content: content, to: url)
        }
    }
}

struct ExportRow: Identifiable {
    let id = UUID()
    let date: String
    let project: String
    let chapter: String
    let total: Int
    let increment: Int
    let note: String?
    let chapterGoal: Int
    let chapterCompleted: Bool
    let chapterTag: ProjectTag?
    let deadline: String?
    let chapterStatus: ChapterStatus?
}

// MARK: - PDF Rapport visuel

struct PDFReportContent: View {
    let rows: [ExportRow]
    let projectCount: Int

    private var chapterSummaries: [ChapterSummary] {
        let grouped = Dictionary(grouping: rows, by: { "\($0.project)||\($0.chapter)" })
        return grouped.values.compactMap { rows in
            guard let first = rows.first else { return nil }
            let latest = rows.max(by: { $0.date < $1.date })?.total ?? 0
            return ChapterSummary(
                project: first.project,
                chapter: first.chapter,
                total: latest,
                goal: first.chapterGoal,
                completed: first.chapterCompleted,
                tag: first.chapterTag,
                deadline: first.deadline,
                status: first.chapterStatus
            )
        }
        .sorted {
            if $0.project == $1.project { return $0.chapter < $1.chapter }
            return $0.project < $1.project
        }
    }

    private var projects: [String] {
        Array(Set(rows.map(\.project))).sorted()
    }

    private var generatedAt: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateStyle = .long
        return f.string(from: Date())
    }

    // MARK: - Couleurs de charte

    private static let headerBg   = Color(red: 0.06,  green: 0.06,  blue: 0.10)
    private static let pageBg     = Color(red: 0.965, green: 0.960, blue: 0.952)
    private static let cardBg     = Color.white
    private static let accentGold = Color(red: 0.961, green: 0.620, blue: 0.043)
    private static let accentBlue = Color(red: 0.247, green: 0.502, blue: 0.965)
    private static let accentGreen = Color(red: 0.196, green: 0.784, blue: 0.549)
    private static let accentPurple = Color(red: 0.706, green: 0.502, blue: 0.984)
    private static let borderColor = Color.black.opacity(0.08)

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Couverture ──────────────────────────────────────────
            headerSection

            // ── Corps ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 28) {

                statsRow

                if globalGoalRatio > 0 { globalProgressSection }

                activitySection

                ForEach(projects, id: \.self) { pdfProjectSection($0) }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 48)

            footerSection
        }
        .background(Self.pageBg)
    }

    // MARK: - Header

    private var headerSection: some View {
        ZStack(alignment: .bottomLeading) {
            Self.headerBg

            // Bande accent en haut
            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(
                        colors: [Self.accentGold, Self.accentGold.opacity(0.6)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    // Surtitre
                    Text("RAPPORT DE PROGRESSION ACADÉMIQUE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Self.accentGold.opacity(0.8))
                        .kerning(2)

                    // Projets
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(projects.prefix(3), id: \.self) { project in
                            Text(project)
                                .font(.system(size: projects.count == 1 ? 26 : 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        if projects.count > 3 {
                            Text("+ \(projects.count - 3) autres…")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }

                    Text(generatedAt)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                }

                Spacer()

                // Méta-infos droite
                VStack(alignment: .trailing, spacing: 6) {
                    metaBadge(value: "\(totalChapters)", label: "chapitres")
                    metaBadge(value: "\(activeDays)", label: "jours d'écriture")
                    metaBadge(value: "\(projectCount)", label: "projet\(projectCount > 1 ? "s" : "")")
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 32)
            .padding(.bottom, 28)
        }
        .frame(minHeight: 160)
    }

    private func metaBadge(value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundColor(Self.accentGold)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statBox(
                icon: "text.cursor",
                label: "Total écrit",
                value: fmt(totalChars),
                sub: "caractères",
                accent: Self.accentGold)
            statBox(
                icon: "calendar",
                label: "Meilleur jour",
                value: fmt(bestDay),
                sub: "car.",
                accent: Self.accentBlue)
            statBox(
                icon: "checkmark.seal.fill",
                label: "Chapitres terminés",
                value: "\(completedChapters)",
                sub: "/ \(totalChapters)",
                accent: Self.accentGreen)
            statBox(
                icon: "chart.line.uptrend.xyaxis",
                label: "Moyenne 14 j",
                value: fmt(avg14),
                sub: "car. / jour",
                accent: Self.accentPurple)
        }
    }

    private func statBox(icon: String, label: String, value: String, sub: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(accent)
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.8)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            // Mini barre décorative
            Rectangle()
                .fill(accent.opacity(0.25))
                .frame(height: 3)
                .clipShape(Capsule())
                .overlay(
                    GeometryReader { geo in
                        Rectangle()
                            .fill(accent)
                            .frame(width: geo.size.width * 0.4)
                            .clipShape(Capsule())
                    },
                    alignment: .leading
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
    }

    // MARK: - Progression globale

    private var globalProgressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PROGRESSION GLOBALE")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ensemble des chapitres avec objectif")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(globalGoalRatio * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(globalGoalRatio >= 1 ? Self.accentGreen : Self.accentGold)
                    Text("— \(fmt(globalTotalWritten)) / \(fmt(globalTotalGoal)) car.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // Barre principale
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 10)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(
                                colors: globalGoalRatio >= 1
                                    ? [Self.accentGreen, Self.accentGreen.opacity(0.7)]
                                    : [Self.accentGold, Self.accentGold.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(1.0, globalGoalRatio)), height: 10)
                    }
                    .frame(height: 10)
                }
            }
            .padding(16)
            .background(Self.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
        }
    }

    // MARK: - Activité récente (30 jours)

    private var activitySection: some View {
        let days = last30Days
        let maxVal = days.values.max() ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACTIVITÉ — 30 DERNIERS JOURS")

            HStack(spacing: 0) {
                // Grille 30 colonnes
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(sortedLast30Keys, id: \.self) { dateStr in
                        let val = days[dateStr] ?? 0
                        let ratio = maxVal > 0 ? Double(val) / Double(maxVal) : 0
                        let barH = max(4.0, 36.0 * ratio)
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(val > 0
                                      ? Self.accentGold.opacity(0.4 + 0.6 * ratio)
                                      : Color.black.opacity(0.06))
                                .frame(height: CGFloat(barH))
                        }
                        .frame(maxWidth: .infinity, maxHeight: 36, alignment: .bottom)
                    }
                }
                .frame(height: 36)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Self.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
        }
    }

    // MARK: - Section projet

    private func pdfProjectSection(_ project: String) -> some View {
        let chapters = chapterSummaries.filter { $0.project == project }
        let projTotal = chapters.reduce(0) { $0 + $1.total }
        let projGoal  = chapters.reduce(0) { $0 + $1.goal }
        let projRatio = projGoal > 0 ? min(1.0, Double(projTotal) / Double(projGoal)) : 0

        return VStack(alignment: .leading, spacing: 0) {

            // En-tête projet
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Self.accentGold)
                Text(project)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                if projGoal > 0 {
                    Text("\(Int(projRatio * 100))%")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(projRatio >= 1 ? Self.accentGreen : .secondary)
                    Text("·").foregroundColor(.secondary.opacity(0.5))
                }
                Text("\(chapters.count) chapitre\(chapters.count > 1 ? "s" : "")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.025))

            // Divider
            Rectangle()
                .fill(Self.borderColor)
                .frame(height: 1)

            // Chapitres
            VStack(spacing: 0) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                    pdfChapterRow(chapter, colorIdx: idx)
                    if idx < chapters.count - 1 {
                        Rectangle().fill(Color.black.opacity(0.04)).frame(height: 1)
                            .padding(.leading, 18)
                    }
                }
            }
        }
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Self.borderColor, lineWidth: 1))
    }

    private func pdfChapterRow(_ chapter: ChapterSummary, colorIdx: Int) -> some View {
        let ratio     = chapter.goal > 0 ? min(1.0, Double(chapter.total) / Double(chapter.goal)) : 0.0
        let isComplete = chapter.completed || ratio >= 1.0
        let rowColor  = isComplete ? Self.accentGreen : Self.accentGold.opacity(0.8)
        let statusInfo = chapterStatusInfo(chapter)

        return HStack(spacing: 0) {
            // Barre couleur latérale
            Rectangle()
                .fill(isComplete ? Self.accentGreen : Color.chapterColor(at: colorIdx).opacity(0.7))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 7) {
                // Ligne 1 : nom + badges
                HStack(spacing: 6) {
                    if let tag = chapter.tag {
                        Circle().fill(tag.color).frame(width: 7, height: 7)
                    }
                    Text(chapter.chapter)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    // Badge statut
                    Text(statusInfo.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(statusInfo.color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(statusInfo.color.opacity(0.12))
                        .clipShape(Capsule())

                    Spacer()

                    // Deadline
                    if let dl = chapter.deadline, let d = DataStore.parseDate(dl) {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(DataStore.formatDate(d))
                                .font(.system(size: 10))
                        }
                        .foregroundColor(deadlineColor(dl))
                    }

                    // Pourcentage
                    if chapter.goal > 0 {
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(rowColor)
                    }
                }

                // Ligne 2 : barre + compteur
                if chapter.goal > 0 {
                    HStack(spacing: 8) {
                        // Barre de progression
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.black.opacity(0.06))
                                .frame(height: 5)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isComplete ? Self.accentGreen : Color.chapterColor(at: colorIdx))
                                    .frame(width: geo.size.width * CGFloat(ratio), height: 5)
                            }
                            .frame(height: 5)
                        }
                        .frame(maxWidth: .infinity)

                        Text(fmt(chapter.total) + " / " + fmt(chapter.goal))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .fixedSize()
                    }
                } else {
                    Text(fmt(chapter.total) + " car.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(LinearGradient(
                    colors: [Self.accentGold.opacity(0.6), Self.accentGold.opacity(0.15)],
                    startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rapport généré automatiquement")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("ThesisTracker")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.7))
                        Text("·  by Ebbcent")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.system(size: 10))
                        Text(generatedAt)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                // Mini logo textuel
                Text("TT")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundColor(Self.accentGold.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Self.accentGold.opacity(0.10)))
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.6))
        }
    }

    // MARK: - Helpers visuels

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.secondary)
            .kerning(1.5)
    }

    private struct StatusInfo { let label: String; let color: Color }

    private func chapterStatusInfo(_ chapter: ChapterSummary) -> StatusInfo {
        if chapter.completed { return StatusInfo(label: "Terminé", color: Self.accentGreen) }
        switch chapter.status {
        case .termine:    return StatusInfo(label: "Terminé",   color: Self.accentGreen)
        case .revision:   return StatusInfo(label: "Révision",  color: Self.accentBlue)
        case .redaction:  return StatusInfo(label: "Rédaction", color: Self.accentGold)
        case .plan:       return StatusInfo(label: "Plan",      color: Color.secondary)
        case nil:
            let ratio = chapter.goal > 0 ? Double(chapter.total) / Double(chapter.goal) : 0
            if ratio >= 1.0 { return StatusInfo(label: "Terminé",   color: Self.accentGreen) }
            if ratio >  0   { return StatusInfo(label: "En cours",  color: Self.accentGold) }
            return StatusInfo(label: "Non commencé", color: Color.secondary)
        }
    }

    private func deadlineColor(_ dateStr: String) -> Color {
        guard let d = DataStore.parseDate(dateStr) else { return .secondary }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: d).day ?? 0
        if days < 0  { return Color(red: 0.9, green: 0.2, blue: 0.2) }
        if days < 7  { return Color(red: 0.9, green: 0.4, blue: 0.1) }
        if days < 30 { return Self.accentGold }
        return .secondary
    }

    // MARK: - Calculs

    private var totalChars: Int      { rows.reduce(0) { $0 + $1.increment } }
    private var activeDays: Int      { Set(rows.filter { $0.increment > 0 }.map(\.date)).count }
    private var totalChapters: Int   { chapterSummaries.count }
    private var totalEntries: Int    { rows.count }
    private var completedChapters: Int { chapterSummaries.filter { $0.completed }.count }

    private var bestDay: Int {
        var byDate = [String: Int]()
        for row in rows { byDate[row.date, default: 0] += row.increment }
        return byDate.values.max() ?? 0
    }

    private var avg14: Int {
        let cal = Calendar.current
        let today = Date()
        var sum = 0; var count = 0
        for i in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dateStr = DataStore.dateString(from: d)
            let dayTotal = rows.filter { $0.date == dateStr }.reduce(0) { $0 + $1.increment }
            if dayTotal > 0 { sum += dayTotal; count += 1 }
        }
        return count > 0 ? sum / count : 0
    }

    private var globalTotalWritten: Int { chapterSummaries.reduce(0) { $0 + $1.total } }
    private var globalTotalGoal: Int    { chapterSummaries.reduce(0) { $0 + $1.goal } }
    private var globalGoalRatio: Double {
        globalTotalGoal > 0 ? min(1.0, Double(globalTotalWritten) / Double(globalTotalGoal)) : 0
    }

    private var last30Days: [String: Int] {
        var dict = [String: Int]()
        let cal = Calendar.current
        let today = Date()
        for i in 0..<30 {
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            let dateStr = DataStore.dateString(from: d)
            dict[dateStr] = rows.filter { $0.date == dateStr }.reduce(0) { $0 + $1.increment }
        }
        return dict
    }

    private var sortedLast30Keys: [String] {
        last30Days.keys.sorted()
    }

    private func fmt(_ n: Int) -> String { DataStore.formatNumber(n) }
}

// MARK: - PDF Tableau brut

struct PDFTableContent: View {
    let rows: [ExportRow]

    private var generatedAt: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateStyle = .long
        return f.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ZStack {
                Color(red: 0.059, green: 0.055, blue: 0.043)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Writing Process — Données brutes")
                            .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                        Text("Généré le \(generatedAt) · \(rows.count) entrées")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                }
                .padding(40)
            }
            .frame(height: 100)

            VStack(alignment: .leading, spacing: 0) {
                // En-tête tableau
                HStack(spacing: 0) {
                    tableCell("Date", weight: .bold, flex: 1.2)
                    tableCell("Projet", weight: .bold, flex: 1.5)
                    tableCell("Chapitre", weight: .bold, flex: 2)
                    tableCell("Total", weight: .bold, flex: 1, align: .trailing)
                    tableCell("Du jour", weight: .bold, flex: 1, align: .trailing)
                }
                .background(Color(red: 0.059, green: 0.055, blue: 0.043).opacity(0.08))

                // Lignes
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack(spacing: 0) {
                        tableCell(row.date, flex: 1.2)
                        tableCell(row.project, flex: 1.5)
                        tableCell(row.chapter, flex: 2)
                        tableCell(fmt(row.total), flex: 1, align: .trailing)
                        tableCell("+\(fmt(row.increment))", flex: 1, align: .trailing)
                    }
                    .background(idx % 2 == 0 ? Color.white : Color(red: 0.97, green: 0.96, blue: 0.94))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))
            .padding(40)

            // Footer
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.black.opacity(0.1))
                    .frame(height: 1)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Rapport généré automatiquement")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        HStack(spacing: 4) {
                            Text("ThesisTracker")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.primary.opacity(0.7))
                            Text("·  by Ebbcent  ·")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(generatedAt)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Text("TT")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundColor(Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.5))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color(red: 0.961, green: 0.620, blue: 0.043).opacity(0.10)))
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 16)
            }
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.94))
    }

    private func tableCell(_ text: String, weight: Font.Weight = .regular, flex: CGFloat = 1, align: HorizontalAlignment = .leading) -> some View {
        Text(text)
            .font(.system(size: 11, weight: weight))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: align == .trailing ? .trailing : .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minWidth: 60 * flex, maxWidth: 120 * flex)
    }

    private func fmt(_ n: Int) -> String {
        DataStore.formatNumber(n)
    }
}

struct ChapterSummary: Identifiable {
    let id = UUID()
    let project: String
    let chapter: String
    let total: Int
    let goal: Int
    let completed: Bool
    let tag: ProjectTag?
    let deadline: String?
    let status: ChapterStatus?
}

// MARK: - PDF Rapport Hebdomadaire (#31)

struct PDFWeeklyReportContent: View {
    let rows: [ExportRow]

    private static let headerBg    = Color(red: 0.06, green: 0.08, blue: 0.14)
    private static let pageBg      = Color(red: 0.965, green: 0.960, blue: 0.952)
    private static let cardBg      = Color.white
    private static let accent      = Color(red: 0.247, green: 0.502, blue: 0.965)
    private static let accentGreen = Color(red: 0.196, green: 0.784, blue: 0.549)
    private static let borderColor = Color.black.opacity(0.08)

    private var generatedAt: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateStyle = .long
        return f.string(from: Date())
    }

    private var weekLabel: String {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        guard let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start,
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let lastWeekEnd   = cal.date(byAdding: .day, value: 6, to: lastWeekStart) else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM"
        return "Semaine du \(f.string(from: lastWeekStart)) au \(f.string(from: lastWeekEnd))"
    }

    private var totalWritten: Int    { rows.reduce(0) { $0 + $1.increment } }
    private var activeDays: Int      { Set(rows.filter { $0.increment > 0 }.map(\.date)).count }
    private var bestDay: Int {
        var d = [String: Int]()
        for r in rows { d[r.date, default: 0] += r.increment }
        return d.values.max() ?? 0
    }
    private var chaptersWorked: Int  { Set(rows.map { "\($0.project)||\($0.chapter)" }).count }

    private var dailyBars: [(dateStr: String, value: Int)] {
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { offset -> (String, Int)? in
            guard let d = cal.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            let str = DataStore.dateString(from: d)
            let val = rows.filter { $0.date == str }.reduce(0) { $0 + $1.increment }
            return (str, val)
        }
    }

    private func dayLabel(_ dateStr: String) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "E"
        guard let d = DataStore.parseDate(dateStr) else { return "" }
        return f.string(from: d).prefix(1).uppercased() + f.string(from: d).dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            ZStack(alignment: .bottomLeading) {
                Self.headerBg
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(LinearGradient(colors: [Self.accent, Self.accent.opacity(0.4)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 4)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("RAPPORT HEBDOMADAIRE")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(Self.accent.opacity(0.8)).kerning(2)
                    Text(weekLabel)
                        .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Text("Généré le \(generatedAt)")
                        .font(.system(size: 12)).foregroundColor(.white.opacity(0.45))
                }
                .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 24)
            }
            .frame(minHeight: 130)

            // Stats
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    weekStatBox(label: "Total écrit", value: DataStore.formatNumber(totalWritten), sub: "car.", color: Self.accent)
                    weekStatBox(label: "Jours actifs", value: "\(activeDays)", sub: "/ 7", color: Self.accentGreen)
                    weekStatBox(label: "Meilleur jour", value: DataStore.formatNumber(bestDay), sub: "car.", color: Color(red: 0.961, green: 0.620, blue: 0.043))
                    weekStatBox(label: "Chapitres touchés", value: "\(chaptersWorked)", sub: "", color: Color(red: 0.706, green: 0.502, blue: 0.984))
                }

                // Barres journalières
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVITÉ JOURNALIÈRE").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary).kerning(1.5)
                    let bars = dailyBars
                    let maxVal = bars.map(\.value).max() ?? 1
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(bars, id: \.dateStr) { item in
                            let ratio = maxVal > 0 ? Double(item.value) / Double(maxVal) : 0
                            VStack(spacing: 4) {
                                Text(DataStore.formatNumber(item.value))
                                    .font(.system(size: 10)).foregroundColor(.secondary)
                                    .opacity(item.value > 0 ? 1 : 0)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.value > 0 ? Self.accent.opacity(0.4 + 0.6 * ratio) : Color.black.opacity(0.06))
                                    .frame(height: max(6, 60 * ratio))
                                Text(dayLabel(item.dateStr))
                                    .font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Self.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
                }

                // Chapitres travaillés
                if !rows.isEmpty {
                    let grouped = Dictionary(grouping: rows, by: { "\($0.project)||\($0.chapter)" })
                    let chaps = grouped.values.compactMap { r -> (String, String, Int)? in
                        guard let first = r.first else { return nil }
                        return (first.project, first.chapter, r.reduce(0) { $0 + $1.increment })
                    }.sorted { $0.2 > $1.2 }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("CHAPITRES").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary).kerning(1.5)
                        VStack(spacing: 0) {
                            ForEach(Array(chaps.enumerated()), id: \.offset) { idx, ch in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ch.1).font(.system(size: 12, weight: .semibold)).foregroundColor(.primary)
                                        Text(ch.0).font(.system(size: 10)).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("+\(DataStore.formatNumber(ch.2)) car.")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundColor(Self.accent)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 10)
                                if idx < chaps.count - 1 {
                                    Rectangle().fill(Self.borderColor).frame(height: 1).padding(.leading, 16)
                                }
                            }
                        }
                        .background(Self.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
        }
        .background(Self.pageBg)
    }

    private func weekStatBox(label: String, value: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).kerning(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.primary)
                if !sub.isEmpty {
                    Text(sub).font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            Rectangle().fill(color.opacity(0.25)).frame(height: 3).clipShape(Capsule())
                .overlay(GeometryReader { geo in
                    Rectangle().fill(color).frame(width: geo.size.width * 0.45).clipShape(Capsule())
                }, alignment: .leading)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.borderColor, lineWidth: 1))
    }
}
