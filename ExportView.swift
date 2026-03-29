import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Format d'export

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv       = "CSV / Excel"
    case xlsx      = "Excel .xlsx"
    case pdfReport = "PDF Rapport"
    case pdfTable  = "PDF Tableau"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .csv:       return "tablecells"
        case .xlsx:      return "tablecells.badge.ellipsis"
        case .pdfReport: return "doc.richtext"
        case .pdfTable:  return "list.bullet.rectangle"
        }
    }
    var description: String {
        switch self {
        case .csv:
            return "Une ligne par jour et par chapitre, séparateur point-virgule. S'ouvre directement dans Excel (BOM UTF-8 inclus)."
        case .xlsx:
            return "Classeur Excel natif avec une feuille d'export complète."
        case .pdfReport:
            return "Rapport mise en page avec barre de progression par chapitre, statistiques et activité récente."
        case .pdfTable:
            return "Tableau simple de toutes les entrées, idéal pour archivage ou impression."
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
                            deadline: chapter.deadline
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
            Color.appBg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Exporter les données")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("\(totalEntries) entrées · \(store.data.projects.count) projet(s)")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18)).foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.plain)
                }

                // Format
                VStack(alignment: .leading, spacing: 8) {
                    Label("FORMAT", systemImage: "").font(.system(size: 10, weight: .bold))
                        .foregroundColor(.labelMuted).kerning(1.2)
                    HStack(spacing: 8) {
                        ForEach(ExportFormat.allCases) { f in
                            Button { format = f } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: f.icon).font(.system(size: 13))
                                    Text(f.rawValue)
                                        .font(.system(size: 12, weight: format == f ? .semibold : .regular))
                                }
                                .foregroundColor(format == f ? .white : .labelMuted)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(format == f ? Color.accent : Color.cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(format == f ? Color.accent : Color.cardBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
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
                        .buttonStyle(.plain).keyboardShortcut(.escape)
                    Spacer()
                    Button { doExport() } label: {
                        HStack(spacing: 8) {
                            if isExporting {
                                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                            }
                            Text("Exporter").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24).padding(.vertical, 10)
                        .background(isExporting ? Color.accent.opacity(0.5) : Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain).disabled(isExporting)
                    .keyboardShortcut(.return)
                }
            }
            .padding(28)
        }
        .frame(width: 520)
        .frame(minHeight: 440)
    }

    // MARK: - Chips

    private func scopeChip(id: UUID?, name: String, icon: String) -> some View {
        let isSelected = selectedProjectId == id
        return Button { selectedProjectId = id } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10))
                Text(name).font(.system(size: 12, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

    // MARK: - Dispatch

    private func doExport() {
        successMessage = nil
        errorMessage = nil
        isExporting = true
        switch format {
        case .csv:       exportCSV()
        case .xlsx:      exportXLSX()
        case .pdfReport: exportPDF(visual: true)
        case .pdfTable:  exportPDF(visual: false)
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
        var lines = ["Date;Projet;Chapitre;Total caractères;Caractères du jour"]
        for row in exportRows {
            let csvRow = [row.date, row.project, row.chapter, "\(row.total)", "\(row.increment)"]
                .map { $0.contains(";") ? "\"\($0)\"" : $0 }
                .joined(separator: ";")
            lines.append(csvRow)
        }
        return lines.joined(separator: "\r\n")
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
            if host.layer == nil {
                host.displayIgnoringOpacity(host.bounds, in: graphicsContext)
            }
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
                deadline: first.deadline
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // En-tête
            ZStack {
                Color(red: 0.059, green: 0.055, blue: 0.043)
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Writing Process")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Rapport de progression · \(generatedAt)")
                            .font(.system(size: 13)).foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(totalChapters) chapitres")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        Text("\(totalEntries) entrées")
                            .font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(40)
            }
            .frame(height: 120)

            VStack(alignment: .leading, spacing: 32) {
                // Stats globales
                HStack(spacing: 16) {
                    pdfStatBox(label: "Total caractères", value: fmt(totalChars), accent: Color(red: 0.961, green: 0.620, blue: 0.043))
                    pdfStatBox(label: "Jours d'écriture", value: "\(activeDays)", accent: Color(red: 0.929, green: 0.435, blue: 0.114))
                    pdfStatBox(label: "Meilleur jour", value: fmt(bestDay), accent: Color(red: 0.196, green: 0.784, blue: 0.549))
                    pdfStatBox(label: "Projets", value: "\(projectCount)", accent: Color(red: 0.706, green: 0.502, blue: 0.984))
                }

                // Projets et chapitres
                ForEach(projects, id: \.self) { project in
                    pdfProjectSection(project)
                }
            }
            .padding(40)

            Spacer(minLength: 40)
        }
        .background(Color(red: 0.97, green: 0.96, blue: 0.94))
    }

    private func pdfStatBox(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary).kerning(0.5)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.07), lineWidth: 1))
    }

    private func pdfProjectSection(_ project: String) -> some View {
        let chapters = chapterSummaries.filter { $0.project == project }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(project).font(.system(size: 16, weight: .bold)).foregroundColor(.primary)
                Spacer()
                Text("\(chapters.count) chapitres")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }

            ForEach(Array(chapters.enumerated()), id: \.element.id) { idx, chapter in
                pdfChapterRow(chapter, colorIdx: idx)
            }
        }
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.07), lineWidth: 1))
    }

    private func pdfChapterRow(_ chapter: ChapterSummary, colorIdx: Int) -> some View {
        let latest = chapter.total
        let goal = chapter.goal
        let ratio = goal > 0 ? min(1.0, Double(latest) / Double(chapter.goal)) : 0.0
        let isComplete = chapter.completed || ratio >= 1.0
        let color = isComplete
            ? Color(red: 0.196, green: 0.784, blue: 0.549)
            : Color.chapterColor(at: colorIdx)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let tag = chapter.tag { Circle().fill(tag.color).frame(width: 8, height: 8) }
                Text(chapter.chapter).font(.system(size: 13, weight: .medium)).foregroundColor(.primary)
                if chapter.completed {
                    Text("Terminé").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color(red: 0.196, green: 0.784, blue: 0.549))
                        .clipShape(Capsule())
                }
                Spacer()
                if goal > 0 {
                    Text("\(Int(ratio * 100))%")
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(color)
                    Text("·").foregroundColor(.secondary)
                }
                Text(fmt(latest) + " car.").font(.system(size: 12)).foregroundColor(.secondary)
            }

            if goal > 0 {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.15)).frame(height: 6)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3).fill(color)
                            .frame(width: geo.size.width * ratio, height: 6)
                    }
                    .frame(height: 6)
                }
                HStack {
                    Text(fmt(latest) + " / " + fmt(goal) + " caractères")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer()
                    Text("Objectif: " + fmt(goal)).font(.system(size: 10)).foregroundColor(.secondary)
                }
                if let deadline = chapter.deadline, let date = DataStore.parseDate(deadline) {
                    Text("Deadline: " + DataStore.formatDate(date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }

    // MARK: - Helpers

    private var totalChars: Int {
        rows.reduce(0) { $0 + $1.increment }
    }

    private var activeDays: Int {
        Set(rows.filter { $0.increment > 0 }.map(\.date)).count
    }

    private var bestDay: Int {
        var byDate = [String: Int]()
        for row in rows {
            byDate[row.date, default: 0] += row.increment
        }
        return byDate.values.max() ?? 0
    }

    private var totalChapters: Int { chapterSummaries.count }
    private var totalEntries: Int  { rows.count }

    private func fmt(_ n: Int) -> String {
        DataStore.formatNumber(n)
    }
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

            Spacer(minLength: 40)
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
}
