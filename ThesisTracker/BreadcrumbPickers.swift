import SwiftUI

// MARK: - Pickers du breadcrumb (#5)

/// Popover qui liste les projets non archivés et permet d'en activer un.
struct BreadcrumbProjectPicker: View {
    @ObservedObject var store: DataStore
    let onSelect: () -> Void

    private var projects: [Project] {
        store.data.projects.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if projects.isEmpty {
                Text("Aucun projet")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(projects) { project in
                            projectRow(project)
                            if project.id != projects.last?.id {
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(minWidth: 260, maxWidth: 320)
    }

    private var header: some View {
        HStack {
            Text("Projets")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
            Spacer()
            Text("\(projects.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.labelMuted.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func projectRow(_ project: Project) -> some View {
        let isActive = store.data.activeProjectId == project.id
        return Button {
            if !isActive {
                store.data.activeProjectId = project.id
            }
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(project.tag?.color ?? Color.accentWarm)
                    .frame(width: 8, height: 8)
                Text(project.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if !project.chapters.isEmpty {
                    Text("\(project.chapters.count) ch.")
                        .font(.system(size: 9))
                        .foregroundColor(.labelMuted)
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accent.opacity(0.06) : Color.clear)
    }
}

/// Popover qui liste les chapitres du projet actif et permet d'en activer un.
struct BreadcrumbChapterPicker: View {
    @ObservedObject var store: DataStore
    let project: Project
    let onSelect: () -> Void

    private var chapters: [Chapter] { project.chapters }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if chapters.isEmpty {
                Text("Aucun chapitre")
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(chapters) { chapter in
                            chapterRow(chapter)
                            if chapter.id != chapters.last?.id {
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .frame(minWidth: 280, maxWidth: 360)
    }

    private var header: some View {
        HStack {
            Text("Chapitres · \(project.name)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.6)
                .lineLimit(1)
            Spacer()
            Text("\(chapters.count)")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.labelMuted.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let isActive = project.activeChapterId == chapter.id
        let dotColor: Color = chapter.isCompleted
            ? .accentGreen
            : (chapter.status.map { Color(hex: $0.color) } ?? .labelMuted)
        let goal = chapter.goal
        let latest = store.latestTotal(for: chapter.id, in: project.id)
        let pct: Int = goal > 0 ? Int(min(100, Double(latest) * 100.0 / Double(goal))) : 0

        return Button {
            if !isActive,
               let projIdx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                store.data.projects[projIdx].activeChapterId = chapter.id
            }
            onSelect()
        } label: {
            HStack(spacing: 8) {
                Circle().fill(dotColor).frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if goal > 0 {
                        Text("\(pct)% · v\(chapter.draftVersion)")
                            .font(.system(size: 9))
                            .foregroundColor(.labelMuted)
                    }
                }
                Spacer()
                if chapter.reviewState == .sent {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 9))
                        .foregroundColor(chapter.reviewState.color)
                } else if chapter.reviewState == .received {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 9))
                        .foregroundColor(chapter.reviewState.color)
                }
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accent)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isActive ? Color.accent.opacity(0.06) : Color.clear)
    }
}
