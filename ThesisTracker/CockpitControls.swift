import SwiftUI

struct CockpitButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(prominent ? Color.white : CockpitTheme.textPrimary(for: colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background(configuration: configuration))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(border(configuration: configuration), lineWidth: 1)
            )
            .shadow(color: CockpitTheme.shadow(for: colorScheme).opacity(prominent ? 0.9 : 0.35), radius: prominent ? 10 : 4, y: 6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func background(configuration: Configuration) -> Color {
        if prominent {
            return configuration.isPressed ? CockpitTheme.accent.opacity(0.82) : CockpitTheme.accent
        }
        return configuration.isPressed
            ? CockpitTheme.panelElevated(for: colorScheme)
            : CockpitTheme.panel(for: colorScheme)
    }

    private func border(configuration: Configuration) -> Color {
        if prominent {
            return CockpitTheme.accent.opacity(configuration.isPressed ? 0.2 : 0.5)
        }
        return CockpitTheme.stroke(for: colorScheme)
    }
}

struct PremiumMenuPicker: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let icon: String
    let accent: Color
    let items: [PremiumMenuItem]

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(item.title, action: item.action)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CockpitTheme.textTertiary(for: colorScheme))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CockpitTheme.overlayFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CockpitTheme.stroke(for: colorScheme), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }
}

struct PremiumMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let action: () -> Void
}
