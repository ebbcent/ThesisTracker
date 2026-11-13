import SwiftUI

// MARK: - Kanban status

enum KanbanStatus: String, CaseIterable, Identifiable {
    case todo       = "À faire"
    case inProgress = "En cours"
    case done       = "Terminé"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .todo:       return "circle"
        case .inProgress: return "circle.dotted"
        case .done:       return "checkmark.circle.fill"
        }
    }
    var color: Color {
        switch self {
        case .todo:       return .labelMuted
        case .inProgress: return .accent
        case .done:       return .accentGreen
        }
    }
}

// MARK: - Kanban View

struct KanbanView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    @State private var editingChapter: (project: Project, chapter: Chapter)? = nil
    @State private var dropTarget: KanbanStatus? = nil
    @State private var movingChapterId: UUID? = nil
    // #60 — Double-clic header pour créer un chapitre
    @State private var addingChapterForStatus: KanbanStatus? = nil

    private var allChapters: [(project: Project, chapter: Chapter)] {
        store.data.projects.flatMap { project in
            project.chapters.map { (project, $0) }
        }
    }

    private func chapters(for status: KanbanStatus) -> [(project: Project, chapter: Chapter)] {
        allChapters.filter { kanbanStatus(for: $0.chapter) == status }
    }

    private func kanbanStatus(for chapter: Chapter) -> KanbanStatus {
        if chapter.isCompleted { return .done }
        // "In progress" if it has any entries
        let hasEntries = chapter.entries.contains { $0.totalCount > 0 }
        return hasEntries ? .inProgress : .todo
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if !showSidebar {
                    Button { withAppAnimation { showSidebar = true } } label: {
                        Image(systemName: "sidebar.left").font(.system(size: 14)).foregroundColor(.labelMuted)
                    }
                    .buttonStyle(.pressable)
                    .help("Afficher la barre latérale")
                    .accessibilityLabel("Afficher la barre latérale")
                }
                Text("Kanban")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Spacer()
                Text("\(allChapters.count) chapitres")
                    .font(.system(size: 12)).foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 16)

            // Columns or empty state
            if allChapters.isEmpty {
                kanbanEmptyState
            } else {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(KanbanStatus.allCases) { status in
                        KanbanColumn(
                            status: status,
                            items: chapters(for: status),
                            store: store,
                            isDropTarget: dropTarget == status,
                            onEdit: { proj, chap in editingChapter = (proj, chap) },
                            onAddChapter: { addingChapterForStatus = status }
                        )
                        .dropDestination(for: String.self) { items, _ in
                            guard let idStr = items.first, let id = UUID(uuidString: idStr) else { return false }
                            applyDrop(chapterId: id, newStatus: status)
                            dropTarget = nil
                            return true
                        } isTargeted: { targeted in
                            withAppAnimation(.easeInOut(duration: 0.15)) { dropTarget = targeted ? status : nil }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 20)
            }
        }
        .background(Color.appBg)
        .sheet(item: Binding(
            get: { editingChapter.map { IdentifiableChapterEdit(project: $0.project, chapter: $0.chapter) } },
            set: { _ in editingChapter = nil }
        )) { item in
            ChapterFormView(store: store, chapter: item.chapter, projectId: item.project.id)
        }
        // #60 — Double-clic header → nouveau chapitre dans le projet actif
        .sheet(item: Binding(
            get: { addingChapterForStatus.map { KanbanNewChapterContext(status: $0) } },
            set: { _ in addingChapterForStatus = nil }
        )) { ctx in
            if let projectId = store.data.activeProjectId ?? store.data.projects.first?.id {
                ChapterFormView(store: store, chapter: nil, projectId: projectId)
            } else {
                VStack(spacing: 16) {
                    Text("Aucun projet actif")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Créez d'abord un projet depuis la barre latérale.")
                        .font(.system(size: 13))
                        .foregroundColor(.labelMuted)
                    Button("Fermer") { addingChapterForStatus = nil }.buttonStyle(.pressable)
                }
                .padding(40)
            }
        }
    }

    private var kanbanEmptyState: some View {
        VStack {   // 5.15 : état vide commun
            Spacer()
            EmptyStateView(icon: "rectangle.split.3x1", title: "Aucun chapitre à afficher",
                           message: "Ajoute des chapitres à tes projets depuis la barre latérale.", iconColor: .accent,
                           action: { withAppAnimation(Motion.quick) { showSidebar = true } }, actionLabel: "Ouvrir la barre latérale")
            Spacer()
        }
    }

    private func applyDrop(chapterId: UUID, newStatus: KanbanStatus) {
        guard let projIdx = store.data.projects.firstIndex(where: { $0.chapters.contains { $0.id == chapterId } }),
              let chapIdx = store.data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        switch newStatus {
        case .todo:
            // Clear entries? No — just unmark as completed
            store.data.projects[projIdx].chapters[chapIdx].isCompleted = false
        case .inProgress:
            store.data.projects[projIdx].chapters[chapIdx].isCompleted = false
        case .done:
            store.data.projects[projIdx].chapters[chapIdx].isCompleted = true
        }
        store.save()
    }
}

