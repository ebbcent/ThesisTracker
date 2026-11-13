import SwiftUI

// MARK: - Feature #37 : Vue "Table des matières"

struct TableOfContentsView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool
    @State private var expandedProjects: Set<UUID> = []
    @State private var showExportSheet: Bool = false
    @State private var exportText: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // En-tête
                HStack(spacing: 12) {
                    Button {
                        withAppAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showSidebar ? .accentWarm : .labelMuted)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(showSidebar ? Color.accentWarm.opacity(0.09) : Color.glassFill)
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(showSidebar ? Color.accentWarm.opacity(0.25) : Color.cardBorder, lineWidth: 1))
                            )
                    }
                    .buttonStyle(.pressable)
                    .help("Afficher ou masquer la barre latérale")
                    .accessibilityLabel("Afficher ou masquer la barre latérale")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Table des matières")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Arborescence complète de vos projets et chapitres")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Button {
                        exportText = generateExportText()
                        showExportSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 10, weight: .medium))
                            Text("Exporter").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accent.opacity(0.2), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }

                let activeProjects = store.data.projects.filter { !$0.isArchived }
                if activeProjects.isEmpty {
                    GlassCard {
                        EmptyStateView(icon: "list.bullet.rectangle", title: "Aucun projet actif",
                                       message: "Créez un projet et des chapitres pour voir la table des matières.")
                    }
                } else {
                    VStack(spacing: 12) {
                        ForEach(activeProjects) { project in
                            projectCard(project)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(AppBackdrop())
        .sheet(isPresented: $showExportSheet) {
            ExportTextSheet(text: exportText)
        }
        .onAppear {
            expandedProjects = Set(store.data.projects.filter { !$0.isArchived }.map(\.id))
        }
    }

    private func projectCard(_ project: Project) -> some View {
        let totalGoal    = project.chapters.reduce(0) { $0 + $1.goal }
        let totalWritten = project.chapters.compactMap { $0.entries.max(by: { $0.date < $1.date })?.totalCount }.reduce(0, +)
        let completedCount = project.chapters.filter(\.isCompleted).count
        let ratio = totalGoal > 0 ? min(1.0, Double(totalWritten) / Double(totalGoal)) : 0
        let isExpanded = expandedProjects.contains(project.id)

        return GlassCard {
            VStack(spacing: 0) {
                // Projet header
                Button {
                    withAppAnimation(.easeOut(duration: 0.15)) {
                        if isExpanded { expandedProjects.remove(project.id) }
                        else { expandedProjects.insert(project.id) }
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.accent.opacity(0.12)).frame(width: 26, height: 26)
                            Image(systemName: "folder.fill").font(.system(size: 11)).foregroundColor(.accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("\(project.chapters.count) chapitre\(project.chapters.count != 1 ? "s" : "") · \(completedCount) terminé\(completedCount != 1 ? "s" : "")")
                                .font(.system(size: 10)).foregroundColor(.labelMuted)
                        }
                        Spacer()
                        if totalGoal > 0 {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(Int(ratio * 100))%")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(.accent)
                                Text("\(DataStore.formatNumber(totalWritten)) car.")
                                    .font(.system(size: 10)).foregroundColor(.labelMuted)
                            }
                        }
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium)).foregroundColor(.labelMuted)
                    }
                }
                .buttonStyle(.pressable)

                if isExpanded && !project.chapters.isEmpty {
                    Divider().padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(project.chapters) { chapter in
                            chapterRow(chapter, project: project)
                            if chapter.id != project.chapters.last?.id {
                                Divider().padding(.leading, 32)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func chapterRow(_ chapter: Chapter, project: Project) -> some View {
        let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
        let pct = chapter.goal > 0 ? min(100, Int(Double(latest) / Double(chapter.goal) * 100)) : 0
        let isActive = project.activeChapterId == chapter.id

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: chapter.isCompleted ? "checkmark.circle.fill" : "doc.text")
                    .font(.system(size: 11))
                    .foregroundColor(chapter.isCompleted ? .accentGreen : .labelMuted)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(chapter.name)
                            .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                            .foregroundColor(.primary)
                        if isActive {
                            Text("actif")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.accent)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        if chapter.priority == .high {
                            Image(systemName: "exclamationmark").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "#DC2626"))
                        }
                        ForEach(chapter.customTags.prefix(2), id: \.self) { tag in
                            Text(tag).font(.system(size: 10)).foregroundColor(.accent)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Color.accent.opacity(0.08)).clipShape(Capsule())
                        }
                    }
                    if let st = chapter.status, !chapter.isCompleted {
                        Text(st.label).font(.system(size: 10)).foregroundColor(Color(hex: st.color))
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    if chapter.goal > 0 {
                        Text("\(DataStore.formatNumber(latest)) / \(DataStore.formatNumber(chapter.goal))")
                            .font(.system(size: 10)).foregroundColor(.labelMuted)
                        Text("\(pct)%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(chapter.isCompleted ? .accentGreen : .accent)
                    } else if latest > 0 {
                        Text(DataStore.formatNumber(latest))
                            .font(.system(size: 10)).foregroundColor(.labelMuted)
                    }
                    if let dl = chapter.deadline, !dl.isEmpty {
                        Image(systemName: "calendar").font(.system(size: 10)).foregroundColor(.accentWarm)
                    }
                }
            }
            .padding(.vertical, 6).padding(.leading, 4)

            // Sous-chapitres (#34)
            if !chapter.subchapters.isEmpty {
                VStack(spacing: 0) {
                    ForEach(chapter.subchapters) { sub in
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 10)).foregroundColor(.labelMuted).frame(width: 20)
                            Text(sub.name).font(.system(size: 11)).foregroundColor(.secondary)
                            Spacer()
                            let subLatest = sub.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                            if sub.goal > 0 {
                                Text("\(Int(min(100, Double(subLatest)/Double(sub.goal)*100)))%")
                                    .font(.system(size: 10)).foregroundColor(.labelMuted)
                            }
                        }
                        .padding(.vertical, 3).padding(.leading, 28)
                    }
                }
            }
        }
    }

    private func generateExportText() -> String {
        var lines: [String] = ["# Table des matières", ""]
        for proj in store.data.projects where !proj.isArchived {
            let total = proj.chapters.compactMap { $0.entries.max(by: { $0.date < $1.date })?.totalCount }.reduce(0, +)
            lines.append("## \(proj.name)  [\(DataStore.formatNumber(total)) car.]")
            lines.append("")
            for (i, ch) in proj.chapters.enumerated() {
                let latest = ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                let pct = ch.goal > 0 ? "\(Int(min(100, Double(latest)/Double(ch.goal)*100)))%" : ""
                let check = ch.isCompleted ? "✓" : " "
                lines.append("  \(i+1). [\(check)] \(ch.name)  \(pct)  (\(DataStore.formatNumber(latest))\(ch.goal > 0 ? " / \(DataStore.formatNumber(ch.goal))" : "") car.)")
                for sub in ch.subchapters {
                    let subLatest = sub.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                    lines.append("       — \(sub.name)  (\(DataStore.formatNumber(subLatest)) car.)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Export text sheet

private struct ExportTextSheet: View {
    let text: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Table des matières")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    let pb = NSPasteboard.general; pb.clearContents(); pb.setString(text, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc").font(.system(size: 10))
                        Text("Copier").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.pressable)
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundColor(.labelMuted)
                        .padding(8).background(Color.cardBg).clipShape(Circle())
                }.buttonStyle(.pressable)
                .help("Fermer")
                .accessibilityLabel("Fermer")
            }
            .padding(16)
            Divider()
            ScrollView {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .frame(width: 480, height: 400)
        .background(AppBackdrop())
    }
}
