import Foundation

enum ActiveTimerMode: String, CaseIterable {
    case focus
    case shortBreak
    case longBreak

    var sessionKind: SessionKind {
        switch self {
        case .focus: .focus
        case .shortBreak: .shortBreak
        case .longBreak: .longBreak
        }
    }

    var displayName: String {
        sessionKind.displayName
    }
}

enum TimerPhase: Equatable {
    case idle
    case running(ActiveTimerMode)
    case paused(ActiveTimerMode)

    var activeMode: ActiveTimerMode? {
        switch self {
        case .idle: nil
        case .running(let mode), .paused(let mode): mode
        }
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

struct PomodoroTimerSnapshot: Equatable {
    var phase: TimerPhase
    var remainingTime: TimeInterval
    var totalDuration: TimeInterval
    var startedAt: Date?
    var expectedEndDate: Date?
    var completedFocusCountInCycle: Int
    var selectedCategoryID: UUID?
    var selectedProjectID: UUID?

    static let idle = PomodoroTimerSnapshot(
        phase: .idle,
        remainingTime: PomodoroAppSettings.default.focusDuration,
        totalDuration: PomodoroAppSettings.default.focusDuration,
        startedAt: nil,
        expectedEndDate: nil,
        completedFocusCountInCycle: 0,
        selectedCategoryID: nil,
        selectedProjectID: nil
    )
}

protocol PomodoroTimerEngineDelegate: AnyObject {
    func timerEngine(_ engine: PomodoroTimerEngine, didUpdate snapshot: PomodoroTimerSnapshot)
    func timerEngine(
        _ engine: PomodoroTimerEngine,
        didFinish mode: ActiveTimerMode,
        nextMode: ActiveTimerMode?,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        categoryID: UUID?,
        projectID: UUID?
    )
    func timerEngine(
        _ engine: PomodoroTimerEngine,
        didInterrupt mode: ActiveTimerMode,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        categoryID: UUID?,
        projectID: UUID?
    )
}

/// État du minuteur sauvegardé dans UserDefaults (propre à chaque Mac) pour survivre
/// à un redémarrage ou à un plantage de l'app.
private struct PersistedTimerState: Codable {
    var mode: String
    var isPaused: Bool
    var startedAt: Date
    var expectedEndDate: Date?
    var remainingAtPause: TimeInterval
    var pausedTotal: TimeInterval
    var pauseStartedAt: Date?
    var plannedDuration: TimeInterval
    var categoryID: UUID?
    var projectID: UUID?
    var savedAt: Date
}

/// Moteur du minuteur. Tout l'état est manipulé sur le main thread (le timer tourne sur la
/// file principale) : plus de course entre le tick et start/pause/stop.
final class PomodoroTimerEngine {
    weak var delegate: PomodoroTimerEngineDelegate?

    private var settings: PomodoroAppSettings
    private var snapshot = PomodoroTimerSnapshot.idle
    private var timer: DispatchSourceTimer?

    private var completedFocusCountInCycle = 0
    private var currentMode: ActiveTimerMode?
    private var currentStartedAt: Date?
    private var currentExpectedEndDate: Date?
    private var currentPlannedDuration: TimeInterval = 0
    private var remainingAtPause: TimeInterval = 0
    /// Début de la pause en cours (nil si le minuteur tourne)
    private var pauseStartedAt: Date?
    /// Temps de pause cumulé de la session en cours (pauses manuelles + veille)
    private var pausedTotal: TimeInterval = 0
    private var selectedCategoryID: UUID?
    private var selectedProjectID: UUID?

    /// Tolérance ajoutée à la durée prévue pour une session terminée
    private let completionTolerance: TimeInterval = 5
    private static let persistedStateKey = "pomodoro.timer.runningState"
    private static let persistedCycleKey = "pomodoro.timer.completedFocusCountInCycle"

    init(settings: PomodoroAppSettings) {
        self.settings = settings
        snapshot.remainingTime = settings.focusDuration
        snapshot.totalDuration = settings.focusDuration
    }

    /// Une session (en cours ou en pause) existe
    var hasActiveSession: Bool {
        currentMode != nil
    }

    var currentSnapshot: PomodoroTimerSnapshot {
        snapshot
    }

    func updateSettings(_ settings: PomodoroAppSettings) {
        self.settings = settings
        if currentMode == nil {
            publish(.idle, remaining: settings.focusDuration, total: settings.focusDuration, startedAt: nil, endDate: nil)
        }
    }

    /// Démarre une session de concentration. Ne fait rien (retourne `false`) si une session est déjà en cours ou en pause.
    @discardableResult
    func startFocusSession(categoryID: UUID?, projectID: UUID?) -> Bool {
        guard currentMode == nil else { return false }
        selectedCategoryID = categoryID
        selectedProjectID = projectID
        beginNewSession(mode: .focus)
        return true
    }

    @discardableResult
    func startBreak(mode: ActiveTimerMode) -> Bool {
        guard mode == .shortBreak || mode == .longBreak, currentMode == nil else { return false }
        beginNewSession(mode: mode)
        return true
    }

    func pause() {
        guard let mode = currentMode, case .running = snapshot.phase, let expectedEndDate = currentExpectedEndDate else { return }
        remainingAtPause = max(0, expectedEndDate.timeIntervalSinceNow)
        pauseStartedAt = Date()
        currentExpectedEndDate = nil
        cancelTimer()
        publish(.paused(mode), remaining: remainingAtPause, total: currentPlannedDuration, startedAt: currentStartedAt, endDate: nil)
        persistState()
    }

    func resume() {
        guard case .paused(let mode) = snapshot.phase, currentMode == mode else { return }
        if let pauseStartedAt {
            pausedTotal += max(0, Date().timeIntervalSince(pauseStartedAt))
        }
        pauseStartedAt = nil
        run(mode: mode, remaining: remainingAtPause)
    }

    func stop() {
        guard let mode = currentMode, let startedAt = currentStartedAt else {
            resetToIdle(resetCycle: true)
            return
        }

        let endedAt = Date()
        let plannedDuration = currentPlannedDuration
        let actualDuration = min(activeDuration(startedAt: startedAt, endedAt: endedAt), plannedDuration + completionTolerance)
        let categoryID = mode == .focus ? selectedCategoryID : nil
        let projectID = mode == .focus ? selectedProjectID : nil
        // Arrêt manuel : le cycle repart de zéro
        resetToIdle(resetCycle: true)
        delegate?.timerEngine(
            self,
            didInterrupt: mode,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: plannedDuration,
            actualDuration: actualDuration,
            categoryID: categoryID,
            projectID: projectID
        )
    }

    /// Remet le compteur de cycle à zéro (pause longue ignorée…)
    func resetCycle() {
        completedFocusCountInCycle = 0
        publish(snapshot.phase, remaining: snapshot.remainingTime, total: snapshot.totalDuration, startedAt: snapshot.startedAt, endDate: snapshot.expectedEndDate)
        persistState()
    }

    /// Restaure l'état sauvegardé au lancement précédent. Une session expirée pendant que l'app
    /// était fermée est transmise au délégué comme interrompue.
    func restorePersistedState() {
        let defaults = UserDefaults.standard
        completedFocusCountInCycle = max(0, defaults.integer(forKey: Self.persistedCycleKey))
        guard currentMode == nil,
              let raw = defaults.data(forKey: Self.persistedStateKey),
              let state = try? JSONDecoder().decode(PersistedTimerState.self, from: raw),
              let mode = ActiveTimerMode(rawValue: state.mode) else {
            defaults.removeObject(forKey: Self.persistedStateKey)
            if currentMode == nil {
                publish(.idle, remaining: settings.focusDuration, total: settings.focusDuration, startedAt: nil, endDate: nil)
            }
            return
        }

        selectedCategoryID = state.categoryID
        selectedProjectID = state.projectID
        currentMode = mode
        currentStartedAt = state.startedAt
        currentPlannedDuration = state.plannedDuration > 0 ? state.plannedDuration : plannedDuration(for: mode)
        pausedTotal = max(0, state.pausedTotal)

        if state.isPaused {
            pauseStartedAt = state.pauseStartedAt ?? state.savedAt
            remainingAtPause = max(0, state.remainingAtPause)
            currentExpectedEndDate = nil
            publish(.paused(mode), remaining: remainingAtPause, total: currentPlannedDuration, startedAt: state.startedAt, endDate: nil)
            persistState()
            return
        }

        pauseStartedAt = nil
        if let end = state.expectedEndDate, end.timeIntervalSinceNow > 1 {
            // Toujours dans les temps : reprise du décompte
            run(mode: mode, remaining: end.timeIntervalSinceNow)
            return
        }

        // Expirée pendant que l'app était fermée : on ne sait pas si elle a été menée à terme
        let endedAt = min(Date(), state.expectedEndDate ?? state.savedAt)
        let startedAt = state.startedAt
        let planned = currentPlannedDuration
        let actualDuration = min(activeDuration(startedAt: startedAt, endedAt: max(startedAt, endedAt)), planned)
        let categoryID = mode == .focus ? selectedCategoryID : nil
        let projectID = mode == .focus ? selectedProjectID : nil
        resetToIdle(resetCycle: false)
        delegate?.timerEngine(
            self,
            didInterrupt: mode,
            startedAt: startedAt,
            endedAt: max(startedAt, endedAt),
            plannedDuration: planned,
            actualDuration: actualDuration,
            categoryID: categoryID,
            projectID: projectID
        )
    }

    // MARK: - Private

    private func beginNewSession(mode: ActiveTimerMode) {
        pausedTotal = 0
        pauseStartedAt = nil
        currentPlannedDuration = plannedDuration(for: mode)
        currentStartedAt = Date()
        run(mode: mode, remaining: currentPlannedDuration)
    }

    private func run(mode: ActiveTimerMode, remaining: TimeInterval) {
        cancelTimer()
        currentMode = mode
        currentExpectedEndDate = Date().addingTimeInterval(remaining)
        remainingAtPause = 0
        publish(.running(mode), remaining: remaining, total: currentPlannedDuration, startedAt: currentStartedAt, endDate: currentExpectedEndDate)
        persistState()

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.tick()
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard case .running(let mode) = snapshot.phase,
              currentMode == mode,
              let expectedEndDate = currentExpectedEndDate,
              let startedAt = currentStartedAt else { return }
        let remaining = max(0, expectedEndDate.timeIntervalSinceNow)
        if remaining <= 0.5 {
            completeCurrentMode(mode: mode, startedAt: startedAt, expectedEndDate: expectedEndDate)
        } else {
            publish(.running(mode), remaining: remaining, total: currentPlannedDuration, startedAt: startedAt, endDate: expectedEndDate)
        }
    }

    private func completeCurrentMode(mode: ActiveTimerMode, startedAt: Date, expectedEndDate: Date) {
        // Garde contre une double complétion (tick en file après un arrêt / une autre complétion)
        guard currentMode == mode, case .running = snapshot.phase else { return }
        cancelTimer()

        let endedAt = max(startedAt, min(Date(), expectedEndDate))
        let durationForCompletedMode = currentPlannedDuration
        let actualDuration = min(
            activeDuration(startedAt: startedAt, endedAt: endedAt),
            durationForCompletedMode + completionTolerance
        )

        let nextMode = nextMode(after: mode)
        if mode == .focus {
            completedFocusCountInCycle += 1
        } else if mode == .longBreak {
            completedFocusCountInCycle = 0
        }
        let categoryID = mode == .focus ? selectedCategoryID : nil
        let projectID = mode == .focus ? selectedProjectID : nil

        resetToIdle(resetCycle: false)

        delegate?.timerEngine(
            self,
            didFinish: mode,
            nextMode: nextMode,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: durationForCompletedMode,
            actualDuration: actualDuration,
            categoryID: categoryID,
            projectID: projectID
        )
    }

    /// Durée active = durée écoulée − pauses (y compris la pause en cours éventuelle)
    private func activeDuration(startedAt: Date, endedAt: Date) -> TimeInterval {
        var paused = pausedTotal
        if let pauseStartedAt {
            paused += max(0, endedAt.timeIntervalSince(pauseStartedAt))
        }
        return max(0, endedAt.timeIntervalSince(startedAt) - paused)
    }

    private func nextMode(after mode: ActiveTimerMode) -> ActiveTimerMode? {
        switch mode {
        case .focus:
            let focusCount = completedFocusCountInCycle + 1
            return focusCount.isMultiple(of: max(1, settings.sessionsBeforeLongBreak)) ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    private func plannedDuration(for mode: ActiveTimerMode) -> TimeInterval {
        switch mode {
        case .focus: settings.focusDuration
        case .shortBreak: settings.shortBreakDuration
        case .longBreak: settings.longBreakDuration
        }
    }

    private func resetToIdle(resetCycle: Bool) {
        cancelTimer()
        currentMode = nil
        currentStartedAt = nil
        currentExpectedEndDate = nil
        currentPlannedDuration = 0
        remainingAtPause = 0
        pauseStartedAt = nil
        pausedTotal = 0
        if resetCycle {
            completedFocusCountInCycle = 0
        }
        publish(.idle, remaining: settings.focusDuration, total: settings.focusDuration, startedAt: nil, endDate: nil)
        persistState()
    }

    private func publish(_ phase: TimerPhase, remaining: TimeInterval, total: TimeInterval, startedAt: Date?, endDate: Date?) {
        let snapshot = PomodoroTimerSnapshot(
            phase: phase,
            remainingTime: remaining,
            totalDuration: total,
            startedAt: startedAt,
            expectedEndDate: endDate,
            completedFocusCountInCycle: completedFocusCountInCycle,
            selectedCategoryID: selectedCategoryID,
            selectedProjectID: selectedProjectID
        )
        self.snapshot = snapshot
        delegate?.timerEngine(self, didUpdate: snapshot)
    }

    /// Sauvegarde l'état courant dans UserDefaults (appelé à chaque changement d'état, pas à chaque tick).
    private func persistState() {
        let defaults = UserDefaults.standard
        defaults.set(completedFocusCountInCycle, forKey: Self.persistedCycleKey)
        guard let mode = currentMode, let startedAt = currentStartedAt else {
            defaults.removeObject(forKey: Self.persistedStateKey)
            return
        }
        let state = PersistedTimerState(
            mode: mode.rawValue,
            isPaused: snapshot.phase.isPaused,
            startedAt: startedAt,
            expectedEndDate: currentExpectedEndDate,
            remainingAtPause: remainingAtPause,
            pausedTotal: pausedTotal,
            pauseStartedAt: pauseStartedAt,
            plannedDuration: currentPlannedDuration,
            categoryID: selectedCategoryID,
            projectID: selectedProjectID,
            savedAt: Date()
        )
        if let raw = try? JSONEncoder().encode(state) {
            defaults.set(raw, forKey: Self.persistedStateKey)
        }
    }

    private func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
