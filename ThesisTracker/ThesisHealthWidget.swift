import SwiftUI

// MARK: - Feature #7 : Indicateur de santé de thèse

struct ThesisHealthWidget: View {
    @ObservedObject var store: DataStore
    @State private var animatedScore: Double = 0

    private var health: DataStore.ThesisHealth { store.thesisHealth }

    var body: some View {
        GlassCard {
            VStack(spacing: 14) {
                // Header
                HStack {
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(statusColor.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: statusIcon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(statusColor)
                        }
                        Text("Santé de la thèse")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    statusBadge
                }

                // Gauge + score
                HStack(spacing: 16) {
                    gaugeRing
                    VStack(alignment: .leading, spacing: 6) {
                        Text(health.headline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        if health.details.count > 1 {
                            ForEach(health.details.dropFirst(), id: \.self) { detail in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(Color.labelMuted.opacity(0.4))
                                        .frame(width: 4, height: 4)
                                    Text(detail)
                                        .font(.system(size: 11))
                                        .foregroundColor(.labelMuted)
                                        .lineLimit(2)
                                }
                            }
                        }
                        if health.details.isEmpty {
                            Text("Continue comme ça !")
                                .font(.system(size: 11))
                                .foregroundColor(.labelMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Progress bar segmentée
                scoreBar
            }
        }
        .onAppear {
            withAppAnimation(.easeOut(duration: 0.28)) {
                animatedScore = Double(health.score)
            }
        }
        .onChange(of: health.score) { _, newScore in
            withAppAnimation(.easeOut(duration: 0.20)) {
                animatedScore = Double(newScore)
            }
        }
    }

    // MARK: - Sub-views

    private var gaugeRing: some View {
        ZStack {
            Circle()
                .stroke(Color.cardBorder, lineWidth: 6)
                .frame(width: 62, height: 62)
            Circle()
                .trim(from: 0, to: animatedScore / 100)
                .stroke(statusColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 62, height: 62)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(health.score)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("/100")
                    .font(.system(size: 8))
                    .foregroundColor(.labelMuted)
            }
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(statusColor)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(statusColor.opacity(0.10))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(statusColor.opacity(0.25), lineWidth: 1))
    }

    private var scoreBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.cardBorder)
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [statusColor.opacity(0.7), statusColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: geo.size.width * (animatedScore / 100), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch health.status {
        case .good:     return .accentGreen
        case .warning:  return .accentWarm
        case .critical: return Color(red: 0.929, green: 0.329, blue: 0.329)
        }
    }

    private var statusIcon: String {
        switch health.status {
        case .good:     return "heart.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private var statusLabel: String {
        switch health.status {
        case .good:     return "En bonne forme"
        case .warning:  return "Attention requise"
        case .critical: return "Action urgente"
        }
    }
}
