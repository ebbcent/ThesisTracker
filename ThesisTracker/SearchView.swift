import SwiftUI

enum SearchSortOrder: String, CaseIterable, Identifiable {
    case relevance  = "Pertinence"
    case dateDesc   = "Plus récent"
    case dateAsc    = "Plus ancien"
    case volumeDesc = "Volume ↓"
    var id: String { rawValue }
}

// #48 — Source des notes pour les résultats de recherche
enum NoteSource: String {
    case dailyNote   = "Note quotidienne"
    case generalNote = "Notes générales"
    case plan        = "Plan"
    case ideas       = "Idées"
    case blockers    = "Blocages"
    case nextStep    = "Prochaine étape"
    case chapterName = "Nom du chapitre"
    case projectNote = "Notes de projet"

    var icon: String {
        switch self {
        case .dailyNote:   return "note.text"
        case .generalNote: return "doc.text"
        case .plan:        return "list.bullet.rectangle"
        case .ideas:       return "lightbulb"
        case .blockers:    return "exclamationmark.triangle"
        case .nextStep:    return "arrow.right.circle"
        case .chapterName: return "book.closed.fill"
        case .projectNote: return "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .dailyNote:   return .accentWarm
        case .generalNote: return .accent
        case .plan:        return Color(red: 0.4, green: 0.7, blue: 1.0)
        case .ideas:       return Color(red: 1.0, green: 0.82, blue: 0.2)
        case .blockers:    return Color(red: 1.0, green: 0.45, blue: 0.35)
        case .nextStep:    return .accentGreen
        case .chapterName: return .accent
        case .projectNote: return Color(red: 0.706, green: 0.502, blue: 0.984)
        }
    }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let projectId: UUID?
    let project: String
    let chapterId: UUID?
    let chapter: String
    let date: String?
    let note: String?
    let snippet: String?       // #48 — highlighted context snippet
    let source: NoteSource
    let charCount: Int

    // Backwards compatibility
    var matchesChapter: Bool { source == .chapterName }
}

