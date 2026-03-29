import AppKit
import SwiftUI

@main
struct ThesisTrackerApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var pomodoroController = PomodoroAppController()
    @AppStorage("interfaceMode") private var interfaceMode: String = "VA"

    init() {
        _ = NotificationManager.shared
    }

    var body: some Scene {
        // ── Fenêtre principale ────────────────────────────
        WindowGroup {
            MainView(store: store)
                .environmentObject(pomodoroController)
                .environmentObject(store)
                .task {
                    await pomodoroController.initializeIfNeeded()
                    pomodoroController.onSaveWordCount = { [weak store] wordCount in
                        guard let store else { return }
                        guard let project = store.activeProject, let chapter = store.activeChapter else { return }
                        let today = DataStore.today
                        let current = chapter.entryForDate(today)?.totalCount ?? 0
                        store.setTotalForDate(current + wordCount, for: chapter.id, in: project.id, date: today)
                    }
                    setupGlobalHotkey()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Fichier") {
                Button("Exporter les données…") {
                    NotificationCenter.default.post(name: .showExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Historique") {
                Button("Afficher l'historique") {
                    NotificationCenter.default.post(name: .navigateToHistory, object: nil)
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
            }
            CommandMenu("Accomplissements") {
                Button("Afficher les accomplissements") {
                    NotificationCenter.default.post(name: .showAchievements, object: nil)
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            }
            CommandMenu("Affichage") {
                Button(interfaceMode == "VA" ? "✓ Version Actuelle (VA)" : "  Version Actuelle (VA)") {
                    interfaceMode = "VA"
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button(interfaceMode == "VD" ? "✓ Version Papier (VD)" : "  Version Papier (VD)") {
                    interfaceMode = "VD"
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Divider()

                Button("Basculer VA ↔ VD") {
                    interfaceMode = interfaceMode == "VA" ? "VD" : "VA"
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }
        }

        // ── Menu bar ─────────────────────────────────────
        MenuBarExtra {
            MenuBarEntryView(store: store)
                .environmentObject(pomodoroController)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "text.book.closed.fill")
                if pomodoroController.timerSnapshot.phase == .idle {
                    if store.currentStreak >= 2 {
                        Text("\(store.currentStreak)")
                            .font(.system(size: 11, weight: .bold))
                    }
                } else {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                    Text(pomodoroController.formattedDuration(pomodoroController.timerSnapshot.remainingTime))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - Global hotkey ⌘⌥Space

    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak pomodoroController] event in
            guard let pomodoroController else { return }
            let cmdOpt: NSEvent.ModifierFlags = [.command, .option]
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == cmdOpt else { return }
            guard event.keyCode == 49 else { return } // 49 = Space
            Task { @MainActor in
                if case .idle = pomodoroController.timerSnapshot.phase {
                    if pomodoroController.pendingNextMode != nil {
                        pomodoroController.startRecommendedSession()
                    } else {
                        pomodoroController.startFocusSession()
                    }
                } else {
                    pomodoroController.pauseOrResume()
                }
            }
        }
    }
}
