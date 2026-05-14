import SwiftUI
import Combine

// Manages overlay display priority so multiple overlays never stack simultaneously.
// Higher rawValue = higher priority (shown first when competing).
enum OverlayKind: Int, Comparable {
    case welcomeBack      = 1
    case postSession      = 2
    case weekSummary      = 3
    case dailySummary     = 4
    case milestone        = 5
    case deadlineAlert    = 6
    case commandPalette   = 7

    static func < (lhs: OverlayKind, rhs: OverlayKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

final class OverlayCoordinator: ObservableObject {
    @Published private(set) var active: Set<OverlayKind> = []

    // Highest-priority overlay currently visible (command palette always wins)
    var topOverlay: OverlayKind? { active.max() }

    func show(_ kind: OverlayKind) {
        // Don't stack lower-priority overlays when a high-priority one is up,
        // unless it's command palette (always allowed on top)
        if kind != .commandPalette, let top = topOverlay, top > kind { return }
        active.insert(kind)
    }

    func dismiss(_ kind: OverlayKind) {
        active.remove(kind)
    }

    func isVisible(_ kind: OverlayKind) -> Bool {
        active.contains(kind)
    }

    // Schedule a dismissal after a delay, respecting any manual early dismissal.
    func autoDismiss(_ kind: OverlayKind, after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.dismiss(kind)
        }
    }
}
