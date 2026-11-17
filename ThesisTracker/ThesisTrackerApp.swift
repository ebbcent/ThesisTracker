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
    @AppStorage("interfaceMode") private var interfaceMode: String = "VT"
    // #48 — hotkey globale configurable pour le mode focus : lue directement
    // dans UserDefaults ("globalFocusKey") par GlobalHotKeys.

    init() {
        // Délégué installé et autorisation demandée dès le lancement (et pas seulement
        // après le chargement des données Pomodoro, qui peut échouer)
        NotificationManager.shared.ensureAuthorization()
    }

    var body: some Scene {
        // ── Fenêtre principale ────────────────────────────
        WindowGroup {
            MainView(store: store)
                .monospacedDigit()   // 5.15 : chiffres à largeur fixe partout (les compteurs ne « sautent » plus)
                .environmentObject(pomodoroController)
                .environmentObject(store)
                .background(WindowAccessor())
                .task {
                    await pomodoroController.initializeIfNeeded()
                    HubWritingBridge.shared.start(store: store, pomodoro: pomodoroController)
                    AppUpdater.shared.checkAutomaticallyIfDue()
                    pomodoroController.onSaveWordCount = { [weak store] wordCount in
                        guard let store else { return }
                        guard let project = store.activeProject, let chapter = store.activeChapter else { return }
                        let today = DataStore.today
                        // 5.23 — part du dernier total connu (les saisies sont cumulatives), pas de zéro
                        // quand rien n'a encore été saisi aujourd'hui ; en mode « mots », 1 mot = 5 signes.
                        let current = store.latestTotal(for: chapter.id, in: project.id)
                        let added = store.data.useWordCount ? wordCount * 5 : wordCount
                        store.setTotalForDate(current + added, for: chapter.id, in: project.id, date: today)
                    }
                    setupGlobalHotkey(store: store, pomodoroController: pomodoroController)
                    // 5.11 — créneaux d'écriture : « Démarrer » depuis le rappel
                    NotificationManager.shared.writingSlotStartHandler = { [weak store] slotID in
                        guard let store, let slot = store.writingSlots.first(where: { $0.id == slotID }) else { return }
                        pomodoroController.startWritingSlot(slot, store: store)
                    }
                    WritingSlotScheduler.reschedule(store.writingSlots)
                    // 5.14 — clic sur « Le professeur a répondu » : ouvre la note rapide
                    NotificationManager.shared.professorReplyHandler = { [weak store] in
                        guard let store else { return }
                        ProfessorPanelManager.shared.show(store: store)
                    }
                }
                .onChange(of: store.data.writingSlots ?? []) { _, slots in
                    WritingSlotScheduler.reschedule(slots)
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
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") {
                    Task { await AppUpdater.shared.check(promptIfAvailable: true, announceResult: true) }
                }
            }
            CommandGroup(replacing: .appSettings) {
                SettingsLink {
                    Text("Réglages…")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // Menu Édition : annuler/rétablir. Si un champ texte a le focus, on
            // laisse l'UndoManager du champ agir ; sinon on utilise l'historique du store.
            CommandGroup(replacing: .undoRedo) {
                Button(store.undoLabel.map { "Annuler « \($0) »" } ?? "Annuler") {   // 5.15 : libellé de l'action
                    if NSApp.keyWindow?.firstResponder is NSText {
                        NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                    } else {
                        store.undo()
                    }
                }
                .keyboardShortcut("z", modifiers: .command)

                Button(store.redoLabel.map { "Rétablir « \($0) »" } ?? "Rétablir") {
                    if NSApp.keyWindow?.firstResponder is NSText {
                        NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
                    } else {
                        store.redo()
                    }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            // Intégré au menu Fichier système (évite un second menu « Fichier »)
            CommandGroup(replacing: .importExport) {
                Button("Exporter les données…") {
                    NotificationCenter.default.post(name: .showExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Historique") {
                Button("Afficher l'historique") {
                    NotificationCenter.default.post(name: .navigateToHistory, object: nil)
                }
                // ⌘⇧H (⌘⌥H = « Masquer les autres » de macOS)
                .keyboardShortcut("h", modifiers: [.command, .shift])
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

                // 5.24 — troisième affichage du tableau de bord
                Button(interfaceMode == "VT" ? "✓ Tuiles (VT)" : "  Tuiles (VT)") {
                    interfaceMode = "VT"
                }
                .keyboardShortcut("3", modifiers: [.command, .option])

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
                            .font(.system(size: 10))
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
                    // 5.21 : même style que le cadran — petit anneau de progression + chiffres arrondis
                    let snap = pomodoroController.timerSnapshot
                    let ratio = snap.totalDuration > 0 ? 1 - snap.remainingTime / snap.totalDuration : 0
                    Image(nsImage: MenuBarRing.image(progress: ratio, paused: snap.phase.isPaused))
                    Text(pomodoroController.formattedDuration(snap.remainingTime))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .help(store.currentStreak > 0 ? "Série : \(store.currentStreak) jours · Record : \(store.longestStreak) jours · ⌃⌥N pour saisie rapide" : "Writing Process · ⌃⌥N pour saisie rapide")
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

    /// Hotkeys globales Carbon (voir GlobalHotKeys.swift) — installées une seule fois,
    /// sans autorisation Accessibilité, événement consommé.
    private func setupGlobalHotkey(store: DataStore, pomodoroController: PomodoroAppController) {
        GlobalHotKeys.shared.install(
            // ⌃⌥P → Pomodoro start/pause
            onPomodoro: { [weak pomodoroController] in
                guard let pomodoroController else { return }
                if case .idle = pomodoroController.timerSnapshot.phase {
                    if pomodoroController.pendingNextMode != nil {
                        pomodoroController.startRecommendedSession()
                    } else {
                        pomodoroController.startFocusSession()
                    }
                } else {
                    pomodoroController.pauseOrResume()
                }
            },
            // ⌃⌥N → Quick Entry (#2)
            onQuickEntry: { [weak store] in
                guard let store else { return }
                QuickEntryPanelManager.shared.show(store: store)
            },
            // #48 — ⌃⌥ + lettre configurable → ouvrir mode focus (ramène l'app au premier plan)
            onFocus: {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .showFocusWriting, object: nil)
            }
        )
    }
}
