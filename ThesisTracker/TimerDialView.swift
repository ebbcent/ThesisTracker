import SwiftUI

struct TimerDialView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let timeText: String
    let progress: Double
    let accentColor: Color
    var size: CGFloat = 280

    @State private var pulseActive = false

    private var strokeWidth: CGFloat { size * 0.075 }
    private var titleSize: CGFloat  { size * 0.054 }
    private var timeSize: CGFloat   { size * 0.20 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(CockpitTheme.stroke(for: colorScheme), lineWidth: strokeWidth)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(accentColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: accentColor.opacity(0.45), radius: 10)
                .appAnimation(.easeInOut(duration: 0.4), value: progress)
                .appAnimation(.easeInOut(duration: 0.5), value: accentColor)

            if progress > 0 && progress < 1 {
                Circle()
                    .stroke(accentColor.opacity(0.10), lineWidth: strokeWidth * 1.7)
                    .scaleEffect(pulseActive ? 1.05 : 1.0)
                    .animation(
                        .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                        value: pulseActive
                    )
            }

            VStack(spacing: size * 0.036) {
                Text(title)
                    .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(CockpitTheme.textSecondary(for: colorScheme))
                    .contentTransition(.numericText())
                    .appAnimation(.easeInOut(duration: 0.25), value: title)

                Text(timeText)
                    .font(.system(size: timeSize, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                    .contentTransition(.numericText(countsDown: true))
                    .appAnimation(.linear(duration: 0.15), value: timeText)
            }
        }
        .frame(width: size, height: size)
        .onAppear { pulseActive = progress > 0 && progress < 1 }
        .onChange(of: progress) { _, newVal in
            pulseActive = newVal > 0 && newVal < 1
        }
    }
}
