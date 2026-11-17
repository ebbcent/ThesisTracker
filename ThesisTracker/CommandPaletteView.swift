import SwiftUI

// MARK: - Command Palette (Cmd+K)

struct CommandPaletteView: View {
    @ObservedObject var store: DataStore
    @Binding var isPresented: Bool
    let onNavigate: (NavItem) -> Void
    let onSelectProject: (Project) -> Void

    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var searchFocused: Bool

    // MARK: - Results

    private struct PaletteResult: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let action: () -> Void
    }

    private var results: [PaletteResult] {
        let q = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).trimmingCharacters(in: .whitespaces)   // 5.23 — sans accents ni casse

        var items: [PaletteResult] = []

        // Navigation items
        for nav in NavItem.allCases {
            if q.isEmpty || nav.rawValue.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) {
                let navCopy = nav
                items.append(PaletteResult(
                    icon: nav.icon,
                    title: nav.rawValue,
                    subtitle: "Vue",
                    action: { onNavigate(navCopy); isPresented = false }
                ))
            }
        }

        // Projects — en tête si query commence par ">" (mode projet)
        let isProjectMode = q.hasPrefix(">")
        let projectQuery = isProjectMode ? String(q.dropFirst()).trimmingCharacters(in: .whitespaces) : q
        for project in store.data.projects {
            let matches = projectQuery.isEmpty || project.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(projectQuery)
            if isProjectMode ? matches : (q.isEmpty || project.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)) {
                let projCopy = project
                let total = project.chapters.reduce(0) { acc, ch in
                    acc + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0)
                }
                let totalGoal = project.chapters.reduce(0) { $0 + $1.goal }
                let pct = totalGoal > 0 ? Int(min(100.0, Double(total) / Double(totalGoal) * 100)) : 0
                let countStr = store.formatCountShort(total)
                let subtitle = totalGoal > 0
                    ? "\(project.chapters.count) chapitre\(project.chapters.count > 1 ? "s" : "") · \(countStr) · \(pct)%"
                    : "\(project.chapters.count) chapitre\(project.chapters.count > 1 ? "s" : "") · \(countStr)"
                let isActive = store.data.activeProjectId == project.id
                let insertionIndex = isProjectMode ? items.startIndex : items.endIndex
                items.insert(PaletteResult(
                    icon: isActive ? "books.vertical.fill" : "folder.fill",
                    title: project.name,
                    subtitle: subtitle,
                    action: { onSelectProject(projCopy); isPresented = false }
                ), at: insertionIndex)
            }
        }

        // Chapters
        for project in store.data.projects {
            for chapter in project.chapters {
                if !q.isEmpty && (chapter.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q) || project.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(q)) {
                    let projCopy = project
                    let chapCopy = chapter
                    items.append(PaletteResult(
                        icon: "book.closed.fill",
                        title: chapter.name,
                        subtitle: "Chapitre · \(project.name)",
                        action: {
                            store.data.activeProjectId = projCopy.id
                            if let idx = store.data.projects.firstIndex(where: { $0.id == projCopy.id }) {
                                store.data.projects[idx].activeChapterId = chapCopy.id
                            }
                            store.save()
                            onNavigate(.dashboard)
                            isPresented = false
                        }
                    ))
                }
            }
        }

        return Array(items.prefix(10))
    }

    var body: some View {
        ZStack {
            // Fond assombri
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Barre de recherche
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.labelMuted)
                    TextField("Rechercher une vue, un projet, un chapitre…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .focused($searchFocused)
                        .onSubmit { activateSelected() }
                        .onChange(of: query) { selectedIndex = 0 }
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.labelMuted)
                        }
                        .buttonStyle(.pressable)
                        .help("Effacer la recherche")
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if !results.isEmpty {
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 2) {
                                ForEach(results.indices, id: \.self) { i in
                                    let result = results[i]
                                    Button(action: result.action) {
                                        HStack(spacing: 12) {
                                            ZStack {
                                                RoundedRectangle(cornerRadius: AppLook.r(7, 10), style: .continuous)
                                                    .fill(Color.accent.opacity(0.12))
                                                    .frame(width: 28, height: 28)
                                                Image(systemName: result.icon)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(.accent)
                                            }
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(result.title)
                                                    .font(.system(size: 13, weight: .medium))
                                                    .foregroundColor(.primary)
                                                Text(result.subtitle)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.labelMuted)
                                            }
                                            Spacer()
                                            if i == selectedIndex {
                                                Image(systemName: "return")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.labelMuted)
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                                                .fill(i == selectedIndex ? Color.accent.opacity(0.10) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.pressable)
                                    .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: selectedIndex) { _, idx in
                            withAppAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }

                    Divider()
                    HStack(spacing: 16) {
                        shortcutHint("↑↓", label: "Naviguer")
                        shortcutHint("↩", label: "Ouvrir")
                        shortcutHint(">", label: "Projets")
                        shortcutHint("Esc", label: "Fermer")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 520)
            .appGlass(in: RoundedRectangle(cornerRadius: AppLook.r(16, 22), style: .continuous), legible: true)   // 5.16 : verre standard (lisibilité)
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: AppLook.r(16, 22), style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
            .offset(y: -80)
        }
        .onAppear {
            searchFocused = true
            selectedIndex = 0
        }
        .onKeyPress(.upArrow)   { selectedIndex = max(0, selectedIndex - 1); return .handled }
        .onKeyPress(.downArrow) { selectedIndex = min(results.count - 1, selectedIndex + 1); return .handled }
        .onKeyPress(.escape)    { isPresented = false; return .handled }
        .onKeyPress(.return)    { activateSelected(); return .handled }
    }

    private func activateSelected() {
        guard selectedIndex < results.count else { return }
        results[selectedIndex].action()
    }

    private func shortcutHint(_ key: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.labelMuted)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.fieldBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.labelMuted)
        }
    }
}
