import AppKit
import SwiftUI
import CoreSpotlight

// MARK: - Window size persistence
//
// SwiftUI's WindowGroup on macOS doesn't reliably restore window size across
// full quits. We persist the frame to UserDefaults and apply it BEFORE the
// window is visible, so the user never sees the default-then-resize flash.
//
// Two mechanisms layered:
//   1. `.defaultSize(...)` on WindowGroup, fed by the saved size — handles
//      SwiftUI's initial layout (the window is created at the saved size).
//   2. `viewWillMove(toWindow:)` hook — runs BEFORE the window is shown,
//      synchronously sets the full saved frame (incl. position).
private enum WindowSizePersistence {
    static let userDefaultsKey = "ThesisTrackerMainWindowFrame"

    /// Direct-to-file storage. UserDefaults goes through cfprefsd which buffers
    /// writes — on a hard kill / Force Quit, recent saves can be lost. Writing
    /// to a file with `.atomic` performs an fsync before returning, so the
    /// frame is guaranteed on disk by the time we exit the save handler.
    private static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("Writing Process")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("window-frame.txt")
    }()

    /// Read once at app launch. Used by `.defaultSize` and the pre-show hook.
    /// File takes precedence over UserDefaults; UserDefaults is a fallback for
    /// frames saved by the previous implementation.
    static let savedFrame: NSRect? = {
        let raw: NSRect? = {
            if let data = try? Data(contentsOf: fileURL),
               let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !str.isEmpty {
                let r = NSRectFromString(str)
                if r.width > 200 && r.height > 200 { return r }
            }
            if let str = UserDefaults.standard.string(forKey: userDefaultsKey) {
                let r = NSRectFromString(str)
                if r.width > 200 && r.height > 200 { return r }
            }
            return nil
        }()
        guard let frame = raw else { return nil }
        // Reject frames that don't intersect any visible screen (e.g. user
        // disconnected the monitor where the window used to live). Otherwise
        // the window would launch off-screen and feel "missing".
        let visible = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        return visible ? frame : nil
    }()

    static let savedSize: CGSize = savedFrame.map { CGSize(width: $0.width, height: $0.height) }
        ?? CGSize(width: 1200, height: 800)

    static func applyInitialFrame(to window: NSWindow) {
        guard let frame = savedFrame else { return }
        window.setFrame(frame, display: false)
    }

    private static func write(frame: NSRect) {
        let str = NSStringFromRect(frame)
        // Atomic file write — fsync'd before returning, survives a kill.
        try? str.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        // Mirror to UserDefaults for back-compat with anything that read from there.
        UserDefaults.standard.set(str, forKey: userDefaultsKey)
    }

    fileprivate static var observersAttached = false
    static func startSaving(window: NSWindow) {
        guard !observersAttached else { return }
        observersAttached = true
        let nc = NotificationCenter.default
        let save: (Notification) -> Void = { _ in write(frame: window.frame) }
        nc.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: save)
        nc.addObserver(forName: NSWindow.didMoveNotification,   object: window, queue: .main, using: save)
        nc.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main, using: save)
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main, using: save)
    }
}

/// NSView subclass whose `viewWillMove(toWindow:)` runs BEFORE the window
/// becomes visible. Setting the frame here avoids the visible "small then big"
/// flash that DispatchQueue.main.async caused.
private final class WindowAttachView: NSView {
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if let newWindow {
            WindowSizePersistence.applyInitialFrame(to: newWindow)
        }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            window.minSize = NSSize(width: 900, height: 600)
            WindowSizePersistence.startSaving(window: window)
        }
    }
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowAttachView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@main
struct ThesisTrackerApp: App {
    @StateObject private var store = DataStore()
    @StateObject private var pomodoroController = PomodoroAppController()
    @AppStorage("interfaceMode") private var interfaceMode: String = "VA"
    // #48 — hotkey globale configurable pour le mode focus
    @AppStorage("globalFocusKey") private var globalFocusKey: String = "f"

    init() {
        _ = NotificationManager.shared
    }

    var body: some Scene {
        // ── Fenêtre principale ────────────────────────────
        WindowGroup {
            MainView(store: store)
                .environmentObject(pomodoroController)
                .environmentObject(store)
                .background(WindowAccessor())
                .task {
                    await pomodoroController.initializeIfNeeded()
                    pomodoroController.onSaveWordCount = { [weak store] wordCount in
                        guard let store else { return }
                        guard let project = store.activeProject, let chapter = store.activeChapter else { return }
                        let today = DataStore.today
                        let current = chapter.entryForDate(today)?.totalCount ?? 0
                        store.setTotalForDate(current + wordCount, for: chapter.id, in: project.id, date: today)
                    }
                    setupGlobalHotkey(store: store)
                }
                // #51 — Spotlight deep-link navigation
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let target = SpotlightTarget.from(activityIdentifier: identifier)
                    else { return }
                    handleSpotlightTarget(target, store: store)
                }
        }
        .defaultSize(WindowSizePersistence.savedSize)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Réglages…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
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