private struct IdentifiableChapterEdit: Identifiable {
    let id = UUID()
    let project: Project
    let chapter: Chapter
}

// #60
private struct KanbanNewChapterContext: Identifiable {
    let id = UUID()
    let status: KanbanStatus
}

// MARK: - Kanban Column

private struct KanbanColumn: View {
    let status: KanbanStatus
    let items: [(project: Project, chapter: Chapter)]
    @ObservedObject var store: DataStore
    let isDropTarget: Bool
    let onEdit: (Project, Chapter) -> Void
    var onAddChapter: (() -> Void)? = nil

    @State private var headerHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Column header — #60 double-clic pour créer un chapitre
            HStack(spacing: 7) {
                Image(systemName: status.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(status.color)
                Text(status.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.labelMuted)
                    .kerning(0.8)
                Spacer()
                // Quick-add button (visible on hover)
                if headerHovered {
                    Button {
                        onAddChapter?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(status.color)
                            .padding(4)
                            .background(Circle().fill(status.color.opacity(0.12)))
                    }
                    .buttonStyle(.pressable)
                    .help("Nouveau chapitre dans « \(status.rawValue) » (ou double-clic)")
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .accessibilityLabel("Nouveau chapitre dans « \(status.rawValue) » (ou double-clic)")
                }
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(status.color.opacity(0.8))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(status.color.opacity(0.12))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)
            .contentShape(Rectangle())
            .onHover { headerHovered = $0 }
            .onTapGesture(count: 2) { onAddChapter?() }
            .appAnimation(.easeInOut(duration: 0.15), value: headerHovered)

            // Cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(items, id: \.chapter.id) { pair in
                        KanbanCard(project: pair.project, chapter: pair.chapter, store: store, onEdit: onEdit)
                            .draggable(pair.chapter.id.uuidString)
                    }
                    if items.isEmpty {
                        Text("Déposer ici")
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDropTarget ? status.color.opacity(0.08) : Color.cardBg.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDropTarget ? status.color.opacity(0.35) : Color.cardBorder, lineWidth: isDropTarget ? 1.5 : 1)
        )
        .appAnimation(.easeInOut(duration: 0.15), value: isDropTarget)
    }
}

// MARK: - Kanban Card

private struct KanbanCard: View {
    let project: Project
    let chapter: Chapter
    @ObservedObject var store: DataStore
    let onEdit: (Project, Chapter) -> Void

    private var latest: Int { store.latestTotal(for: chapter.id, in: project.id) }
    private var ratio: Double {
        guard chapter.goal > 0 else { return 0 }
        return min(1.0, Double(latest) / Double(chapter.goal))
    }
    private var statusColor: Color { store.statusColor(for: chapter.id, in: project.id, goal: chapter.goal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let tag = chapter.tag {
                    Circle().fill(tag.color).frame(width: 7, height: 7)
                }
                Text(chapter.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
                Button { onEdit(project, chapter) } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10)).foregroundColor(.labelMuted)
                }
                .buttonStyle(.pressable)
                .help("Modifier le chapitre")
                .accessibilityLabel("Modifier le chapitre")
            }

            Text(project.name)
                .font(.system(size: 10)).foregroundColor(.labelMuted)

            if chapter.goal > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2).fill(statusColor.opacity(0.12)).frame(height: 3)
                            RoundedRectangle(cornerRadius: 2).fill(statusColor)
                                .frame(width: geo.size.width * ratio, height: 3)
                        }
                    }
                    .frame(height: 3)
                    HStack {
                        Text("\(store.formatCountShort(latest)) / \(store.formatCountShort(chapter.goal))")
                            .font(.system(size: 10)).foregroundColor(.labelMuted)
                        Spacer()
                        Text("\(Int(ratio * 100))%")
                            .font(.system(size: 10, weight: .medium)).foregroundColor(statusColor)
                    }
                }
            }

            if let deadline = chapter.deadline.flatMap(DataStore.parseDate) {
                let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: deadline).day ?? 0
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.system(size: 10))
                    Text(daysLeft >= 0 ? "\(daysLeft) j. restants" : "En retard")
                        .font(.system(size: 10))
                }
                .foregroundColor(daysLeft < 3 ? Color(red: 0.929, green: 0.329, blue: 0.329) : .labelMuted)
            }
        }
        .padding(10)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(chapter.isCompleted ? Color.accentGreen.opacity(0.25) : Color.cardBorder, lineWidth: 1)
        )
    }
}
