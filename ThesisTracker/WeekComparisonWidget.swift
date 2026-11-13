import SwiftUI

// MARK: - Feature #10 : Comparaison semaine sur semaine

struct WeekComparisonWidget: View {
    @ObservedObject var store: DataStore

    private var data: DataStore.WeekComparisonData { store.weekComparisonData }

    private var deltaPercent: Int {
        guard data.lastTotal > 0 else { return data.thisTotal > 0 ? 100 : 0 }
        return Int((Double(data.thisTotal) / Double(data.lastTotal) - 1.0) * 100)
    }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: "#6366F1").opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#6366F1"))
                    }
                    Text("Comparaison semaines")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    deltaBadge
                }

                barsView

                HStack(spacing: 14) {
                    legendDot(color: .accent,
                              label: "Cette sem. · \(DataStore.formatNumber(data.thisTotal))")
                    legendDot(color: .labelMuted.opacity(0.35),
                              label: "Sem. passée · \(DataStore.formatNumber(data.lastTotal))")
                    Spacer()
                }
            }
        }
    }

    private var deltaBadge: some View {
        let isUp  = deltaPercent >= 0
        let isFlat = abs(deltaPercent) < 3
        let color: Color = isFlat ? .labelMuted : (isUp ? .accentGreen : Color(hex: "#F97316"))
        let label = isFlat ? "stable" : (isUp ? "+\(deltaPercent)%" : "\(deltaPercent)%")
        return Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private var barsView: some View {
        let all  = data.thisWeek + data.lastWeek
        let maxV = CGFloat(max(all.max() ?? 1, 1))
        let maxH: CGFloat = 40

        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<min(7, data.dayLabels.count), id: \.self) { i in
                VStack(spacing: 3) {
                    HStack(alignment: .bottom, spacing: 1) {
                        let lh = max(2, maxH * CGFloat(data.lastWeek[i]) / maxV)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.labelMuted.opacity(0.22))
                            .frame(width: 7, height: lh)
                        let th = max(2, maxH * CGFloat(data.thisWeek[i]) / maxV)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accent)
                            .frame(width: 7, height: th)
                    }
                    Text(data.dayLabels[i])
                        .font(.system(size: 10))
                        .foregroundColor(.labelMuted)
                }
                if i < 6 { Spacer(minLength: 0) }
            }
        }
        .frame(height: maxH + 14)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 12, height: 4)
            Text(label).font(.system(size: 10)).foregroundColor(.labelMuted)
        }
    }
}
