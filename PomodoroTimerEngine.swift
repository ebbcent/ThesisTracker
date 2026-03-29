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

final class PomodoroTimerEngine {
    weak var delegate: PomodoroTimerEngineDelegate?

    private var settings: PomodoroAppSettings
    private var snapshot = PomodoroTimerSnapshot.idle
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "ThesisTracker.PomodoroTimerEngine.queue")

    private var completedFocusCountInCycle = 0
    private var currentMode: ActiveTimerMode?
    private var currentStartedAt: Date?
    private var currentExpectedEndDate: Date?
    private var remainingAtPause: TimeInterval = 0
    private var selectedCategoryID: UUID?
    private var selectedProjectID: UUID?

    init(settings: PomodoroAppSettings) {
        self.settings = settings
        snapshot.remainingTime = settings.focusDuration
        snapshot.totalDuration = settings.focusDuration
    }

    func updateSettings(_ settings: PomodoroAppSettings) {
        self.settings = settings
        if currentMode == nil {
            publish(.idle, remaining: settings.focusDuration, total: settings.focusDuration, startedAt: nil, endDate: nil)
        }
    }

    func startFocusSession(categoryID: UUID?, projectID: UUID?) {
        selectedCategoryID = categoryID
        selectedProjectID = projectID
        start(mode: .focus, duration: settings.focusDuration)
    }

    func startBreak(mode: ActiveTimerMode) {
        guard mode == .shortBreak || mode == .longBreak else { return }
        start(mode: mode, duration: plannedDuration(for: mode))
    }

    func pause() {
        guard let mode = currentMode, let expectedEndDate = currentExpectedEndDate else { return }
        remainingAtPause = max(0, expectedEndDate.timeIntervalSinceNow)
        cancelTimer()
        publish(.paused(mode), remaining: remainingAtPause, total: snapshot.totalDuration, startedAt: currentStartedAt, endDate: nil)
    }

    func resume() {
        guard case .paused(let mode) = snapshot.phase else { return }
        start(mode: mode, duration: remainingAtPause, preserveStartedAt: currentStartedAt)
    }

    func stop() {
        guard let mode = currentMode, let startedAt = currentStartedAt else {
            resetToIdle(resetCycle: false)
            return
        }

        let endedAt = Date()
        let plannedDuration = snapshot.totalDuration
        let actualDuration = max(0, endedAt.timeIntervalSince(startedAt))
        cancelTimer()
        resetToIdle(resetCycle: false)
        DispatchQueue.main.async {
            self.delegate?.timerEngine(
                self,
                didInterrupt: mode,
                startedAt: startedAt,
                endedAt: endedAt,
                plannedDuration: plannedDuration,
                actualDuration: actualDuration,
                categoryID: mode == .focus ? self.selectedCategoryID : nil,
                projectID: mode == .focus ? self.selectedProjectID : nil
            )
        }
    }

    private func start(mode: ActiveTimerMode, duration: TimeInterval, preserveStartedAt: Date? = nil) {
        cancelTimer()
        currentMode = mode
        let startedAt = preserveStartedAt ?? Date()
        currentStartedAt = startedAt
        currentExpectedEndDate = Date().addingTimeInterval(duration)
        publish(.running(mode), remaining: duration, total: plannedDuration(for: mode), startedAt: startedAt, endDate: currentExpectedEndDate)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard let mode = currentMode, let expectedEndDate = currentExpectedEndDate, let startedAt = currentStartedAt else { return }
        let remaining = max(0, expectedEndDate.timeIntervalSinceNow)
        if remaining <= 0.5 {
            completeCurrentMode(mode: mode, startedAt: startedAt)
        } else {
            publish(.running(mode), remaining: remaining, total: snapshot.totalDuration, startedAt: startedAt, endDate: expectedEndDate)
        }
    }

    private func completeCurrentMode(mode: ActiveTimerMode, startedAt: Date) {
        let endedAt = Date()
        let durationForCompletedMode = plannedDuration(for: mode)
        let actualDuration = max(0, endedAt.timeIntervalSince(startedAt))
        cancelTimer()

        let nextMode = nextMode(after: mode)
        if mode == .focus {
            completedFocusCountInCycle += 1
        } else if mode == .longBreak {
            completedFocusCountInCycle = 0
        }

        resetToIdle(resetCycle: false)

        DispatchQueue.main.async {
            self.delegate?.timerEngine(
                self,
                didFinish: mode,
                nextMode: nextMode,
                startedAt: startedAt,
                endedAt: endedAt,
                plannedDuration: durationForCompletedMode,
                actualDuration: actualDuration,
                categoryID: mode == .focus ? self.selectedCategoryID : nil,
                projectID: mode == .focus ? self.selectedProjectID : nil
            )
        }
    }

    private func nextMode(after mode: ActiveTimerMode) -> ActiveTimerMode? {
        switch mode {
        case .focus:
            let focusCount = completedFocusCountInCycle + 1
            return focusCount.isMultiple(of: settings.sessionsBeforeLongBreak) ? .longBreak : .shortBreak
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
        remainingAtPause = 0
        if resetCycle {
            completedFocusCountInCycle = 0
        }
        publish(.idle, remaining: settings.focusDuration, total: settings.focusDuration, startedAt: nil, endDate: nil)
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
        DispatchQueue.main.async {
            self.delegate?.timerEngine(self, didUpdate: snapshot)
        }
    }

    private func cancelTimer() {
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }
}
