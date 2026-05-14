import SwiftUI

/// #20 — Wrapper unifié : bascule entre heatmap annuelle et calendrier mensuel.
/// Les deux vues gardent leur propre état interne ; le toggle flotte en safe-area top.
struct UnifiedActivityView: View {

    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    enum ViewMode { case heatmap, calendar }
    @State private var mode: ViewMode

    init(store: DataStore, showSidebar: Binding<Bool>, initialMode: ViewMode = .heatmap) {
        self.store = store
        self._showSidebar = showSidebar
        self._mode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            switch mode {
            case .heatmap:
                HeatmapView(store: store, showSidebar: $showSidebar)
            case .calendar:
                CalendarView(store: store, showSidebar: $showSidebar)
            }
        }
        .id(mode)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.18), value: mode)
        .safeAreaInset(edge: .top, spacing: 0) {
            toggleBar
        }
    }

    // MARK: - Toggle bar

    private var toggleBar: some View {
        HStack {
            Spacer()
            HStack(spacing: 2) {
                modeButton(icon: "tablecells.fill", target: .heatmap, tooltip: "Vue annuelle (heatmap)")
                modeButton(icon: "calendar",        target: .calendar, tooltip: "Vue mensuelle (calendrier)")
            }
            .padding(3)
            .background(Color.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.cardBorder, lineWidth: 1)
            )
            .padding(.trailing, 20)
        }
        .padding(.vertical, 6)
        .background(Color.appBg)
    }

    private func modeButton(icon: String, target: ViewMode, tooltip: String) -> some View {
        let selected = mode == target
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = target }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(selected ? .white : .labelMuted)
                .frame(width: 30, height: 26)
                .background(selected ? Color.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .animation(.easeInOut(duration: 0.15), value: selected)
    }
}
