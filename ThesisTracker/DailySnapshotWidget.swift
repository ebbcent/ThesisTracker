import SwiftUI

// MARK: - Feature #15 : Snapshot quotidien (hier vs avant-hier)

struct DailySnapshotWidget: View {
    @ObservedObject var store: DataStore

    private var yesterday:     Int { store.yesterdayTotal }
    private var dayBefore:     Int { store.dayBeforeYesterdayTotal }
    private var delta:         Int { yesterday - dayBefore }
    private var todayTotal:    Int { store.dailyTotals()[DataStore.today] ?? 0 }
    private var dailyGoal:     Int { store.data.dailyGoal }
    private var useWords:      Bool { store.data.useWordCount }

    private var deltaColor: Color {
        if delta > 0 { return .accentGreen }
        if delta < 0 { return Color(hex: "#F97316") }
        return .labelMuted
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#7C3AED").opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#7C3AED"))
                    }
                    Text("Snapshot quotidien")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if todayTotal > 0 {
                        todayBadge
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    // Hier
                    statBlock(
                        label: "Hier",
                        value: fmt(yesterday),
                        sub: nil,
                        color: .primary
                    )

                    // Delta
                    VStack(spacing: 2) {
                        Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(deltaColor)
                        Text(delta == 0 ? "=" : (delta > 0 ? "+\(fmt(delta))" : "-\(fmt(abs(delta)))"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(deltaColor)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)

                    // Avant-hier
                    statBlock(
                        label: "Avant-hier",
                        value: fmt(dayBefore),
                        sub: nil,
                        color: .secondary
                    )

                    Spacer()
                }

                // Barre objectif du jour (si configuré)
                if dailyGoal > 0 && todayTotal > 0 {
                    let r = min(1.0, Double(todayTotal) / Double(dailyGoal))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Aujourd'hui · \(fmt(todayTotal)) / \(fmt(dailyGoal))")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted)
                            Spacer()
                            if r >= 1.0 {
                                Text("✓ Objectif atteint")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accentGreen)
                            } else {
                                Text("\(Int(r * 100))%")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accent)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.cardBorder).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(r >= 1.0 ? Color.accentGreen : Color.accent)
                                    .frame(width: geo.size.width * r, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }

    private func statBlock(label: String, value: String, sub: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.labelMuted)
                .textCase(.uppercase)
                .tracking(0.4)
            Text(value)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
            if let sub {
                Text(sub).font(.system(size: 10)).foregroundColor(.labelMuted)
            }
        }
    }

    private var todayBadge: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.accentGreen).frame(width: 5, height: 5)
            Text("Aujourd'hui · \(fmt(todayTotal))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.accentGreen)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.accentGreen.opacity(0.08))
        .clipShape(Capsule())
    }

    private func fmt(_ val: Int) -> String {
        useWords ? "\(DataStore.formatNumber(val / 5)) mots" : "\(DataStore.formatNumber(val)) car."
    }
}