struct SearchView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var query: String = ""
    @State private var sortOrder: SearchSortOrder = .relevance
    @State private var selectedProjectId: UUID? = nil
    @State private var showSortMenu: Bool = false

    private var filteredResults: [SearchResult] {
        var results = allResults
        if let pid = selectedProjectId {
            results = results.filter { $0.projectId == pid }
        }
        switch sortOrder {
        case .relevance:
            // chapter name matches first, then chapter notes, then daily notes, then by date desc
            let priority: (NoteSource) -> Int = { s in
                switch s {
                case .chapterName: return 0
                case .generalNote: return 1
                case .plan, .ideas, .nextStep: return 2
                case .blockers:    return 3
                case .dailyNote:   return 4
                case .projectNote: return 5
                }
            }
            results.sort {
                let p0 = priority($0.source); let p1 = priority($1.source)
                if p0 != p1 { return p0 < p1 }
                return ($0.date ?? "") > ($1.date ?? "")
            }
        case .dateDesc:
            results.sort { ($0.date ?? "") > ($1.date ?? "") }
        case .dateAsc:
            results.sort { ($0.date ?? "") < ($1.date ?? "") }
        case .volumeDesc:
            results.sort { $0.charCount > $1.charCount }
        }
        return results
    }

    // MARK: - #48 Search engine

    private var allResults: [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        var results: [SearchResult] = []

        for project in store.data.projects {
            let latest = { (ch: Chapter) in ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0 }

            // --- Project-level note ---
            if let pnote = project.notes,
               pnote.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle) {
                results.append(SearchResult(
                    projectId: project.id, project: project.name,
                    chapterId: nil, chapter: project.name,
                    date: nil, note: pnote,
                    snippet: makeSnippet(pnote, needle: needle),
                    source: .projectNote, charCount: 0
                ))
            }

            for chapter in project.chapters {
                let chTotal = latest(chapter)

                // Chapter name match
                if chapter.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle) {
                    results.append(SearchResult(
                        projectId: project.id, project: project.name,
                        chapterId: chapter.id, chapter: chapter.name,
                        date: nil, note: nil, snippet: nil,
                        source: .chapterName, charCount: chTotal
                    ))
                }

                // Chapter-level note fields (#48)
                let chapterNoteFields: [(String?, NoteSource)] = [
                    (chapter.notes,         .generalNote),
                    (chapter.notesPlan,     .plan),
                    (chapter.notesIdeas,    .ideas),
                    (chapter.notesBlockers, .blockers),
                    (chapter.nextStep,      .nextStep),
                ]
                for (text, source) in chapterNoteFields {
                    guard let text,
                          text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                    else { continue }
                    results.append(SearchResult(
                        projectId: project.id, project: project.name,
                        chapterId: chapter.id, chapter: chapter.name,
                        date: nil, note: text,
                        snippet: makeSnippet(text, needle: needle),
                        source: source, charCount: chTotal
                    ))
                }

                // Daily entry notes
                for entry in chapter.entries {
                    guard let note = entry.note,
                          note.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                    else { continue }
                    let dayCount = chapter.increment(for: entry.date)
                    results.append(SearchResult(
                        projectId: project.id, project: project.name,
                        chapterId: chapter.id, chapter: chapter.name,
                        date: entry.date, note: note,
                        snippet: makeSnippet(note, needle: needle),
                        source: .dailyNote, charCount: dayCount
                    ))
                }
            }
        }
        return results
    }

    /// Extracts a ~120-char context window around the first occurrence of `needle`.
    private func makeSnippet(_ text: String, needle: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard let range = folded.range(of: needle) else { return String(text.prefix(120)) }
        let start = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let contextStart = max(0, start - 40)
        let idx = text.index(text.startIndex, offsetBy: contextStart, limitedBy: text.endIndex) ?? text.startIndex
        let slice = String(text[idx...].prefix(120))
        let prefix = contextStart > 0 ? "…" : ""
        let suffix = (contextStart + 120) < text.count ? "…" : ""
        return prefix + slice + suffix
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                headerView
                searchField
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filterBar
                }
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyPrompt
                } else if filteredResults.isEmpty {
                    noResults
                } else {
                    resultsList
                }
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Button {
                withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(showSidebar ? .accent : .labelMuted)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(showSidebar ? Color.accent.opacity(0.10) : Color.glassFill)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(
                                showSidebar ? Color.accent.opacity(0.30) : Color.cardBorder, lineWidth: 1))
                    )
            }
            .buttonStyle(.pressable)
            .help("Afficher ou masquer la barre latérale")
            .accessibilityLabel("Afficher ou masquer la barre latérale")

            VStack(alignment: .leading, spacing: 2) {
                Text("Recherche")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Chapitres, plan, idées, blocages et notes quotidiennes")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(filteredResults.count) résultat\(filteredResults.count != 1 ? "s" : "")")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        GlassCard {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.labelMuted)
                TextField("Chercher dans chapitres, plan, idées, blocages, notes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.labelMuted)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.pressable)
                    .help("Effacer la recherche")
                    .accessibilityLabel("Effacer la recherche")
                }
            }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Project filter chips
            if store.data.projects.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(id: nil, name: "Tous", icon: "globe")
                        ForEach(store.data.projects) { p in
                            filterChip(id: p.id, name: p.name, icon: "folder.fill")
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            // Sort selector
            HStack(spacing: 8) {
                Text("Trier par :")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(SearchSortOrder.allCases) { order in
                            Button {
                                withAppAnimation(.easeInOut(duration: 0.15)) { sortOrder = order }
                            } label: {
                                Text(order.rawValue)
                                    .font(.system(size: 11, weight: sortOrder == order ? .semibold : .regular))
                                    .lineLimit(1)
                                    .foregroundColor(sortOrder == order ? .white : .labelMuted)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(sortOrder == order ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(
                                        sortOrder == order ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
        }
    }

    private func filterChip(id: UUID?, name: String, icon: String) -> some View {
        let sel = selectedProjectId == id
        return Button { selectedProjectId = id } label: {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(name)
                    .font(.system(size: 11, weight: sel ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundColor(sel ? .white : .labelMuted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(sel ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(sel ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }

    // MARK: - Results list

    private var resultsList: some View {
        VStack(spacing: 8) {
            ForEach(filteredResults) { result in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        // Source indicator badge
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(result.source.color.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: result.source.icon)
                                .font(.system(size: 13))
                                .foregroundColor(result.source.color)
                        }
                        .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 5) {
                            // Project · Chapter + source badge
                            HStack(spacing: 6) {
                                HStack(spacing: 4) {
                                    Text(result.project)
                                        .font(.system(size: 12))
                                        .foregroundColor(.labelMuted)
                                    Text("·")
                                        .foregroundColor(.labelMuted)
                                        .font(.system(size: 12))
                                    Text(result.source == .projectNote ? result.project : result.chapter)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                // #48 — source label pill
                                if result.source != .chapterName && result.source != .projectNote {
                                    Text(result.source.rawValue)
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(result.source.color)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(result.source.color.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }

                            // Date
                            if let date = result.date, let parsed = DataStore.parseDate(date) {
                                Text(DataStore.formatDate(parsed))
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }

                            // Snippet (#48) or chapter match label
                            if let snippet = result.snippet {
                                Text(highlightedText(snippet, query: query))
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if result.source == .chapterName {
                                Text("Correspondance sur le nom du chapitre")
                                    .font(.system(size: 12))
                                    .foregroundColor(.labelMuted)
                                    .italic()
                            }
                        }

                        Spacer(minLength: 4)

                        // Char count
                        if result.charCount > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(store.formatCount(result.charCount))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.accent)
                                    .lineLimit(1)
                            }
                            .padding(.top, 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Returns an AttributedString with the search query highlighted in accent color.
    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            guard let range = attributed[searchStart...].range(
                of: needle,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) else { break }
            attributed[range].foregroundColor = Color.accent
            attributed[range].font = .system(size: 12, weight: .semibold)
            searchStart = range.upperBound
        }
        return attributed
    }

    // MARK: - Empty / no results

    private var emptyPrompt: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.labelMuted.opacity(0.5))
                Text("Recherche plein texte dans les noms de chapitres, plan, idées, blocages, prochaine étape et notes quotidiennes.")
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var noResults: some View {
        GlassCard {   // 5.15 : état vide commun
            EmptyStateView(icon: "doc.text.magnifyingglass", title: "Aucun résultat pour « \(query) »",
                           message: "Essaie un autre mot, ou une partie seulement du mot.")
        }
    }
}
