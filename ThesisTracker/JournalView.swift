import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Journal de bord doctoral

struct JournalWidget: View {
    @ObservedObject var store: DataStore
    @State private var showSheet = false

    private var entries: [JournalEntry] { store.journalEntriesSorted() }
    private var todayEntry: JournalEntry? { entries.first { $0.date == DataStore.today } }

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.404, green: 0.224, blue: 0.718).opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.404, green: 0.224, blue: 0.718))
                    }
                    Text("Journal de bord")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(entries.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.labelMuted.opacity(0.1))
                        .clipShape(Capsule())
                }
                if let todayEntry {
                    Text(todayEntry.content)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(3)
                        .padding(8)
                        .background(Color(red: 0.404, green: 0.224, blue: 0.718).opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let last = entries.first {
                    Text("Dernière entrée — \(last.date.suffix(5))")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                    Text(last.content)
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .lineLimit(2)
                } else {
                    Text("Écris une note libre par jour — réflexion, blocage, idée méta. Pas pour produire, pour respirer.")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                }
                Button { showSheet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: todayEntry == nil ? "square.and.pencil" : "list.bullet")
                            .font(.system(size: 11))
                        Text(todayEntry == nil ? "Écrire aujourd'hui" : "Ouvrir le journal")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color(red: 0.404, green: 0.224, blue: 0.718))
                    .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .sheet(isPresented: $showSheet) {
            JournalSheet(store: store)
        }
    }
}

// MARK: - Sheet principale du journal

struct JournalSheet: View {
    @ObservedObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var newEntryText: String = ""
    @State private var editingId: UUID? = nil
    @State private var editingText: String = ""
    @State private var showCopyToast = false
    @State private var showSavePanel = false
    @State private var exportFeedback: ExportFeedback? = nil

    private enum ExportFeedback: Equatable {
        case success(String)
        case failure(String)
    }

    private var entries: [JournalEntry] { store.journalEntriesSorted(matching: query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            todayComposer
            Divider()
            searchBar
            if entries.isEmpty {
                emptyState
            } else {
                listView
            }
            if showCopyToast {
                copyToastBanner
            }
            if let feedback = exportFeedback {
                exportFeedbackBanner(feedback)
            }
        }
        .frame(width: 640, height: 640)
    }

    @ViewBuilder
    private func exportFeedbackBanner(_ feedback: ExportFeedback) -> some View {
        let (icon, color, text): (String, Color, String) = {
            switch feedback {
            case .success(let msg): return ("checkmark.circle.fill", .accentGreen, msg)
            case .failure(let msg): return ("exclamationmark.triangle.fill", .red, msg)
            }
        }()
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(color.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Journal de bord")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(store.data.journalEntries.count) entrée\(store.data.journalEntries.count > 1 ? "s" : "")")
                    .font(.system(size: 11)).foregroundColor(.labelMuted)
            }
            Spacer()
            Menu {
                Button("Exporter en Word (.docx)") { exportDOCX() }
                Button("Copier pour Apple Notes / Markdown") { copyForAppleNotes() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Exporter").font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.labelMuted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.glassFill)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.cardBorder, lineWidth: 1))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.labelMuted)
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private var todayComposer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUJOURD'HUI — \(DataStore.today)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.6)
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: $newEntryText)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 90)
                    .padding(6)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Button {
                    _ = store.addJournalEntry(content: newEntryText)
                    newEntryText = ""
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 18))
                        Text("Ajouter").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(red: 0.404, green: 0.224, blue: 0.718))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.pressable)
                .disabled(newEntryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted)
            TextField("Rechercher dans le journal…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(Color.appBg)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "book.closed" : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.labelMuted.opacity(0.55))
            Text(query.isEmpty ? "Pas encore d'entrée" : "Aucun résultat")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.labelMuted)
            Text(query.isEmpty
                 ? "Note tes blocages, déclics et idées du jour. Le champ du haut sauvegarde immédiatement."
                 : "Aucune entrée ne correspond à « \(query) ».")
                .font(.system(size: 11))
                .foregroundColor(.labelMuted.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
        .accessibilityElement(children: .combine)
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(entries) { entry in
                    entryRow(entry)
                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 18)
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(longDate(entry.date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.4)
                if let mood = entry.mood {
                    Text("· humeur \(mood)/5")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted.opacity(0.8))
                }
                Spacer()
                Button {
                    if editingId == entry.id { editingId = nil }
                    else { editingId = entry.id; editingText = entry.content }
                } label: {
                    Image(systemName: editingId == entry.id ? "checkmark.circle.fill" : "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(editingId == entry.id ? .accentGreen : .labelMuted.opacity(0.6))
                }
                .buttonStyle(.pressable)
                .help(editingId == entry.id ? "Terminer" : "Modifier")
                .accessibilityLabel(editingId == entry.id ? "Terminer" : "Modifier")
                Button {
                    store.deleteJournalEntry(entry.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted.opacity(0.6))
                }
                .buttonStyle(.pressable)
                .help("Supprimer")
                .accessibilityLabel("Supprimer")
            }
            if editingId == entry.id {
                TextEditor(text: $editingText)
                    .font(.system(size: 12))
                    .frame(minHeight: 80)
                    .padding(6)
                    .background(Color.fieldBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Button("Enregistrer") {
                    store.updateJournalEntry(entry.id, content: editingText)
                    editingId = nil
                }
                .buttonStyle(.pressable)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accent)
                .clipShape(Capsule())
            } else {
                Text(entry.content)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !entry.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(entry.tags.prefix(5), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.system(size: 10))
                            .foregroundColor(.labelMuted)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.labelMuted.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var copyToastBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.accentGreen)
            Text("Copié dans le presse-papier")
                .font(.system(size: 11, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.accentGreen.opacity(0.1))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Exports

    private func exportDOCX() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.nameFieldStringValue = "journal-de-bord-\(DataStore.today).docx"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let blocks = JournalExport.docxBlocks(entries: entries)
            let data = DOCXWriter.make(title: "Journal de bord", blocks: blocks)
            do {
                try data.write(to: url)
                withAppAnimation { exportFeedback = .success("Journal exporté : \(url.lastPathComponent)") }
            } catch {
                withAppAnimation { exportFeedback = .failure("Export impossible : \(error.localizedDescription)") }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAppAnimation { exportFeedback = nil }
            }
        }
    }

    private func copyForAppleNotes() {
        JournalExport.copyToPasteboard(entries: entries)
        withAppAnimation { showCopyToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAppAnimation { showCopyToast = false }
        }
    }

    // MARK: - Helpers

    private static let longFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM yyyy"
        return f
    }()
    private func longDate(_ str: String) -> String {
        guard let d = DataStore.parseDate(str) else { return str }
        let s = Self.longFmt.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
