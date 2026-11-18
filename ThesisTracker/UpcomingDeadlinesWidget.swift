import SwiftUI

// MARK: - Feature #11 : Prochains jalons

struct UpcomingDeadlinesWidget: View {
    @ObservedObject var store: DataStore

    private var items: [DataStore.UpcomingMilestoneItem] {
        store.upcomingMilestonesData(limit: 3)
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppLook.r(8, 12))
                            .fill(Color(hex: "#DC2626").opacity(0.10))
                            .frame(width: 28, height: 28)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#DC2626"))
                    }
                    Text("Prochains jalons")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if !items.isEmpty {
                        Text("\(items.count)")
                            .font(.system(size: AppLook.fs(10), weight: .bold))
                            .foregroundColor(.labelMuted)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.cardBorder)
                            .clipShape(Capsule())
                    }
                }

                if items.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: AppLook.fs(11))).foregroundColor(.accentGreen)
                        Text("Aucun jalon à venir")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            milestoneRow(item)
                        }
                    }
                }
            }
        }
    }

    private func milestoneRow(_ item: DataStore.UpcomingMilestoneItem) -> some View {
        let (color, label) = countdownStyle(item.daysUntil)
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 3, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.projectName)
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
            }

            Spacer()

            Text(label)
                .font(.system(size: AppLook.fs(11), weight: .bold, design: AppLook.fontDesign))
                .foregroundColor(color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
        }
    }

    private func countdownStyle(_ days: Int) -> (Color, String) {
        if days < 0  { return (Color(hex: "#DC2626"), "J+\(-days)") }
        if days == 0 { return (Color(hex: "#DC2626"), "Aujourd'hui") }
        if days == 1 { return (Color(hex: "#DC2626"), "Demain") }
        if days <= 7 { return (Color(hex: "#F97316"), "J-\(days)") }
        if days <= 14{ return (Color(hex: "#F5C518"), "J-\(days)") }
        return (.accentGreen, "J-\(days)")
    }
}
