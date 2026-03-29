import SwiftUI

struct DeadlineBoardView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    private var items: [(project: Project, chapter: Chapter)] { store.chaptersWithDeadlines }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                headerView
                if items.isEmpty {
                    emptyState
                } else {
                    summaryRow
                    deadlineList
                }
            }
            .padding(20)
        }
    }

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
                Text("Echeances")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Text("\(items.count) chapitre(s) avec deadline")
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
            }
            Spacer()
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            MiniStatCard(label: "En retard", value: "\(overdueCount)", unit: "", color: .red)
            MiniStatCard(label: "Cette semaine", value: "\(dueThisWeekCount)", unit: "", color: .accentWarm)
            MiniStatCard(label: "Termines", value: "\(completedCount)", unit: "", color: .accentGreen)
        }
    }

    private var deadlineList: some View {
        VStack(spacing: 8) {
            ForEach(items, id: \.chapter.id) { item in
                let deadline = item.chapter.deadline.flatMap(DataStore.parseDate) ?? Date()
                let latest = store.latestTotal(for: item.chapter.id, in: item.project.id)
                let eta = store.estimatedCompletionDate(for: item.chapter.id, in: item.project.id)
                GlassCard {
                    HStack(alignment: .top, spacing: 14) {
                        Circle()
                            .fill(item.chapter.isCompleted ? Color.accentGreen : statusColor(for: deadline))
                            .frame(width: 10, height: 10)
                            .padding(.top, 6)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(item.project.name) · \(item.chapter.name)")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Deadline: \(DataStore.formatDate(deadline))")
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                            Text(progressLabel(latest: latest, goal: item.chapter.goal))
                                .font(.system(size: 12))
                                .foregroundColor(.labelMuted)
                            if let eta {
                                Text("Projection: \(DataStore.formatDate(eta))")
                                    .font(.system(size: 12))
                                    .foregroundColor(eta > deadline ? .red : .accentGreen)
                            }
                        }
                        Spacer()
                        Text(statusText(for: deadline, completed: item.chapter.isCompleted))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(item.chapter.isCompleted ? .accentGreen : statusColor(for: deadline))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((item.chapter.isCompleted ? Color.accentGreen : statusColor(for: deadline)).opacity(0.12)))
                    }
                }
            }
        }
    }

    private var overdueCount: Int {
        items.filter {
            guard let deadline = $0.chapter.deadline.flatMap(DataStore.parseDate), !$0.chapter.isCompleted else { return false }
            return Calendar.current.startOfDay(for: deadline) < Calendar.current.startOfDay(for: Date())
        }.count
    }

    private var dueThisWeekCount: Int {
        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: Date()) else { return 0 }
        return items.filter {
            guard let deadline = $0.chapter.deadline.flatMap(DataStore.parseDate), !$0.chapter.isCompleted else { return false }
            return deadline >= Date() && deadline <= weekEnd
        }.count
    }

    private var completedCount: Int { items.filter { $0.chapter.isCompleted }.count }

    private func statusColor(for deadline: Date) -> Color {
        let start = Calendar.current.startOfDay(for: deadline)
        let today = Calendar.current.startOfDay(for: Date())
        if start < today { return .red }
        if start <= (Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today) { return .accentWarm }
        return .accent
    }

    private func statusText(for deadline: Date, completed: Bool) -> String {
        if completed { return "Termine" }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: deadline)).day ?? 0
        if days < 0 { return "En retard" }
        if days == 0 { return "Aujourd'hui" }
        if days == 1 { return "Demain" }
        return "Dans \(days) j"
    }

    private func progressLabel(latest: Int, goal: Int) -> String {
        guard goal > 0 else { return "\(DataStore.formatNumber(latest)) car." }
        return "\(DataStore.formatNumber(latest)) / \(DataStore.formatNumber(goal)) car."
    }

    private var emptyState: some View {
        GlassCard {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundColor(.labelMuted)
                Text("Aucune deadline pour l'instant")
                    .font(.system(size: 14))
                    .foregroundColor(.labelMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }
}

