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
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)

        var items: [PaletteResult] = []

        // Navigation items
        for nav in NavItem.allCases {
            if q.isEmpty || nav.rawValue.lowercased().contains(q) {
                let navCopy = nav
                items.append(PaletteResult(
                    icon: nav.icon,
                    title: nav.rawValue,
                    subtitle: "Vue",
                    action: { onNavigate(navCopy); isPresented = false }
                ))
            }
        }

        // Projects
        for project in store.data.projects {
            if q.isEmpty || project.name.lowercased().contains(q) {
                let projCopy = project
                items.append(PaletteResult(
                    icon: "folder.fill",
                    title: project.name,
                    subtitle: "\(project.chapters.count) chapitre\(project.chapters.count > 1 ? "s" : "")",
                    action: { onSelectProject(projCopy); isPresented = false }
                ))
            }
        }

        // Chapters
        for project in store.data.projects {
            for chapter in project.chapters {
                if !q.isEmpty && (chapter.name.lowercased().contains(q) || project.name.lowercased().contains(q)) {
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
                        .buttonStyle(.plain)
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
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(i == selectedIndex ? Color.accent.opacity(0.10) : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(i)
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 320)
                        .onChange(of: selectedIndex) { _, idx in
                            withAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }

                    Divider()
                    HStack(spacing: 16) {
                        shortcutHint("↑↓", label: "Naviguer")
                        shortcutHint("↩", label: "Ouvrir")
                        shortcutHint("Esc", label: "Fermer")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }
            .frame(width: 520)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.cardBg)
                    .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
