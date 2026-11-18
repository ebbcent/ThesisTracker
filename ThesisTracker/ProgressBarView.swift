import SwiftUI

struct ProgressBarView: View {
    let label: String
    let icon: String
    let value: Int
    let goal: Int
    let color: Color
    let trackColor: Color  // kept for API compatibility

    @State private var animatedProgress: Double = 0

    private var hasGoal: Bool { goal > 0 }
    private var targetProgress: Double {
        guard hasGoal else { return 0 }
        return min(1.0, Double(value) / Double(goal))
    }
    private var percentage: Int { Int(targetProgress * 100) }
    private var isComplete: Bool { hasGoal && value >= goal }
    private var displayColor: Color { isComplete ? .accentGreen : color }

    // Static formatter — NumberFormatter is expensive to allocate
    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                        .font(.system(size: AppLook.fs(11), weight: .medium))
                        .foregroundColor(displayColor)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(formatNumber(value))
                        .font(.system(size: AppLook.fs(11), weight: .semibold))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                        .appAnimation(.easeOut(duration: 0.15), value: value)
                    if hasGoal {
                        Text(" / \(formatNumber(goal))")
                            .font(.system(size: AppLook.fs(11)))
                            .foregroundColor(.labelMuted)
                        Text("  \(percentage)%")
                            .font(.system(size: AppLook.fs(11), weight: .bold))
                            .foregroundColor(displayColor)
                            .contentTransition(.numericText())
                            .appAnimation(.easeOut(duration: 0.15), value: percentage)
                    }
                }
            }

            if hasGoal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.cardBorder)
                            .frame(height: 3)
                        if animatedProgress > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(
                                    LinearGradient(
                                        colors: isComplete ? [Color.accentGreen] : [displayColor, displayColor.opacity(0.75)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(3, geo.size.width * animatedProgress), height: 3)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
        // 5.18 : VoiceOver lit « Objectif du jour, 3 200 sur 10 000, 32 pour cent »
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(hasGoal ? "\(formatNumber(value)) sur \(formatNumber(goal)), \(percentage) pour cent" : formatNumber(value))
        .onAppear {
            guard hasGoal else { return }
            // Fast fill — no sluggish delay
            withAppAnimation(.easeOut(duration: 0.25)) {
                animatedProgress = targetProgress
            }
        }
        .onChange(of: value) { _, _ in
            guard hasGoal else { return }
            withAppAnimation(.easeOut(duration: 0.18)) {
                animatedProgress = targetProgress
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        ProgressBarView.numberFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
