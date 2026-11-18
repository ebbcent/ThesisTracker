import SwiftUI

// MARK: - Feature #40 : Archive automatique suggérée

struct AutoArchiveSuggestionBanner: View {
    @ObservedObject var store: DataStore
    @AppStorage("dismissedArchiveSuggestions") private var dismissedRaw: String = ""

    private var dismissed: Set<UUID> {
        Set(dismissedRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    private var candidates: [Project] {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let cal = Calendar(identifier: .gregorian)
        let totals = store.dailyTotals()
        return store.data.projects.filter { proj in
            guard !proj.isArchived, !dismissed.contains(proj.id) else { return false }
            // Check if no entry in the last 90 days for ANY chapter in this project
            var lastEntryDate: Date? = nil
            for ch in proj.chapters {
                if let latest = ch.entries.map(\.date).max(),
                   let d = fmt.date(from: latest) {
                    if lastEntryDate == nil || d > lastEntryDate! { lastEntryDate = d }
                }
            }
            if let last = lastEntryDate {
                let days = cal.dateComponents([.day], from: last, to: today).day ?? 0
                return days >= 90
            }
            return false // No entries at all — don't suggest
        }
    }

    var body: some View {
        if !candidates.isEmpty {
            VStack(spacing: 8) {
                ForEach(candidates) { project in
                    projectBanner(project)
                }
            }
        }
    }

    private func projectBanner(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "archivebox")
                .font(.system(size: 13))
                .foregroundColor(.accentWarm)
            VStack(alignment: .leading, spacing: 2) {
                Text("Archiver « \(project.name) » ?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Aucune saisie depuis plus de 90 jours")
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Button("Archiver") {
                    archiveProject(project)
                }
                .font(.system(size: AppLook.fs(11), weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.accentWarm)
                .clipShape(RoundedRectangle(cornerRadius: AppLook.r(6, 10)))
                .buttonStyle(.pressable)

                Button("Ignorer") {
                    dismissProject(project)
                }
                .font(.system(size: AppLook.fs(11)))
                .foregroundColor(.labelMuted)
                .buttonStyle(.pressable)
            }
        }
        .padding(12)
        .background(Color.accentWarm.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.accentWarm.opacity(0.2), lineWidth: 1))
    }

    private func archiveProject(_ project: Project) {
        if let idx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
            store.data.projects[idx].isArchived = true
            store.save()
        }
        dismissProject(project)
    }

    private func dismissProject(_ project: Project) {
        var d = dismissed
        d.insert(project.id)
        dismissedRaw = d.map(\.uuidString).joined(separator: ",")
    }
}

// MARK: - Helper: compute when a project was last active
extension Project {
    /// Last date any chapter in this project had an entry (yyyy-MM-dd), or nil
    var lastActivityDate: String? {
        chapters.compactMap { $0.entries.map(\.date).max() }.max()
    }

    /// Days since last activity
    var daysSinceLastActivity: Int? {
        guard let last = lastActivityDate else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: last) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: d, to: Date()).day
    }
}
