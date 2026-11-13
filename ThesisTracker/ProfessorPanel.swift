import AppKit
import SwiftUI

// MARK: - 5.14 Professeur en « note rapide » : fenêtre flottante
//
// Même séance que l'onglet Professeur (ProfessorSession.shared), dans une
// petite fenêtre qui reste au-dessus des autres (y compris de Pages en plein
// écran). Taille et position mémorisées par macOS.

@MainActor
final class ProfessorPanelManager: NSObject, NSWindowDelegate {
    static let shared = ProfessorPanelManager()
    private var panel: NSPanel?

    private override init() {}

    /// Fenêtre affichée et non réduite (sert à décider d'une notification).
    var isVisible: Bool {
        guard let panel else { return false }
        return panel.isVisible && !panel.isMiniaturized && panel.occlusionState.contains(.visible)
    }

    /// Bouton du tableau de bord et raccourci ⇧⌘P : ouvre ou referme.
    func toggle(store: DataStore) {
        if let panel, panel.isVisible, panel.isKeyWindow {
            panel.orderOut(nil)
        } else {
            show(store: store)
        }
    }

    /// Ouvre la fenêtre au premier plan (clic sur une notification).
    func show(store: DataStore) {
        let p = panel ?? makePanel(store: store)
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func makePanel(store: DataStore) -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = "Professeur — note rapide"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.minSize = NSSize(width: 340, height: 360)
        p.isMovableByWindowBackground = true
        p.delegate = self
        p.contentView = NSHostingView(rootView:
            ProfessorView(store: store, showSidebar: .constant(false), compact: true)
                .padding(.top, 18)
                .background(AppBackdrop())
        )
        if !p.setFrameUsingName("ProfessorQuickPanel") {
            if let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 420 - 24, y: f.maxY - 560 - 24))
            } else {
                p.center()
            }
        }
        p.setFrameAutosaveName("ProfessorQuickPanel")
        return p
    }

    func windowDidBecomeKey(_ notification: Notification) {
        ProfessorSession.shared.unreadReply = false
    }
}

// MARK: - Bouton « note rapide » (tableau de bord)

struct ProfessorQuickButton: View {
    @ObservedObject var store: DataStore
    @ObservedObject private var session = ProfessorSession.shared
    var size: CGFloat = 28

    var body: some View {
        Button {
            ProfessorPanelManager.shared.toggle(store: store)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accentWarm)
                    .frame(width: size, height: size)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.accentWarm.opacity(0.09))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.accentWarm.opacity(0.25), lineWidth: 1))
                    )
                if session.isSending {
                    Circle().fill(Color.accentWarm).frame(width: 7, height: 7).offset(x: 2, y: -2)
                } else if session.unreadReply {
                    Circle().fill(Color.blue).frame(width: 7, height: 7).offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.pressable)
        .help("Professeur — note rapide (⇧⌘P)")
        .accessibilityLabel("Ouvrir le professeur en note rapide")
    }
}
