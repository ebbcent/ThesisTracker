import SwiftUI

enum SearchSortOrder: String, CaseIterable, Identifiable {
    case relevance  = "Pertinence"
    case dateDesc   = "Plus récent"
    case dateAsc    = "Plus ancien"
    case volumeDesc = "Volume ↓"
    var id: String { rawValue }
}

struct SearchResult: Identifiable {
    let id = UUID()
    let projectId: UUID?
    let project: String
    let chapter: String
    let date: String?
    let note: String?
    let matchesChapter: Bool
    let charCount: Int
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
            // chapter matches first, then by date desc
            results.sort {
                if $0.matchesChapter != $1.matchesChapter { return $0.matchesChapter }
                let d0 = $0.date ?? ""
                let d1 = $1.date ?? ""
                return d0 > d1
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

    private var allResults: [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let needle = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return store.data.projects.flatMap { project in
            project.chapters.flatMap { chapter -> [SearchResult] in
                let chapterMatches = chapter.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
                let latest = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
                let noteMatches: [SearchResult] = chapter.entries.compactMap { entry -> SearchResult? in
                    guard let note = entry.note,
                          note.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle) else { return nil }
                    let dayCount = chapter.increment(for: entry.date)
                    return SearchResult(projectId: project.id, project: project.name, chapter: chapter.name,
                                        date: entry.date, note: note, matchesChapter: false, charCount: dayCount)
                }
                var values = noteMatches
                if chapterMatches {
                    values.insert(SearchResult(projectId: project.id, project: project.name, chapter: chapter.name,
                                               date: nil, note: nil, matchesChapter: true, charCount: latest), at: 0)
                }
                return values
            }
        }
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
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { showSidebar.toggle() }
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
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recherche")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Projets, chapitres et notes")
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
                TextField("Chercher un projet, un chapitre ou une note…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.labelMuted)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
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
                                withAnimation(.easeInOut(duration: 0.15)) { sortOrder = order }
                            } label: {
                                Text(order.rawValue)
                                    .font(.system(size: 11, weight: sortOrder == order ? .semibold : .regular))
                                    .foregroundColor(sortOrder == order ? .white : .labelMuted)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(sortOrder == order ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(
                                        sortOrder == order ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
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
                Text(name).font(.system(size: 11, weight: sel ? .semibold : .regular))
            }
            .foregroundColor(sel ? .white : .labelMuted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(sel ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(sel ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Results list

    private var resultsList: some View {
        VStack(spacing: 8) {
            ForEach(filteredResults) { result in
                GlassCard {
                    HStack(alignment: .top, spacing: 12) {
                        // Type indicator
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(result.matchesChapter ? Color.accent.opacity(0.12) : Color.accentWarm.opacity(0.12))
                                .frame(width: 32, height: 32)
                            Image(systemName: result.matchesChapter ? "book.closed.fill" : "note.text")
                                .font(.system(size: 13))
                                .foregroundColor(result.matchesChapter ? .accent : .accentWarm)
                        }
                        .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 5) {
                            // Project · Chapter
                            HStack(spacing: 4) {
                                Text(result.project)
                                    .font(.system(size: 12))
                                    .foregroundColor(.labelMuted)
                                Text("·")
                                    .foregroundColor(.labelMuted)
                                    .font(.system(size: 12))
                                Text(result.chapter)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                            }

                            // Date
                            if let date = result.date, let parsed = DataStore.parseDate(date) {
                                Text(DataStore.formatDate(parsed))
                                    .font(.system(size: 11))
                                    .foregroundColor(.labelMuted)
                            }

                            // Note or chapter match label
                            if let note = result.note {
                                Text(note)
                                    .font(.system(size: 12))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else if result.matchesChapter {
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

    // MARK: - Empty / no results

    private var emptyPrompt: some View {
        GlassCard {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.labelMuted.opacity(0.5))
                Text("Commence une recherche pour retrouver rapidement un chapitre ou une note.")
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }

    private var noResults: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(.labelMuted.opacity(0.5))
                Text("Aucun résultat pour « \(query) »")
                    .foregroundColor(.labelMuted)
                    .font(.system(size: 13))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
    }
}