        // ── Réglages (⌘,) ────────────────────────────────
        Settings {
            SettingsView(store: store)
                .environmentObject(pomodoroController)
        }

        // ── Menu bar ─────────────────────────────────────
        MenuBarExtra {
            MenuBarEntryView(store: store)
                .environmentObject(pomodoroController)
        } label: {
            // V5 — Couleur adaptative selon avancement (#9)
            let todayTotal = store.dailyProgress
            let dailyGoal  = store.effectiveDailyGoal
            let goalRatio  = dailyGoal > 0 ? Double(todayTotal) / Double(dailyGoal) : 0
            let iconColor: Color = goalRatio >= 1.0 ? .accentGreen
                                 : goalRatio >= 0.5 ? .yellow
                                 : goalRatio >  0   ? .orange
                                 : .primary
            HStack(spacing: 4) {
                Image(systemName: "text.book.closed.fill")
                    .foregroundColor(iconColor)
                if pomodoroController.timerSnapshot.phase == .idle {
                    if store.currentStreak >= 2 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(red: 0.961, green: 0.455, blue: 0.114))
                        Text("\(store.currentStreak)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    if todayTotal > 0 {
                        Text("·")
                            .font(.system(size: 11))
                            .opacity(0.5)
                        Text(store.formatCountShort(todayTotal))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(iconColor)
                    }
                } else {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10))
                    Text(pomodoroController.formattedDuration(pomodoroController.timerSnapshot.remainingTime))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
            }
            .help(store.currentStreak > 0 ? "Streak : \(store.currentStreak) jours · Record : \(store.longestStreak) jours · ⌘⇧Espace pour saisie rapide" : "Writing Process · ⌘⇧Espace pour saisie rapide")
        }
        .menuBarExtraStyle(.window)
    }

    // MARK: - #51 Spotlight navigation

    private func handleSpotlightTarget(_ target: SpotlightTarget, store: DataStore) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            switch target.destination {
            case .project(let projectId):
                store.data.activeProjectId = projectId
                store.save()
                NotificationCenter.default.post(
                    name: .navigateToDashboard, object: nil,
                    userInfo: ["projectId": projectId]
                )

            case .chapter(let chapterId):
                // Find which project owns this chapter and activate both
                guard let project = store.data.projects.first(where: {
                    $0.chapters.contains { $0.id == chapterId }
                }) else { return }
                store.data.activeProjectId = project.id
                if let projIdx = store.data.projects.firstIndex(where: { $0.id == project.id }) {
                    store.data.projects[projIdx].activeChapterId = chapterId
                }
                store.save()
                NotificationCenter.default.post(
                    name: .navigateToDashboard, object: nil,
                    userInfo: ["chapterId": chapterId]
                )
            }
        }
    }

    // MARK: - Global hotkeys

    private func setupGlobalHotkey(store: DataStore) {
        // #48 — capture de la clé configurable au moment de l'enregistrement
        let capturedFocusKey = globalFocusKey
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak pomodoroController, weak store] event in
            guard let pomodoroController else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let cmdOpt: NSEvent.ModifierFlags   = [.command, .option]
            let cmdShift: NSEvent.ModifierFlags = [.command, .shift]

            // ⌘⌥Space → Pomodoro start/pause
            if flags == cmdOpt && event.keyCode == 49 {
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
                return
            }

            // ⌘⇧Space ou ⌥⌘W → Quick Entry (#2)
            let isQuickEntry = (flags == cmdShift && event.keyCode == 49)
                             || (flags == cmdOpt  && event.keyCode == 13) // W = 13
            if isQuickEntry {
                guard let store else { return }
                Task { @MainActor in
                    QuickEntryPanelManager.shared.show(store: store)
                }
                return
            }

            // #48 — ⌘⌥ + lettre configurable → ouvrir mode focus (ramène l'app au premier plan)
            if flags == cmdOpt,
               let char = event.characters?.lowercased(),
               !char.isEmpty, char == capturedFocusKey {
                Task { @MainActor in
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .showFocusWriting, object: nil)
                }
                return
            }
        }
    }
}
