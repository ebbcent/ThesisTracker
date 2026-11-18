import SwiftUI

// MARK: - Feature #59 : Onboarding contextuel
// Bulle d'aide affichée une seule fois par vue, persistée via AppStorage.
// Usage : .onboardingTooltip(key: "dashboard", message: "...", alignment: .bottom)

// MARK: - View Modifier

struct OnboardingTooltipModifier: ViewModifier {
    let key: String
    let message: String
    let icon: String
    let alignment: Alignment

    @AppStorage private var dismissed: Bool
    @State private var visible: Bool = false

    init(key: String, message: String, icon: String = "lightbulb.fill", alignment: Alignment = .bottom) {
        self.key       = key
        self.message   = message
        self.icon      = icon
        self.alignment = alignment
        self._dismissed = AppStorage(wrappedValue: false, "onboarding_dismissed_\(key)")
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: alignment) {
                if visible {
                    OnboardingTooltipBubble(
                        message: message,
                        icon: icon,
                        alignment: alignment
                    ) {
                        withAppAnimation(.easeOut(duration: 0.15)) {
                            visible = false
                        }
                        dismissed = true
                    }
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.95, anchor: unitPoint(from: alignment))
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.95, anchor: unitPoint(from: alignment))
                                .combined(with: .opacity)
                        )
                    )
                    .zIndex(200)
                }
            }
            .onAppear {
                guard !dismissed else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAppAnimation(.easeOut(duration: 0.18)) {
                        visible = true
                    }
                }
            }
    }

    private func unitPoint(from alignment: Alignment) -> UnitPoint {
        switch alignment {
        case .top, .topLeading, .topTrailing:  return .bottom
        case .bottom, .bottomLeading, .bottomTrailing: return .top
        case .leading:  return .trailing
        case .trailing: return .leading
        default:        return .center
        }
    }
}

// MARK: - Bubble View

struct OnboardingTooltipBubble: View {
    let message: String
    let icon: String
    let alignment: Alignment
    let onDismiss: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.accent)

            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 240)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: AppLook.fs(10), weight: .bold))
                    .foregroundColor(.labelMuted)
                    .padding(5)
                    .background(Circle().fill(Color.cardBorder.opacity(0.5)))
            }
            .buttonStyle(.pressable)
            .help("Fermer")
            .accessibilityLabel("Fermer")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            FloatingSurface(radius: 12)   // 5.27 : verre en Tuiles (le fond d'origine était presque transparent)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .overlay(
                    RoundedRectangle(cornerRadius: AppLook.r(12, 18), style: .continuous)
                        .stroke(Color.accent.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(offset(for: alignment))
        // Caret
        .overlay(alignment: caretAlignment) {
            Triangle()
                .fill(Color.glassFill)
                .frame(width: 10, height: 6)
                .rotationEffect(caretRotation)
                .offset(caretOffset)
        }
        .scaleEffect(hovered ? 1.02 : 1.0)
        .appAnimation(.easeInOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
    }

    private func offset(for a: Alignment) -> EdgeInsets {
        switch a {
        case .bottom, .bottomLeading, .bottomTrailing: return EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0)
        case .top, .topLeading, .topTrailing:          return EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0)
        default: return EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        }
    }

    private var caretAlignment: Alignment {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: return .top
        case .top, .topLeading, .topTrailing:           return .bottom
        case .leading:                                   return .trailing
        default:                                         return .leading
        }
    }

    private var caretRotation: Angle {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: return .degrees(0)
        case .top, .topLeading, .topTrailing:           return .degrees(180)
        case .leading:                                   return .degrees(-90)
        default:                                         return .degrees(90)
        }
    }

    private var caretOffset: CGSize {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: return CGSize(width: 0, height: -3)
        case .top, .topLeading, .topTrailing:           return CGSize(width: 0, height: 3)
        default: return .zero
        }
    }
}

// MARK: - Caret Shape

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - View Extension

extension View {
    /// Shows a one-time contextual onboarding tooltip. Pass a unique `key` per tip.
    func onboardingTooltip(
        key: String,
        message: String,
        icon: String = "lightbulb.fill",
        alignment: Alignment = .bottom
    ) -> some View {
        modifier(OnboardingTooltipModifier(key: key, message: message, icon: icon, alignment: alignment))
    }

    /// Resets all onboarding tooltips (for testing / settings).
    static func resetAllOnboardingTooltips() {
        let prefix = "onboarding_dismissed_"
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
}
