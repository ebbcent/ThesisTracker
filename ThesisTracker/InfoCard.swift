import SwiftUI

struct InfoCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String
    var emphasized: Bool = false
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, emphasized: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.emphasized = emphasized
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(CockpitTheme.textPrimary(for: colorScheme))
                Spacer()
                Capsule()
                    .fill((emphasized ? CockpitTheme.glow : CockpitTheme.stroke(for: colorScheme)).opacity(0.9))
                    .frame(width: emphasized ? 56 : 34, height: 6)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(emphasized ? CockpitTheme.panelElevated(for: colorScheme) : CockpitTheme.panel(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(CockpitTheme.stroke(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: CockpitTheme.shadow(for: colorScheme).opacity(emphasized ? 1 : 0.7), radius: emphasized ? 20 : 10, y: 10)
    }
}
