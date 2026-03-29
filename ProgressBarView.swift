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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: isComplete ? "checkmark.circle.fill" : icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(displayColor)
                        .frame(width: 16)
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    Text(formatNumber(value))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.5), value: value)
                    if hasGoal {
                        Text(" / \(formatNumber(goal))")
                            .font(.system(size: 11))
                            .foregroundColor(.labelMuted)
                        Text("  \(percentage)%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(displayColor)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.5), value: percentage)
                    }
                }
            }

            if hasGoal {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.12))
                            .frame(height: 3)
                        if animatedProgress > 0 {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(displayColor)
                                .frame(width: max(3, geo.size.width * animatedProgress), height: 3)
                        }
                    }
                }
                .frame(height: 3)
            }
        }
        .onAppear {
            guard hasGoal else { return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.75).delay(0.1)) {
                animatedProgress = targetProgress
            }
        }
        .onChange(of: value) { _, _ in
            guard hasGoal else { return }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = targetProgress
            }
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "\u{202F}"
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
