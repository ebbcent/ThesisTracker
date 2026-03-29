import SwiftUI

// MARK: - Vue Timeline / Gantt

struct TimelineView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    private let chapterNameWidth: CGFloat = 120
    private let barAreaWidth: CGFloat = 240
    private let dateWidth: CGFloat = 80

    // MARK: - Data helpers

    private struct TimelineEntry: Identifiable {
        let id: UUID
        let projectName: String
        let chapterName: String
        let chapterId: UUID
        let projectId: UUID
        let progress: Int         // caractères écrits
        let goal: Int             // objectif (0 si non défini)
        let deadline: String?     // "yyyy-MM-dd" ou nil
    }

    private var entries: [TimelineEntry] {
        var result: [TimelineEntry] = []
        for project in store.data.projects {
            for chapter in project.chapters {
                // Masquer les chapitres sans objectif ni deadline
                guard chapter.goal > 0 || chapter.deadline != nil else { continue }
                let progress = chapter.entries
                    .sorted { $0.date > $1.date }
                    .first?.totalCount ?? 0
                result.append(TimelineEntry(
                    id: chapter.id,
                    projectName: project.name,
                    chapterName: chapter.name,
                    chapterId: chapter.id,
                    projectId: project.id,
                    progress: progress,
                    goal: chapter.goal,
                    deadline: chapter.deadline
                ))
            }
        }
        // Trier : d'abord avec deadline (par date), puis sans deadline
        return result.sorted { a, b in
            switch (a.deadline, b.deadline) {
            case (let da?, let db?): return da < db
            case (.some, .none):     return true
            case (.none, .some):     return false
            case (.none, .none):     return a.chapterName < b.chapterName
            }
        }
    }

    // Grouper par projet (ordre stable)
    private var entriesByProject: [(projectName: String, entries: [TimelineEntry])] {
        var seen: [String] = []
        var dict: [String: [TimelineEntry]] = [:]
        for entry in entries {
            if dict[entry.projectName] == nil {
                seen.append(entry.projectName)
                dict[entry.projectName] = []
            }
            dict[entry.projectName]!.append(entry)
        }
        return seen.map { (projectName: $0, entries: dict[$0]!) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header standard
            headerView

            Divider()

            if entries.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Colonne headers
                        columnHeaders

                        Divider().padding(.bottom, 4)

                        ForEach(entriesByProject, id: \.projectName) { group in
                            projectSection(group)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(Color.appBg)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            if !showSidebar {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                        showSidebar = true
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.labelMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.cardBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accent)

            Text("Timeline")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            Text("\(entries.count) chapitre\(entries.count != 1 ? "s" : "")")
                .font(.system(size: 12))
                .foregroundColor(.labelMuted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Column headers

    private var columnHeaders: some View {
        HStack(spacing: 0) {
            Text("Chapitre")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
                .frame(width: chapterNameWidth, alignment: .leading)

            Text("Progression")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)

            Text("Échéance")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.labelMuted)
                .kerning(0.8)
                .frame(width: dateWidth, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .textCase(.uppercase)
    }

    // MARK: - Project section

    private func projectSection(_ group: (projectName: String, entries: [TimelineEntry])) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section titre projet
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.accent)
                Text(group.projectName)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.accent)
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.top, 8)

            // Chapitres
            VStack(spacing: 2) {
                ForEach(group.entries) { entry in
                    chapterRow(entry)
                }
            }
        }
    }

    // MARK: - Chapter row

    private func chapterRow(_ entry: TimelineEntry) -> some View {
        HStack(spacing: 0) {
            // Nom du chapitre
            Text(entry.chapterName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .frame(width: chapterNameWidth, alignment: .leading)

            // Barre de progression
            GeometryReader { geo in
                let fraction = progressFraction(for: entry)
                let color = barColor(fraction: fraction, hasDeadline: entry.deadline != nil)
                let barWidth = max(4, geo.size.width * fraction)

                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.fieldBg)
                        .frame(height: 10)

                    // Fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.9), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: barWidth, height: 10)

                    // Dépassement / bordure si 100%+
                    if fraction >= 1.0 {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(color.opacity(0.6), lineWidth: 1.5)
                            .frame(height: 10)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 10)
            .padding(.leading, 10)
            .padding(.trailing, 10)

            // Infos droite
            VStack(alignment: .trailing, spacing: 1) {
                if let deadline = entry.deadline {
                    Text(formattedDeadline(deadline))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(deadlineColor(deadline))
                        .lineLimit(1)
                } else {
                    Text("–")
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
                let pct = Int(progressFraction(for: entry) * 100)
                Text("\(pct)%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(barColor(fraction: progressFraction(for: entry), hasDeadline: entry.deadline != nil))
            }
            .frame(width: dateWidth, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cardBg.opacity(0.5))
        )
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.day.timeline.left")
                .font(.system(size: 36))
                .foregroundColor(.labelMuted.opacity(0.4))
            Text("Aucun chapitre avec objectif ou échéance")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.labelMuted)
            Text("Ajoutez un objectif ou une échéance à vos chapitres\npour les voir apparaître ici.")
                .font(.system(size: 12))
                .foregroundColor(.labelMuted.opacity(0.7))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func progressFraction(for entry: TimelineEntry) -> Double {
        guard entry.goal > 0 else { return 0 }
        return min(1.5, Double(entry.progress) / Double(entry.goal))
    }

    private func barColor(fraction: Double, hasDeadline: Bool) -> Color {
        if fraction >= 1.0 { return .accentGreen }
        if fraction >= 0.5 { return .accentWarm }
        return hasDeadline ? Color(red: 0.929, green: 0.329, blue: 0.329) : .accent
    }

    private func formattedDeadline(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.dateFormat = "d MMM yy"
        return out.string(from: date)
    }

    private func deadlineColor(_ dateStr: String) -> Color {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return .labelMuted }
        let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if daysLeft < 0 { return Color(red: 0.929, green: 0.329, blue: 0.329) }
        if daysLeft <= 7 { return .accentWarm }
        return .labelMuted
    }
}
