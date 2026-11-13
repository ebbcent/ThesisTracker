import SwiftUI

// MARK: - Feature #9 : Widget vitesse d'écriture

struct WritingSpeedWidget: View {
    @ObservedObject var store: DataStore

    private var data: DataStore.WritingSpeedData { store.writingSpeedData }

    var body: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accent.opacity(0.12))
                            .frame(width: 28, height: 28)
                        Image(systemName: "speedometer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accent)
                    }
                    Text("Vitesse d'écriture")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    trendBadge
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DataStore.formatNumber(data.avgCharsPerDay))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text(store.data.useWordCount ? "mots/j" : "car./j")
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                    Spacer()
                }

                Text(data.activeDaysCount == 0
                     ? "Aucun jour actif sur les 7 derniers jours"
                     : "Moyenne sur \(data.activeDaysCount) jour\(data.activeDaysCount > 1 ? "s" : "") actif\(data.activeDaysCount > 1 ? "s" : "") · 7 jours")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)

                sparkline
            }
        }
    }

    private var trendBadge: some View {
        let pct  = Int(abs(data.trend - 1.0) * 100)
        let isUp = data.trend >= 1.0
        let isFlat = pct < 3
        let color: Color = isFlat ? .labelMuted : (isUp ? .accentGreen : Color(hex: "#F97316"))
        let icon  = isFlat ? "minus" : (isUp ? "arrow.up.right" : "arrow.down.right")
        let label = isFlat ? "stable" : (isUp ? "+\(pct)%" : "-\(pct)%")
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    private var sparkline: some View {
        let values = data.last7Values
        let maxV   = CGFloat(max(values.max() ?? 1, 1))
        return GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                    let barH = max(3, (geo.size.height - 2) * CGFloat(v) / maxV)
                    let isToday = i == values.count - 1
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isToday ? Color.accent : Color.accent.opacity(0.3))
                        .frame(width: max(1, (geo.size.width - CGFloat(values.count - 1) * 3) / CGFloat(values.count)),
                               height: barH)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 28)
    }
}
