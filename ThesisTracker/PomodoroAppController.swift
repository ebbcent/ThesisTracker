import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class PomodoroAppController: ObservableObject {
    enum AppSection: String, CaseIterable, Identifiable {
        case today
        case journal
        case statistics
        case projects
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: "Aujourd'hui"
            case .journal: "Journal"
            case .statistics: "Statistiques"
            case .projects: "Projets"
            case .settings: "Réglages"
            }
        }

        var icon: String {
            switch self {
            case .today: "sun.max"
            case .journal: "book.closed"
            case .statistics: "chart.xyaxis.line"
            case .projects: "square.stack.3d.up"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    // MARK: - Core state

    @Published var data: PomodoroAppData
    @Published private(set) var timerSnapshot: PomodoroTimerSnapshot
    @Published var selectedSection: AppSection = .today

    // MARK: - Filter state

    @Published var selectedCategoryID: UUID?
    @Published var selectedProjectID: UUID?

    // MARK: - Writing chapter link (feature #6)

    @Published var selectedWritingProjectId: UUID? = nil
    @Published var selectedWritingChapterId: UUID? = nil

    // MARK: - Statistics state

    @Published var selectedRange: PomodoroStatisticsRange = .weekly
    @Published var statisticsAnchorDate: Date = .now

    // MARK: - Journal state

    @Published var selectedJournalDate: Date?
    @Published var journalSearchText = ""

    // MARK: - UI state

    @Published var noteDraft = ""
    @Published var wordCountDraft = ""
    @Published var isPresentingNoteEditor = false

    /// #43 — delta d'écriture pendant la session (injecté depuis MainView/ThesisTrackerApp)
    @Published var sessionWritingDelta: Int? = nil

    var onSaveWordCount: ((Int) -> Void)?
    @Published var isFocusModeEnabled = false
    @Published var editingSessionDraft: PomodoroSessionRecord?
    @Published private(set) var statusMessage = "Chargement des données..."
    @Published private(set) var storageLocationDescription = "Préparation du stockage..."
    /// Problème de stockage à afficher (fichier iCloud indisponible, restauration…) — nil si tout va bien
    @Published private(set) var storageWarning: String?

    /// Une session de concentration externe (Sanctuaire) est en cours : démarrer un Pomodoro est bloqué
    @Published private(set) var isExternalFocusActive = false

    // MARK: - Pending next phase

    @Published private(set) var pendingNextMode: ActiveTimerMode?

    // MARK: - Animation triggers

    @Published private(set) var focusSessionJustCompleted = false

    // MARK: - Validation

    @Published private(set) var goalValidationError: String?

    // MARK: - Cached stats

    @Published private(set) var dashboardSummary: PomodoroDashboardSummary = .empty
    @Published private(set) var todayOperationalSnapshot: PomodoroTodayOperationalSnapshot = .empty
    @Published private(set) var goalProgress: [PomodoroGoalProgress] = []
    @Published private(set) var timeline: [PomodoroTimelineEntry] = []
    @Published private(set) var dailySummary: PomodoroDailySummary = .empty
    @Published private(set) var currentStreak: Int = 0
    @Published private(set) var prediction: PomodoroProductivityPrediction = .empty
    @Published private(set) var projectInsights: [PomodoroProjectInsight] = []

    // MARK: - Cached filtered stats

    @Published private(set) var chartMetrics: [PomodoroPeriodMetric] = []
    @Published private(set) var contributionCells: [PomodoroContributionCell] = []
    @Published private(set) var weekdayDistribution: [PomodoroDistributionBucket] = []
    @Published private(set) var hourlyDistribution: [PomodoroDistributionBucket] = []

    // MARK: - Cached journal

    @Published private(set) var journalEntries: [PomodoroSessionRecord] = []
    @Published private(set) var selectedDayTimeline: [PomodoroDailyTimelineSegment] = []

    // MARK: - Private

    private let store: PomodoroDataStore
    private let timerEngine: PomodoroTimerEngine
    private let notificationManager = PomodoroTimerNotificationManager()
    private let soundManager = PomodoroSoundManager()
    private let monitor = PomodoroDataFileMonitor()
    private var storeURL: URL?
    private var initialized = false
    private var pendingSaveTask: Task<Void, Never>?
    private var pauseReminderTask: Task<Void, Never>?
    private var pendingNoteSessionID: UUID?
    private var activeBlockSessionIDs: [UUID] = []
    private var activeBlockStartedAt: Date?
    private var cancellables = Set<AnyCancellable>()
    /// `false` si le fichier n'a pas pu être lu au démarrage : aucune écriture (protection de l'autre Mac)
    private var isStoreWritable = true
    /// Des modifications attendent d'être écrites sur le disque
    private var hasUnsavedChanges = false
    /// La session a été mise en pause automatiquement à la mise en veille
    private var sessionPausedBySleep = false

    // MARK: - Init

    init(data: PomodoroAppData, store: PomodoroDataStore = PomodoroDataStore()) {
        self.data = data
        self.store = store
        self.timerSnapshot = .idle
        self.timerEngine = PomodoroTimerEngine(settings: data.settings)
        self.timerEngine.delegate = nil
        self.timerEngine.delegate = self
        setupCombine()
        setupSystemObservers()
    }

    convenience init() {
        self.init(data: PomodoroAppData.empty())
    }

    static var preview: PomodoroAppController {
        let controller = PomodoroAppController()
        controller.statusMessage = "Aperçu"
        controller.storageLocationDescription = "Données d'aperçu"
        return controller
    }

    // MARK: - Combine cache setup

    private func setupCombine() {
        $data
            .sink { [weak self] data in
                guard let self else { return }
                self.recomputeTodayStats(data: data)
            }
            .store(in: &cancellables)

        Publishers.MergeMany([
            $data.map { _ in () }.eraseToAnyPublisher(),
            $selectedRange.map { _ in () }.eraseToAnyPublisher(),
            $statisticsAnchorDate.map { _ in () }.eraseToAnyPublisher(),
            $selectedCategoryID.map { _ in () }.eraseToAnyPublisher(),
            $selectedProjectID.map { _ in () }.eraseToAnyPublisher()
        ])
        .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.recomputeFilteredStats() }
        .store(in: &cancellables)

        Publishers.MergeMany([
            $data.map { _ in () }.eraseToAnyPublisher(),
            $selectedCategoryID.map { _ in () }.eraseToAnyPublisher(),
            $selectedProjectID.map { _ in () }.eraseToAnyPublisher(),
            $journalSearchText.map { _ in () }.eraseToAnyPublisher(),
            $selectedJournalDate.map { _ in () }.eraseToAnyPublisher()
        ])
        .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.recomputeJournalStats() }
        .store(in: &cancellables)
    }

    /// Statistiques « aujourd'hui » (recalculées aussi au changement de jour et au réveil)
    private func recomputeTodayStats(data: PomodoroAppData) {
        dashboardSummary = PomodoroStatisticsEngine.dashboardSummary(for: .now, data: data)
        todayOperationalSnapshot = PomodoroStatisticsEngine.operationalSnapshot(for: .now, data: data)
        goalProgress = PomodoroStatisticsEngine.goalProgress(for: data)
        timeline = PomodoroStatisticsEngine.timeline(for: .now, data: data)
        dailySummary = PomodoroStatisticsEngine.dailySummary(for: .now, data: data)
        currentStreak = PomodoroStatisticsEngine.currentStreak(data: data)
        prediction = PomodoroPredictiveAnalyzer.buildPrediction(from: data)
        projectInsights = PomodoroStatisticsEngine.projectInsights(data: data)
    }

    private func refreshDateDependentStats() {
        recomputeTodayStats(data: data)
        recomputeFilteredStats()
        recomputeJournalStats()
    }

    // MARK: - System observers (minuit, veille, fermeture)

    private func setupSystemObservers() {
        // Passage à minuit : les stats « aujourd'hui » étaient figées sur la veille
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshDateDependentStats() }
            .store(in: &cancellables)

        // Notifications NSWorkspace / NSApplication postées sur le main thread : traitement synchrone
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.handleWillSleep() }
            .store(in: &cancellables)
        workspaceCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.handleDidWake() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.handleWillTerminate() }
            .store(in: &cancellables)
    }

    /// Veille = pause implicite (le temps de veille n'est pas compté comme temps de travail)
    private func handleWillSleep() {
        guard case .running = timerEngine.currentSnapshot.phase else { return }
        timerEngine.pause()
        notificationManager.cancelSessionEndNotification()
        sessionPausedBySleep = true
    }

    private func handleDidWake() {
        refreshDateDependentStats()
        guard sessionPausedBySleep else { return }
        sessionPausedBySleep = false
        guard timerEngine.currentSnapshot.phase.isPaused else { return }
        timerEngine.resume()
        scheduleEndNotification()
        statusMessage = "Minuteur repris après la veille"
    }

    private func handleWillTerminate() {
        // L'état du minuteur est déjà dans UserDefaults (restauré au prochain lancement) :
        // on retire la notification de fin pour ne pas annoncer une session qui ne se terminera pas.
        notificationManager.cancelSessionEndNotification()
        if data.settings.deepWorkEnabled, timerEngine.currentSnapshot.phase.activeMode == .focus {
            runFocusShortcut(enabled: false)
        }
        // Écriture synchrone de la sauvegarde différée
        pendingSaveTask?.cancel()
        guard hasUnsavedChanges, isStoreWritable, let storeURL else { return }
        data.globalStatistics = PomodoroStatisticsEngine.globalSnapshot(for: data)
        PomodoroDataStore.saveSynchronously(data, to: storeURL)
        hasUnsavedChanges = false
    }

    private func recomputeFilteredStats() {
        let year = Calendar.current.component(.year, from: statisticsAnchorDate)
        chartMetrics = PomodoroStatisticsEngine.chartMetrics(
            for: selectedRange,
            anchor: statisticsAnchorDate,
            data: data,
            categoryID: selectedCategoryID,
            projectID: selectedProjectID
        )
        contributionCells = PomodoroStatisticsEngine.contributionCalendar(
            for: year,
            data: data,
            categoryID: selectedCategoryID,
            projectID: selectedProjectID
        )
        weekdayDistribution = PomodoroStatisticsEngine.weekdayDistribution(data: data, categoryID: selectedCategoryID, projectID: selectedProjectID)
        hourlyDistribution = PomodoroStatisticsEngine.hourlyDistribution(data: data, categoryID: selectedCategoryID, projectID: selectedProjectID)
    }

    private func recomputeJournalStats() {
        journalEntries = PomodoroStatisticsEngine.journalSessions(
            data: data,
            categoryID: selectedCategoryID,
            projectID: selectedProjectID,
            searchText: journalSearchText,
            selectedDay: selectedJournalDate
        )
        selectedDayTimeline = PomodoroStatisticsEngine.dailyTimeline(for: selectedJournalDate ?? .now, data: data)
    }

    // MARK: - Menu bar

    var menuBarTitle: String {
        if case .idle = timerSnapshot.phase {
            return "Pomodoro"
        }
        return "\(timerSnapshot.phase.activeMode?.displayName ?? "Minuteur") \(formattedDuration(timerSnapshot.remainingTime))"
    }

    var menuBarIcon: String {
        switch timerSnapshot.phase {
        case .idle: "timer"
        case .running(.focus): "brain.head.profile"
        case .running: "cup.and.saucer"
        case .paused: "pause.circle"
        }
    }

    // MARK: - Initialization

    func initializeIfNeeded() async {
        guard !initialized else { return }
        initialized = true

        do {
            let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.ThesisTracker"
            let bootstrap = try await store.bootstrap(bundleIdentifier: bundleIdentifier)
            data = bootstrap.data
            storeURL = bootstrap.fileURL
            isStoreWritable = bootstrap.isWritable
            storageWarning = bootstrap.warning
            timerEngine.updateSettings(data.settings)
            await notificationManager.requestAuthorizationIfNeeded()
            notificationManager.onStartBreak = { [weak self] in self?.startRecommendedSession() }
            notificationManager.onStartSession = { [weak self] in self?.startRecommendedSession() }
            notificationManager.onSkipBreak = { [weak self] in self?.skipPendingPhase() }
            statusMessage = bootstrap.warning ?? "Données chargées"
            storageLocationDescription = bootstrap.locationDescription
            startMonitoring()
            // Session en cours lors de la fermeture / du plantage précédent
            timerEngine.restorePersistedState()
            scheduleEndNotification()
        } catch {
            statusMessage = "Échec de l'initialisation : \(error.localizedDescription)"
        }
    }

    // MARK: - Timer

    /// Un nouveau minuteur peut être lancé (aucune session en cours / en pause, pas de Sanctuaire)
    var canStartSession: Bool {
        !timerEngine.hasActiveSession && !isExternalFocusActive
    }

    func startFocusSession() {
        guard canStartSession else { return }
        cancelPauseReminder()
        // Démarrer directement une session au lieu de la grande pause proposée = grande pause sautée
        if pendingNextMode == .longBreak {
            timerEngine.resetCycle()
        }
        pendingNextMode = nil
        beginFocusSession()
    }

    func startRecommendedSession() {
        guard let mode = pendingNextMode, canStartSession else { return }
        cancelPauseReminder()
        pendingNextMode = nil
        if mode == .focus {
            beginFocusSession()
        } else {
            guard timerEngine.startBreak(mode: mode) else { return }
            scheduleEndNotification()
            statusMessage = "Pause démarrée"
        }
    }

    /// Chemin unique de démarrage d'une session de concentration (bouton, menu, notification, raccourci).
    private func beginFocusSession() {
        timerEngine.updateSettings(data.settings)
        guard timerEngine.startFocusSession(categoryID: selectedCategoryID, projectID: selectedProjectID) else { return }
        sessionPausedBySleep = false
        notificationManager.scheduleSessionStartedNotification(duration: data.settings.focusDuration)
        scheduleEndNotification()
        NotificationCenter.default.post(name: .pomodoroFocusStarted, object: nil)
        statusMessage = "Session de concentration démarrée"
        if data.settings.deepWorkEnabled { runFocusShortcut(enabled: true) }
    }

    func pauseOrResume() {
        sessionPausedBySleep = false
        if timerSnapshot.phase.isPaused {
            timerEngine.resume()
            scheduleEndNotification()
            statusMessage = "Minuteur repris"
        } else {
            timerEngine.pause()
            notificationManager.cancelSessionEndNotification()
            statusMessage = "Minuteur en pause"
        }
    }

    func skipPendingPhase() {
        cancelPauseReminder()
        // Grande pause sautée : nouveau cycle
        if pendingNextMode == .longBreak {
            timerEngine.resetCycle()
        }
        pendingNextMode = nil
        statusMessage = "Phase ignorée"
    }

    /// Planifie la notification de fin d'après l'état réel du moteur (démarrage, reprise, restauration).
    private func scheduleEndNotification() {
        let snapshot = timerEngine.currentSnapshot
        guard case .running(let mode) = snapshot.phase, let endDate = snapshot.expectedEndDate else { return }
        notificationManager.scheduleSessionEndNotification(
            mode: mode,
            plannedDuration: snapshot.totalDuration,
            fireIn: endDate.timeIntervalSinceNow
        )
    }

    private func schedulePauseReminder(for mode: ActiveTimerMode) {
        guard mode == .shortBreak || mode == .longBreak else { return }
        let delay = max(1, data.settings.pauseReminderMinutes)
        cancelPauseReminder()
        pauseReminderTask = Task {
            try? await Task.sleep(for: .seconds(delay * 60))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.pendingNextMode == mode else { return }
                self.notificationManager.schedulePauseReminderNotification(mode: mode)
            }
        }
    }

    private func cancelPauseReminder() {
        pauseReminderTask?.cancel()
        pauseReminderTask = nil
    }

    func stopTimer() {
        let stoppedMode = timerEngine.currentSnapshot.phase.activeMode
        sessionPausedBySleep = false
        notificationManager.cancelSessionEndNotification()
        cancelPauseReminder()
        timerEngine.stop()
        pendingNextMode = nil
        finalizeActiveBlockIfNeeded(endedAt: .now)
        statusMessage = "Minuteur arrêté"
        if data.settings.deepWorkEnabled, stoppedMode == .focus { runFocusShortcut(enabled: false) }
    }

    // MARK: - External focus (Sanctuaire)

    /// Signale qu'une session de concentration externe (Sanctuaire) est en cours.
    func setExternalFocusActive(_ active: Bool) {
        guard isExternalFocusActive != active else { return }
        isExternalFocusActive = active
    }

    /// Enregistre une session de concentration réalisée hors du minuteur Pomodoro (Sanctuaire).
    func recordExternalFocusSession(
        startedAt: Date,
        endedAt: Date,
        activeDuration: TimeInterval,
        plannedDuration: TimeInterval,
        note: String,
        completed: Bool
    ) {
        guard activeDuration >= 60 else { return }
        let session = appendSession(
            mode: .focus,
            startedAt: startedAt,
            endedAt: max(startedAt, endedAt),
            plannedDuration: plannedDuration,
            actualDuration: activeDuration,
            completionState: completed ? .completed : .interrupted,
            categoryID: selectedCategoryID,
            projectID: selectedProjectID
        )
        if let index = data.sessions.firstIndex(where: { $0.id == session.id }) {
            data.sessions[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        statusMessage = completed ? "Session Sanctuaire enregistrée" : "Session Sanctuaire interrompue enregistrée"
        scheduleSave()
    }

    // MARK: - Deep work (Concentration via l'app Raccourcis)

    /// Lance le raccourci configuré (app Raccourcis) qui active / désactive la Concentration.
    /// Aucun accès aux préférences système : sans raccourci configuré, ne fait rien.
    private func runFocusShortcut(enabled: Bool) {
        guard data.settings.deepWorkEnabled else { return }
        let rawName = enabled ? data.settings.focusShortcutOnName : data.settings.focusShortcutOffName
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        do {
            try process.run()
        } catch {
            statusMessage = "Raccourci « \(name) » impossible à lancer : \(error.localizedDescription)"
        }
    }

    // MARK: - Settings

    func saveSettings() {
        data.settings.updatedAt = .now
        timerEngine.updateSettings(data.settings)
        statusMessage = "Réglages mis à jour"
        scheduleSave()
    }

    // MARK: - Filters

    func clearFilters() {
        selectedCategoryID = nil
        selectedProjectID = nil
    }

    // MARK: - Statistics navigation

    func selectContributionDay(_ date: Date) {
        selectedJournalDate = date
        selectedSection = .journal
    }

    func clearJournalDateSelection() {
        selectedJournalDate = nil
    }

    func shiftStatisticsAnchor(by value: Int) {
        let component: Calendar.Component
        switch selectedRange {
        case .daily:
            component = .day
        case .weekly:
            component = .weekOfYear
        case .monthly:
            component = .month
        case .yearly:
            component = .year
        }
        statisticsAnchorDate = Calendar.current.date(byAdding: component, value: value, to: statisticsAnchorDate) ?? statisticsAnchorDate
    }

    func jumpStatisticsAnchorToToday() {
        statisticsAnchorDate = .now
    }

    func toggleFocusMode() {
        isFocusModeEnabled.toggle()
    }

    // MARK: - Categories

    func addCategory(named name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let category = PomodoroActivityCategory(
            id: UUID(),
            name: name,
            colorHex: randomColorHex(),
            createdAt: .now,
            updatedAt: .now
        )
        data.categories.append(category)
        data.updatedAt = .now
        scheduleSave()
    }

    func updateCategory(id: UUID, name: String) {
        guard let index = data.categories.firstIndex(where: { $0.id == id }) else { return }
        data.categories[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.categories[index].updatedAt = .now
        scheduleSave()
    }

    func deleteCategory(id: UUID) {
        data.categories.removeAll { $0.id == id }
        recordTombstone(id)
        for index in data.sessions.indices where data.sessions[index].categoryID == id {
            data.sessions[index].categoryID = nil
            data.sessions[index].updatedAt = .now
        }
        for index in data.goals.indices where data.goals[index].categoryID == id {
            data.goals[index].categoryID = nil
            data.goals[index].updatedAt = .now
        }
        if selectedCategoryID == id {
            selectedCategoryID = nil
        }
        scheduleSave()
    }

    // MARK: - Projects

    func addProject(name: String, detail: String, targetSessions: Int?, targetMinutes: Int?) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let project = PomodoroProjectRecord(
            id: UUID(),
            name: name,
            detail: detail,
            colorHex: randomColorHex(),
            targetSessionCount: targetSessions,
            targetMinutes: targetMinutes,
            createdAt: .now,
            updatedAt: .now
        )
        data.projects.append(project)
        data.updatedAt = .now
        scheduleSave()
    }

    func updateProject(id: UUID, name: String, detail: String, targetSessions: Int?, targetMinutes: Int?) {
        guard let index = data.projects.firstIndex(where: { $0.id == id }) else { return }
        data.projects[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.projects[index].detail = detail
        data.projects[index].targetSessionCount = targetSessions
        data.projects[index].targetMinutes = targetMinutes
        data.projects[index].updatedAt = .now
        scheduleSave()
    }

    func deleteProject(id: UUID) {
        data.projects.removeAll { $0.id == id }
        recordTombstone(id)
        for index in data.sessions.indices where data.sessions[index].projectID == id {
            data.sessions[index].projectID = nil
            data.sessions[index].updatedAt = .now
        }
        for index in data.goals.indices where data.goals[index].projectID == id {
            data.goals[index].projectID = nil
            data.goals[index].updatedAt = .now
        }
        if selectedProjectID == id {
            selectedProjectID = nil
        }
        scheduleSave()
    }

    // MARK: - Goals

    @discardableResult
    func addGoal(title: String, period: GoalPeriod, metric: GoalMetric, target: Int) -> String? {
        if let error = validateGoal(title: title, metric: metric, target: target) {
            goalValidationError = error
            return error
        }
        goalValidationError = nil
        data.goals.append(
            PomodoroGoalDefinition(
                id: UUID(),
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                period: period,
                metric: metric,
                target: target,
                categoryID: selectedCategoryID,
                projectID: selectedProjectID,
                createdAt: .now,
                updatedAt: .now
            )
        )
        scheduleSave()
        return nil
    }

    @discardableResult
    func updateGoal(id: UUID, title: String, period: GoalPeriod, metric: GoalMetric, target: Int) -> String? {
        guard let index = data.goals.firstIndex(where: { $0.id == id }) else { return nil }
        if let error = validateGoal(title: title, metric: metric, target: target) {
            goalValidationError = error
            return error
        }
        goalValidationError = nil
        data.goals[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        data.goals[index].period = period
        data.goals[index].metric = metric
        data.goals[index].target = target
        data.goals[index].updatedAt = .now
        scheduleSave()
        return nil
    }

    func clearGoalValidationError() {
        goalValidationError = nil
    }

    func deleteGoal(id: UUID) {
        data.goals.removeAll { $0.id == id }
        recordTombstone(id)
        scheduleSave()
    }

    private func validateGoal(title: String, metric: GoalMetric, target: Int) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Le titre de l'objectif ne peut pas être vide."
        }
        if target <= 0 {
            return "La cible doit être supérieure à 0."
        }
        let maxTarget: Int = metric == .minutes ? 1440 : 200
        if target > maxTarget {
            return metric == .minutes
                ? "La cible ne peut pas dépasser \(maxTarget) minutes par période."
                : "La cible ne peut pas dépasser \(maxTarget) sessions par période."
        }
        return nil
    }

    // MARK: - Sessions

    func saveNoteForLastCompletedSession() {
        guard let sessionID = pendingNoteSessionID,
              let index = data.sessions.firstIndex(where: { $0.id == sessionID }) else {
            isPresentingNoteEditor = false
            noteDraft = ""
            wordCountDraft = ""
            return
        }

        data.sessions[index].note = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        data.sessions[index].updatedAt = .now

        let trimmed = wordCountDraft
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{202F}", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        if let wordCount = Int(trimmed), wordCount > 0 {
            onSaveWordCount?(wordCount)
        }

        noteDraft = ""
        wordCountDraft = ""
        pendingNoteSessionID = nil
        isPresentingNoteEditor = false
        sessionWritingDelta = nil  // #43 — réinitialiser le delta
        scheduleSave()
    }

    func beginEditingSession(_ session: PomodoroSessionRecord) {
        editingSessionDraft = session
    }

    func cancelEditingSession() {
        editingSessionDraft = nil
    }

    func saveEditedSession(
        id: UUID,
        startedAt: Date,
        endedAt: Date,
        categoryID: UUID?,
        projectID: UUID?,
        note: String,
        completionState: SessionCompletionState
    ) {
        guard let index = data.sessions.firstIndex(where: { $0.id == id }) else { return }
        let safeEndedAt = max(endedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970)
        data.sessions[index].startedAt = startedAt
        data.sessions[index].endedAt = Date(timeIntervalSince1970: safeEndedAt)
        data.sessions[index].duration = max(60, data.sessions[index].endedAt.timeIntervalSince(startedAt))
        data.sessions[index].categoryID = categoryID
        data.sessions[index].projectID = projectID
        data.sessions[index].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        data.sessions[index].completionState = completionState
        data.sessions[index].updatedAt = .now
        rebuildWorkBlocks()
        editingSessionDraft = nil
        scheduleSave()
    }

    func deleteSession(id: UUID) {
        data.sessions.removeAll { $0.id == id }
        recordTombstone(id)
        rebuildWorkBlocks()
        if editingSessionDraft?.id == id {
            editingSessionDraft = nil
        }
        scheduleSave()
    }

    // MARK: - Export

    func exportJSON() {
        guard let url = savePanelURL(defaultName: "export-pomodoro.json") else { return }
        Task {
            guard let storeURL else { return }
            let _ = storeURL
            do {
                try await store.exportJSON(data, to: url)
                await MainActor.run { self.statusMessage = "JSON exporté" }
            } catch {
                await MainActor.run { self.statusMessage = "Échec de l'export : \(error.localizedDescription)" }
            }
        }
    }

    func exportCSV() {
        guard let url = savePanelURL(defaultName: "sessions-pomodoro.csv") else { return }
        Task {
            do {
                try await store.exportCSV(data, to: url)
                await MainActor.run { self.statusMessage = "CSV exporté" }
            } catch {
                await MainActor.run { self.statusMessage = "Échec de l'export : \(error.localizedDescription)" }
            }
        }
    }

    // MARK: - Helpers

    func categoryName(for id: UUID?) -> String {
        data.categories.first(where: { $0.id == id })?.name ?? "Aucune"
    }

    func projectName(for id: UUID?) -> String {
        data.projects.first(where: { $0.id == id })?.name ?? "Aucun"
    }

    func formattedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    // MARK: - Private helpers

    private func startMonitoring() {
        guard let storeURL else { return }
        monitor.start(url: storeURL) { [weak self] in
            Task { @MainActor in
                await self?.reloadFromDisk()
            }
        }
    }

    private func reloadFromDisk() async {
        guard let storeURL else { return }
        do {
            let disk = try await store.readDisk(from: storeURL)
            // Fusion APRÈS l'await, avec l'état mémoire courant : rien de ce qui a changé pendant la lecture n'est perdu
            let merged = PomodoroDataStore.merge(local: data, remote: disk)
            let becameWritable = !isStoreWritable
            if becameWritable {
                // Le fichier iCloud est enfin lisible : l'écriture redevient sûre (readDisk l'a réactivée côté store)
                isStoreWritable = true
                storageWarning = nil
            }
            if merged != data {
                data = merged
                timerEngine.updateSettings(merged.settings)
                statusMessage = "Données locales rechargées"
            }
            // Pas de sauvegarde systématique ici (sinon ping-pong entre les deux Mac) :
            // seulement pour écrire ce qui avait été bloqué pendant l'indisponibilité du fichier.
            if becameWritable && hasUnsavedChanges {
                scheduleSave()
            }
        } catch {
            statusMessage = "Échec du rechargement : \(error.localizedDescription)"
        }
    }

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        data.globalStatistics = PomodoroStatisticsEngine.globalSnapshot(for: data)
        data.updatedAt = .now
        hasUnsavedChanges = true

        pendingSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await persist()
        }
    }

    private func persist() async {
        guard let storeURL else { return }
        guard isStoreWritable else {
            statusMessage = storageWarning ?? "Enregistrement désactivé : fichier Pomodoro indisponible"
            return
        }
        let snapshot = data
        monitor.ignoreOwnWrites()
        do {
            let saved = try await store.save(snapshot, to: storeURL)
            monitor.ignoreOwnWrites()
            if data == snapshot {
                if saved != data { data = saved }
                hasUnsavedChanges = false
            } else {
                // `data` a changé pendant l'écriture : on fusionne au lieu d'écraser
                // (ces changements ont replanifié une sauvegarde).
                data = PomodoroDataStore.merge(local: data, remote: saved)
            }
            statusMessage = "Données enregistrées"
        } catch {
            statusMessage = "Échec de l'enregistrement : \(error.localizedDescription)"
        }
    }

    /// Pierre tombale : la suppression est propagée à l'autre Mac au lieu d'être annulée par la fusion.
    private func recordTombstone(_ id: UUID) {
        data.deletedIDs[id.uuidString] = .now
    }

    private func appendSession(
        mode: ActiveTimerMode,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        completionState: SessionCompletionState,
        categoryID: UUID?,
        projectID: UUID?
    ) -> PomodoroSessionRecord {
        let session = PomodoroSessionRecord(
            id: UUID(),
            startedAt: startedAt,
            endedAt: endedAt,
            duration: actualDuration,
            plannedDuration: plannedDuration,
            kind: mode.sessionKind,
            completionState: completionState,
            categoryID: categoryID,
            projectID: projectID,
            note: "",
            createdAt: .now,
            updatedAt: .now,
            writingProjectId: selectedWritingProjectId,
            writingChapterId: selectedWritingChapterId
        )
        data.sessions.append(session)
        data.updatedAt = .now
        return session
    }

    private func updateBlocksForCompletedFocus(session: PomodoroSessionRecord, nextMode: ActiveTimerMode?) {
        if activeBlockStartedAt == nil {
            activeBlockStartedAt = session.startedAt
        }
        activeBlockSessionIDs.append(session.id)
        if nextMode == .longBreak {
            finalizeActiveBlockIfNeeded(endedAt: session.endedAt)
        }
    }

    private func finalizeActiveBlockIfNeeded(endedAt: Date) {
        guard let startedAt = activeBlockStartedAt, let firstSessionID = activeBlockSessionIDs.first else { return }
        let focusSessions = data.sessions.filter { activeBlockSessionIDs.contains($0.id) }
        let blockID = PomodoroWorkBlockRecord.deterministicID(firstSessionID: firstSessionID)
        let block = PomodoroWorkBlockRecord(
            id: blockID,
            sessionIDs: activeBlockSessionIDs,
            startedAt: startedAt,
            endedAt: endedAt,
            focusSessionCount: focusSessions.count,
            totalFocusDuration: focusSessions.reduce(0) { $0 + $1.duration },
            createdAt: .now,
            updatedAt: .now
        )
        data.workBlocks.removeAll { $0.id == blockID }
        data.workBlocks.append(block)
        activeBlockSessionIDs = []
        activeBlockStartedAt = nil
    }

    private func rebuildWorkBlocks() {
        let completedFocusSessions = data.sessions.completedFocusOnly().sorted { $0.startedAt < $1.startedAt }
        let maxBreakGap: TimeInterval = TimeInterval(data.settings.workBlockMaxBreakMinutes) * 60
        var rebuilt: [PomodoroWorkBlockRecord] = []
        var buffer: [PomodoroSessionRecord] = []

        func flushBuffer() {
            guard let first = buffer.first, let last = buffer.last else { return }
            rebuilt.append(
                PomodoroWorkBlockRecord(
                    // ID déterministe : la même reconstruction sur l'autre Mac donne le même bloc
                    id: PomodoroWorkBlockRecord.deterministicID(firstSessionID: first.id),
                    sessionIDs: buffer.map(\.id),
                    startedAt: first.startedAt,
                    endedAt: last.endedAt,
                    focusSessionCount: buffer.count,
                    totalFocusDuration: buffer.reduce(0) { $0 + $1.duration },
                    createdAt: .now,
                    updatedAt: .now
                )
            )
            buffer.removeAll()
        }

        for session in completedFocusSessions {
            if let previous = buffer.last,
               session.startedAt.timeIntervalSince(previous.endedAt) > maxBreakGap {
                flushBuffer()
            }
            buffer.append(session)
        }
        flushBuffer()
        // La reconstruction locale fait foi : les anciens blocs disparus reçoivent une pierre tombale
        let rebuiltIDs = Set(rebuilt.map(\.id))
        for block in data.workBlocks where !rebuiltIDs.contains(block.id) {
            recordTombstone(block.id)
        }
        data.workBlocks = rebuilt
    }

    private func randomColorHex() -> String {
        let palette = ["#B45309", "#1D4ED8", "#0F766E", "#BE123C", "#6D28D9", "#475569"]
        return palette.randomElement() ?? "#1D4ED8"
    }

    private func savePanelURL(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Timer delegate

// Le moteur tourne sur le main thread et appelle son délégué de façon synchrone :
// `assumeIsolated` évite le saut asynchrone (et l'état intermédiaire incohérent) de l'ancien `Task { @MainActor }`.
extension PomodoroAppController: PomodoroTimerEngineDelegate {
    nonisolated func timerEngine(_ engine: PomodoroTimerEngine, didUpdate snapshot: PomodoroTimerSnapshot) {
        MainActor.assumeIsolated {
            self.timerSnapshot = snapshot
        }
    }

    nonisolated func timerEngine(
        _ engine: PomodoroTimerEngine,
        didFinish mode: ActiveTimerMode,
        nextMode: ActiveTimerMode?,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        categoryID: UUID?,
        projectID: UUID?
    ) {
        MainActor.assumeIsolated {
            let session = self.appendSession(
                mode: mode,
                startedAt: startedAt,
                endedAt: endedAt,
                plannedDuration: plannedDuration,
                actualDuration: actualDuration,
                completionState: .completed,
                categoryID: categoryID,
                projectID: projectID
            )
            if mode == .focus {
                self.pendingNoteSessionID = session.id
                self.isPresentingNoteEditor = true
                self.updateBlocksForCompletedFocus(session: session, nextMode: nextMode)
                self.focusSessionJustCompleted = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(900))
                    self.focusSessionJustCompleted = false
                }
                if self.data.settings.deepWorkEnabled { self.runFocusShortcut(enabled: false) }
            }
            self.pendingNextMode = nextMode
            if let nextMode, (nextMode == .shortBreak || nextMode == .longBreak) {
                self.schedulePauseReminder(for: nextMode)
            }
            // Un seul son : celui de l'app (la notification de fin, planifiée à l'avance, est silencieuse)
            let sound = PomodoroSoundManager.sound(for: mode, settings: self.data.settings)
            self.soundManager.play(sound, volume: self.data.settings.soundVolume)
            self.scheduleSave()
        }
    }

    nonisolated func timerEngine(
        _ engine: PomodoroTimerEngine,
        didInterrupt mode: ActiveTimerMode,
        startedAt: Date,
        endedAt: Date,
        plannedDuration: TimeInterval,
        actualDuration: TimeInterval,
        categoryID: UUID?,
        projectID: UUID?
    ) {
        MainActor.assumeIsolated {
            _ = self.appendSession(
                mode: mode,
                startedAt: startedAt,
                endedAt: endedAt,
                plannedDuration: plannedDuration,
                actualDuration: actualDuration,
                completionState: .interrupted,
                categoryID: categoryID,
                projectID: projectID
            )
            self.finalizeActiveBlockIfNeeded(endedAt: endedAt)
            self.scheduleSave()
        }
    }
}
