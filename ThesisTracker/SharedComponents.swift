import SwiftUI

// MARK: - EmptyStateView (#10)
// Composant réutilisable pour les états vides : KanbanView, HistoryListView, ChartView, SearchView.

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var iconColor: Color = .labelMuted
    var action: (() -> Void)? = nil
    var actionLabel: String = "Action"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.08))
                    .frame(width: 60, height: 60)
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor.opacity(0.5))
            }
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.75))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.labelMuted)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(Color.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }
}

// MARK: - Debouncer

final class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) { self.delay = delay }

    func schedule(_ action: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: action)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func flush() { workItem?.perform(); workItem = nil }
}

// MARK: - FilterChipButton (#11)
// Chip de filtre réutilisable : KanbanView, SearchView, ChartView.

struct FilterChipButton: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: AppLook.fs(10), weight: isSelected ? .semibold : .regular))
                }
                Text(label)
                    .font(.system(size: AppLook.fs(11), weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .white : .labelMuted)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.pressable)
        .appAnimation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
