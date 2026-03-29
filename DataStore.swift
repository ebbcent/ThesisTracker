import SwiftUI
import Combine

// MARK: - Undo entry

struct UndoEntry {
    let projectId: UUID
    let chapterId: UUID
    let date: String
    let oldValue: Int
    let newValue: Int
}

class DataStore: ObservableObject {
    @Published var data: AppData = AppData()
    @Published var isUsingICloud: Bool = false
    @Published var showSaveIndicator: Bool = false

    // Undo / Redo
    private(set) var undoStack: [UndoEntry] = []
    private(set) var redoStack: [UndoEntry] = []
    @Published var canUndo: Bool = false
    @Published var canRedo: Bool = false

    // Daily summary
    @Published var showDailySummary: Bool = false
    private var lastSummaryDate: String {
        get { UserDefaults.standard.string(forKey: "lastSummaryDate") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastSummaryDate") }
    }

    // Weekly summary
    @Published var showWeeklySummary: Bool = false
    private var lastWeeklySummaryWeek: String {
        get { UserDefaults.standard.string(forKey: "lastWeeklySummaryWeek") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastWeeklySummaryWeek") }
    }

    private var fileWatcher: DispatchSourceFileSystemObject?
    private var lastSnapshotSignature: String?
    private let appStorageName = "Writing Process"
    private let legacyStorageNames = ["Writing Process", "WritingTracker", "ThesisTracker"]

    private static let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let frenchLongDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter
    }()

    private static let frenchDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter
    }()

    private static let frenchMonthYearFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "MMM yyyy"
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        return formatter
    }()

    // MARK: - File URLs

    private var iCloudDriveFileURL: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: iCloudRoot.path) else { return nil }
        let appDir = iCloudRoot.appendingPathComponent(appStorageName)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("data.json")
    }

    private var localFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(appStorageName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    private var snapshotsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(appStorageName).appendingPathComponent("Snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var legacyICloudFileURLs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let iCloudRoot = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: iCloudRoot.path) else { return [] }
        return legacyStorageNames
            .filter { $0 != appStorageName }
            .map { iCloudRoot.appendingPathComponent($0).appendingPathComponent("data.json") }
    }

    private var legacyLocalFileURLs: [URL] {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return legacyStorageNames
            .filter { $0 != appStorageName }
            .map { appSupport.appendingPathComponent($0).appendingPathComponent("data.json") }
    }

    private var activeFileURL: URL {
        iCloudDriveFileURL ?? localFileURL
    }

    // MARK: - Init

    init() {
        isUsingICloud = iCloudDriveFileURL != nil
        migrateToICloudIfNeeded()
        load()
        startWatchingFile()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    // MARK: - Migration locale → iCloud Drive

    private func migrateToICloudIfNeeded() {
        guard let iCloudFile = iCloudDriveFileURL else { return }
        guard !FileManager.default.fileExists(atPath: iCloudFile.path) else { return }
        let candidates = [localFileURL] + legacyICloudFileURLs + legacyLocalFileURLs
        guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return }
        try? FileManager.default.createDirectory(at: iCloudFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: source, to: iCloudFile)
    }

    // MARK: - Load

    func load() {
        guard let jsonData = try? Data(contentsOf: activeFileURL),
              var decoded = try? JSONDecoder().decode(AppData.self, from: jsonData) else { return }
        // Migration ancien format (chapitres au niveau racine)
        if decoded.projects.isEmpty, let old = decoded.legacyChapters, !old.isEmpty {
            var project = Project(name: "Ma thèse")
            project.chapters = old
            project.activeChapterId = decoded.legacyActiveChapterId
            decoded.projects = [project]
            decoded.activeProjectId = project.id
        }
        DispatchQueue.main.async { self.data = decoded }
    }

    // MARK: - Save

    func save() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        try? encoded.write(to: activeFileURL, options: .atomic)
        saveSnapshotIfNeeded(for: encoded)
        showSaveIndicator = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.showSaveIndicator = false
        }
        NotificationManager.shared.scheduleDeadlineNotifications(chaptersWithDeadlines: chaptersWithDeadlines)
        checkAndShowDailySummary()
        checkAndShowWeeklySummary()
        checkNewBadgeUnlocks()
    }

    private func saveSnapshotIfNeeded(for encoded: Data) {
        let signature = "\(encoded.count)-\(encoded.hashValue)"
        guard signature != lastSnapshotSignature else { return }
        lastSnapshotSignature = signature

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = snapshotsDirectoryURL.appendingPathComponent("snapshot-\(timestamp).json")
        try? encoded.write(to: url, options: .atomic)

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
        for oldURL in sorted.dropFirst(30) {
            try? FileManager.default.removeItem(at: oldURL)
        }
    }

    // MARK: - File watcher

    private func startWatchingFile() {
        let dirURL = activeFileURL.deletingLastPathComponent()
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.load()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcher = source
    }

    @objc private func appDidBecomeActive() {
        load()
        checkAndShowDailySummary()
        checkAndShowWeeklySummary()
    }

    // MARK: - Date helpers

    nonisolated static var today: String {
        storageDateFormatter.string(from: Date())
    }

    nonisolated static func dateString(from date: Date) -> String {
        storageDateFormatter.string(from: date)
    }

    nonisolated static func parseDate(_ dateString: String) -> Date? {
        storageDateFormatter.date(from: dateString)
    }

    nonisolated static func formatLongDate(_ date: Date, capitalize: Bool = false) -> String {
        let value = frenchLongDateFormatter.string(from: date)
        return capitalize ? value.prefix(1).uppercased() + value.dropFirst() : value
    }

    nonisolated static func formatDate(_ date: Date) -> String {
        frenchDateFormatter.string(from: date)
    }

    nonisolated static func formatMonthYear(_ date: Date) -> String {
        frenchMonthYearFormatter.string(from: date)
    }

    nonisolated static func formatNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    func formatCount(_ value: Int) -> String {
        if data.useWordCount {
            return DataStore.formatNumber(value / 5) + " mots"
        }
        return DataStore.formatNumber(value) + " car."
    }

    func formatCountShort(_ value: Int) -> String {
        if data.useWordCount {
            return DataStore.formatNumber(value / 5) + " m."
        }
        return DataStore.formatNumber(value) + " car."
    }

    // MARK: - Active selectors

    var activeProject: Project? {
        guard let id = data.activeProjectId else { return nil }
        return data.projects.first(where: { $0.id == id })
    }

    var activeProjectIndex: Int? {
        guard let id = data.activeProjectId else { return nil }
        return data.projects.firstIndex(where: { $0.id == id })
    }

    var activeChapter: Chapter? {
        guard let project = activeProject,
              let id = project.activeChapterId else { return nil }
        return project.chapters.first(where: { $0.id == id })
    }

    // MARK: - Sorting helpers

    func sortedProjects(_ projects: [Project]) -> [Project] {
        data.sortProjectsAlphabetically
            ? projects.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            : projects
    }

    func sortedChapters(_ chapters: [Chapter]) -> [Chapter] {
        data.sortChaptersAlphabetically
            ? chapters.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            : chapters
    }

    // MARK: - Progress

    private var allChapters: [Chapter] {
        data.projects.flatMap { $0.chapters }
    }

    private func chapters(projectId: UUID? = nil, chapterId: UUID? = nil) -> [Chapter] {
        if let projectId {
            guard let project = data.projects.first(where: { $0.id == projectId }) else { return [] }
            if let chapterId {
                return project.chapters.filter { $0.id == chapterId }
            }
            return project.chapters
        }
        if let chapterId {
            return allChapters.filter { $0.id == chapterId }
        }
        return allChapters
    }

    func dailyTotals(projectId: UUID? = nil, chapterId: UUID? = nil) -> [String: Int] {
        var totals: [String: Int] = [:]
        for chapter in chapters(projectId: projectId, chapterId: chapterId) {
            var previousTotal = 0
            for entry in chapter.entries.sorted(by: { $0.date < $1.date }) {
                let increment = max(0, entry.totalCount - previousTotal)
                if increment > 0 {
                    totals[entry.date, default: 0] += increment
                }
                previousTotal = entry.totalCount
            }
        }
        return totals
    }

    var dailyProgress: Int {
        dailyTotals()[DataStore.today] ?? 0
    }

    var weeklyProgress: Int {
        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar; cal.firstWeekday = 2
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let totals = dailyTotals()
        var total = 0; var current = weekStart
        while current <= now {
            let dateStr = DataStore.dateString(from: current)
            total += totals[dateStr] ?? 0
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? now + 1
        }
        return total
    }

    var monthlyProgress: Int {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let totals = dailyTotals()
        var total = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            let dateStr = DataStore.dateString(from: date)
            total += totals[dateStr] ?? 0
        }
        return total
    }

    var chapterProgress: Int {
        guard let chapter = activeChapter else { return 0 }
        return chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
    }

    // MARK: - Entry mutations

    func setTotalForDate(_ count: Int, for chapterId: UUID, in projectId: UUID, date: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let oldValue = data.projects[projIdx].chapters[chapIdx].entries.first(where: { $0.date == date })?.totalCount ?? 0
        let entry = UndoEntry(projectId: projectId, chapterId: chapterId, date: date, oldValue: oldValue, newValue: count)
        undoStack.append(entry)
        redoStack.removeAll()
        canUndo = true; canRedo = false
        if undoStack.count > 50 { undoStack.removeFirst() }
        let currentHour = Calendar.current.component(.hour, from: Date())
        if let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) {
            data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount = count
            if data.projects[projIdx].chapters[chapIdx].entries[entryIdx].savedAtHour == nil {
                data.projects[projIdx].chapters[chapIdx].entries[entryIdx].savedAtHour = currentHour
            }
        } else {
            var entry = DailyEntry(date: date, totalCount: count)
            entry.savedAtHour = currentHour
            data.projects[projIdx].chapters[chapIdx].entries.append(entry)
        }
        save()
    }

    func setNoteForDate(_ note: String, for chapterId: UUID, in projectId: UUID, date: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) {
            data.projects[projIdx].chapters[chapIdx].entries[entryIdx].note = trimmed.isEmpty ? nil : trimmed
        }
        save()
    }

    func deleteEntry(for chapterId: UUID, in projectId: UUID, date: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].entries.removeAll { $0.date == date }
        save()
    }

    // MARK: - Project mutations

    func addProject(name: String) {
        let project = Project(name: name)
        data.projects.append(project)
        if data.activeProjectId == nil { data.activeProjectId = project.id }
        save()
    }

    func deleteProject(at offsets: IndexSet) {
        let removedIds = offsets.map { data.projects[$0].id }
        data.projects.remove(atOffsets: offsets)
        if let activeId = data.activeProjectId, removedIds.contains(activeId) {
            data.activeProjectId = data.projects.first?.id
        }
        // Remove from folders
        for id in removedIds {
            for i in data.folders.indices {
                data.folders[i].projectIds.removeAll { $0 == id }
            }
        }
        save()
    }

    func deleteProject(id: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == id }) else { return }
        deleteProject(at: IndexSet([idx]))
    }

    func updateProject(_ project: Project) {
        guard let idx = data.projects.firstIndex(where: { $0.id == project.id }) else { return }
        data.projects[idx] = project
        save()
    }

    func setProjectTag(_ tag: ProjectTag?, for projectId: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[idx].tag = tag
        save()
    }

    func moveProject(_ projectId: UUID, toFolder folderId: UUID?) {
        // Remove from all folders
        for i in data.folders.indices {
            data.folders[i].projectIds.removeAll { $0 == projectId }
        }
        // Update project's folderId
        if let idx = data.projects.firstIndex(where: { $0.id == projectId }) {
            data.projects[idx].folderId = folderId
        }
        // Add to new folder
        if let folderId = folderId,
           let folderIdx = data.folders.firstIndex(where: { $0.id == folderId }) {
            if !data.folders[folderIdx].projectIds.contains(projectId) {
                data.folders[folderIdx].projectIds.append(projectId)
            }
        }
        save()
    }

    // MARK: - Folder mutations

    func addFolder(name: String) {
        let folder = ProjectFolder(name: name)
        data.folders.append(folder)
        save()
    }

    func deleteFolder(id: UUID, keepProjects: Bool = true) {
        if keepProjects {
            // Move projects back to ungrouped
            if let folder = data.folders.first(where: { $0.id == id }) {
                for projId in folder.projectIds {
                    if let idx = data.projects.firstIndex(where: { $0.id == projId }) {
                        data.projects[idx].folderId = nil
                    }
                }
            }
        }
        data.folders.removeAll { $0.id == id }
        save()
    }

    func updateFolder(_ folder: ProjectFolder) {
        guard let idx = data.folders.firstIndex(where: { $0.id == folder.id }) else { return }
        data.folders[idx] = folder
        save()
    }

    func toggleFolderExpanded(_ folderId: UUID) {
        guard let idx = data.folders.firstIndex(where: { $0.id == folderId }) else { return }
        data.folders[idx].isExpanded.toggle()
        save()
    }

    // MARK: - Chapter mutations

    func addChapter(name: String, goal: Int, deadline: String? = nil, notes: String? = nil, to projectId: UUID, chapterFolderId: UUID? = nil) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        var chapter = Chapter(name: name, goal: goal, deadline: deadline)
        chapter.notes = notes
        chapter.chapterFolderId = chapterFolderId
        data.projects[projIdx].chapters.append(chapter)
        if data.projects[projIdx].activeChapterId == nil {
            data.projects[projIdx].activeChapterId = chapter.id
        }
        save()
    }

    // MARK: - Chapter folder mutations

    func addChapterFolder(name: String, to projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[projIdx].chapterFolders.append(ChapterFolder(name: name))
        save()
    }

    func deleteChapterFolder(id folderId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        for chapIdx in data.projects[projIdx].chapters.indices {
            if data.projects[projIdx].chapters[chapIdx].chapterFolderId == folderId {
                data.projects[projIdx].chapters[chapIdx].chapterFolderId = nil
            }
        }
        data.projects[projIdx].chapterFolders.removeAll { $0.id == folderId }
        save()
    }

    func renameChapterFolder(_ folderId: UUID, newName: String, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let folderIdx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == folderId }) else { return }
        data.projects[projIdx].chapterFolders[folderIdx].name = newName
        save()
    }

    func toggleChapterFolderExpanded(_ folderId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let folderIdx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == folderId }) else { return }
        data.projects[projIdx].chapterFolders[folderIdx].isExpanded.toggle()
        save()
    }

    func moveChapterToFolder(_ chapterId: UUID, folderId: UUID?, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].chapterFolderId = folderId
        save()
    }

    func deleteChapter(at offsets: IndexSet, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let removedIds = offsets.map { data.projects[projIdx].chapters[$0].id }
        data.projects[projIdx].chapters.remove(atOffsets: offsets)
        if let activeId = data.projects[projIdx].activeChapterId, removedIds.contains(activeId) {
            data.projects[projIdx].activeChapterId = data.projects[projIdx].chapters.first?.id
        }
        save()
    }

    /// Supprime un chapitre et toutes ses entrées
    func deleteChapterById(_ chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        deleteChapter(at: IndexSet([chapIdx]), in: projectId)
    }

    func setChapterTag(_ tag: ProjectTag?, for chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].tag = tag
        save()
    }

    func toggleChapterComplete(_ chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].isCompleted.toggle()
        save()
    }

    // V3.2 — Statut de chapitre
    func setChapterStatus(_ status: ChapterStatus?, for chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].status = status
        if status == .termine {
            data.projects[projIdx].chapters[chapIdx].isCompleted = true
        } else if status != nil && status != .termine {
            data.projects[projIdx].chapters[chapIdx].isCompleted = false
        }
        save()
    }

    /// Déplace un chapitre juste avant targetId dans le même projet
    func moveChapterById(_ sourceId: UUID, before targetId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              sourceId != targetId else { return }
        guard let fromIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == sourceId }) else { return }
        let chapter = data.projects[projIdx].chapters.remove(at: fromIdx)
        let insertIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == targetId })
                        ?? data.projects[projIdx].chapters.count
        data.projects[projIdx].chapters.insert(chapter, at: insertIdx)
        save()
    }

    /// Déplace un chapitre à la fin
    func moveChapterToEnd(_ sourceId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let fromIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == sourceId }) else { return }
        let chapter = data.projects[projIdx].chapters.remove(at: fromIdx)
        data.projects[projIdx].chapters.append(chapter)
        save()
    }

    /// Déplace un projet juste avant targetId
    func moveProjectById(_ sourceId: UUID, before targetId: UUID) {
        guard sourceId != targetId,
              let fromIdx = data.projects.firstIndex(where: { $0.id == sourceId }) else { return }
        let project = data.projects.remove(at: fromIdx)
        let insertIdx = data.projects.firstIndex(where: { $0.id == targetId }) ?? data.projects.count
        data.projects.insert(project, at: insertIdx)
        save()
    }

    /// Déplace un projet à la fin
    func moveProjectToEnd(_ sourceId: UUID) {
        guard let fromIdx = data.projects.firstIndex(where: { $0.id == sourceId }) else { return }
        let project = data.projects.remove(at: fromIdx)
        data.projects.append(project)
        save()
    }

    func updateChapter(_ chapter: Chapter, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapter.id }) else { return }
        data.projects[projIdx].chapters[chapIdx] = chapter
        save()
    }

    // MARK: - Helpers

    func latestTotal(for chapterId: UUID, in projectId: UUID) -> Int {
        guard let project = data.projects.first(where: { $0.id == projectId }),
              let chapter = project.chapters.first(where: { $0.id == chapterId }) else { return 0 }
        return chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
    }

    func statusColor(for chapterId: UUID, in projectId: UUID, goal: Int) -> Color {
        guard goal > 0 else { return .gray }
        let ratio = Double(latestTotal(for: chapterId, in: projectId)) / Double(goal)
        if ratio >= 1.0  { return Color(red: 0.196, green: 0.784, blue: 0.549) }
        if ratio >= 0.66 { return Color(red: 0.961, green: 0.620, blue: 0.043) }
        if ratio >= 0.33 { return Color(red: 0.929, green: 0.435, blue: 0.114) }
        return Color(red: 0.929, green: 0.329, blue: 0.329)
    }


    /// Projection de fin de chapitre basée sur la moyenne des `lookbackDays` derniers jours
    /// Retourne nil si le chapitre est terminé ou si aucun progrès récent
    func estimatedCompletionDate(for chapterId: UUID, in projectId: UUID, lookbackDays: Int = 14) -> Date? {
        guard let project = data.projects.first(where: { $0.id == projectId }),
              let chapter = project.chapters.first(where: { $0.id == chapterId }) else { return nil }

        let latest = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
        let goal   = chapter.goal
        guard goal > 0, latest < goal else { return nil }
        let remaining = goal - latest

        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        var dailyIncrements: [Int] = []
        for offset in 1...lookbackDays {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let inc = chapter.increment(for: DataStore.dateString(from: date))
            if inc > 0 { dailyIncrements.append(inc) }
        }
        guard !dailyIncrements.isEmpty else { return nil }
        let avgPerDay = dailyIncrements.reduce(0, +) / dailyIncrements.count
        guard avgPerDay > 0 else { return nil }

        let daysNeeded = Int(ceil(Double(remaining) / Double(avgPerDay)))
        return cal.date(byAdding: .day, value: daysNeeded, to: today)
    }

    func estimatedCompletionDate(for projectId: UUID, lookbackDays: Int = 14) -> Date? {
        guard let project = data.projects.first(where: { $0.id == projectId }) else { return nil }
        let chapters = project.chapters.filter { !$0.isCompleted && $0.goal > 0 }
        guard !chapters.isEmpty else { return nil }

        let remaining = chapters.reduce(0) { total, chapter in
            let latest = chapter.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
            return total + max(0, chapter.goal - latest)
        }
        guard remaining > 0 else { return nil }

        let cal = Calendar(identifier: .gregorian)
        let today = Date()
        var increments: [Int] = []
        for offset in 1...lookbackDays {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = DataStore.dateString(from: date)
            let total = chapters.reduce(0) { $0 + $1.increment(for: dateStr) }
            if total > 0 { increments.append(total) }
        }
        guard !increments.isEmpty else { return nil }
        let avgPerDay = increments.reduce(0, +) / increments.count
        guard avgPerDay > 0 else { return nil }

        let daysNeeded = Int(ceil(Double(remaining) / Double(avgPerDay)))
        return cal.date(byAdding: .day, value: daysNeeded, to: today)
    }

    // MARK: - Streaks

    /// Jours consécutifs d'écriture (en partant d'aujourd'hui, ou d'hier si aujourd'hui est vide)
    var currentStreak: Int {
        let cal = Calendar(identifier: .gregorian)
        let totals = dailyTotals()
        let todayStr = DataStore.today
        let todayTotal = totals[todayStr] ?? 0
        let startOffset = todayTotal > 0 ? 0 : 1   // si rien aujourd'hui, on part d'hier
        var streak = 0
        var offset = startOffset
        while offset < 730 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let dateStr = DataStore.dateString(from: date)
            let total = totals[dateStr] ?? 0
            if total > 0 { streak += 1; offset += 1 }
            else { break }
        }
        return streak
    }

    /// Meilleure série de jours consécutifs de toute l'histoire
    var longestStreak: Int {
        var daysWithWriting = Set<String>()
        for project in data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    if chapter.increment(for: entry.date) > 0 { daysWithWriting.insert(entry.date) }
                }
            }
        }
        let sorted = daysWithWriting.sorted()
        guard !sorted.isEmpty else { return 0 }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let cal = Calendar(identifier: .gregorian)
        var longest = 1, current = 1
        for i in 1..<sorted.count {
            guard let prev = fmt.date(from: sorted[i-1]), let curr = fmt.date(from: sorted[i]) else { continue }
            let diff = cal.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 { current += 1; if current > longest { longest = current } }
            else { current = 1 }
        }
        return longest
    }

    // MARK: - Momentum score (0-100)

    /// Régularité 40% + Objectif 35% + Streak 25%
    var momentumScore: Int {
        let cal = Calendar(identifier: .gregorian)
        let totals = dailyTotals()
        var activeDays = 0
        var goalDays = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else { continue }
            let val = totals[DataStore.dateString(from: date)] ?? 0
            if val > 0 { activeDays += 1 }
            if data.dailyGoal > 0 && val >= data.dailyGoal { goalDays += 1 }
        }
        let regularite = Double(activeDays) / 30.0 * 100.0
        let objectif: Double = data.dailyGoal > 0
            ? Double(goalDays) / 30.0 * 100.0
            : regularite
        let streak = min(100.0, Double(currentStreak) * 3.0)
        return Int(regularite * 0.40 + objectif * 0.35 + streak * 0.25)
    }

    // Date range helper for "Tout" period in charts
    var earliestEntryDate: Date {
        let allDates = data.projects.flatMap { $0.chapters }.flatMap { $0.entries }
            .compactMap { DataStore.parseDate($0.date) }
        return allDates.min() ?? Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    }

    // MARK: - Adaptive daily goal

    /// Objectif journalier recalculé pour rattraper le retard sur l'objectif hebdomadaire
    var adaptedDailyGoal: Int {
        guard data.weeklyGoal > 0 else { return data.dailyGoal }
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now) else { return data.dailyGoal }
        let weekEnd = interval.end
        let remainingDays = max(1, cal.dateComponents([.day], from: now, to: weekEnd).day ?? 1)
        let remaining = max(0, data.weeklyGoal - weeklyProgress)
        return Int(ceil(Double(remaining) / Double(remainingDays)))
    }

    var adaptedDailyGoalDiffers: Bool {
        guard data.dailyGoal > 0 else { return false }
        let diff = abs(adaptedDailyGoal - data.dailyGoal)
        return diff > data.dailyGoal / 10   // > 10% de différence
    }

    // MARK: - V3.3 Daily session

    /// Caractères écrits la veille (tous chapitres confondus)
    var yesterdayProgress: Int {
        let cal = Calendar(identifier: .gregorian)
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        return dailyTotals()[DataStore.dateString(from: yesterday)] ?? 0
    }

    /// Rattrapage partiel si la veille était vide et qu'un objectif journalier est défini
    /// (50 % du manqué — uniquement quand l'objectif hebdo n'est pas actif)
    var catchUpAmount: Int {
        guard data.dailyGoal > 0, data.weeklyGoal == 0 else { return 0 }
        let missed = max(0, data.dailyGoal - yesterdayProgress)
        return Int(Double(missed) * 0.5)
    }

    /// Objectif intelligent pour aujourd'hui :
    /// — hebdo défini → adaptedDailyGoal (intègre déjà le rattrapage hebdo)
    /// — sinon         → dailyGoal + 50 % du manqué d'hier
    var todaySmartGoal: Int {
        if data.weeklyGoal > 0 { return adaptedDailyGoal }
        if data.dailyGoal > 0  { return data.dailyGoal + catchUpAmount }
        return 0
    }

    // MARK: - V3.4 Stats enrichies & Projection

    /// Somme des caractères restants pour tous les chapitres non terminés avec objectif défini
    var thesisRemainingChars: Int {
        data.projects.flatMap { $0.chapters }.reduce(0) { sum, ch in
            guard !ch.isCompleted, ch.goal > 0 else { return sum }
            let latest = ch.entries.sorted { $0.date > $1.date }.first?.totalCount ?? 0
            return sum + max(0, ch.goal - latest)
        }
    }

    /// Vitesse journalière moyenne sur les 14 derniers jours actifs (tous projets)
    var velocity14Days: Int {
        let cal = Calendar(identifier: .gregorian)
        var increments: [Int] = []
        for offset in 1...14 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let total = dailyTotals()[DataStore.dateString(from: date)] ?? 0
            if total > 0 { increments.append(total) }
        }
        guard !increments.isEmpty else { return 0 }
        return increments.reduce(0, +) / increments.count
    }

    /// Jours estimés pour terminer toute la thèse à la cadence actuelle
    var thesisProjectedDays: Int? {
        let remaining = thesisRemainingChars
        let vel = velocity14Days
        guard vel > 0 else { return nil }
        if remaining <= 0 { return 0 }
        return Int(ceil(Double(remaining) / Double(vel)))
    }

    /// Tous les mois depuis le premier écrit jusqu'à aujourd'hui (scroll horizontal)
    var allMonthlyStats: [(label: String, chars: Int)] {
        let cal    = Calendar(identifier: .gregorian)
        let totals = dailyTotals()
        guard let earliest  = totals.keys.filter({ (totals[$0] ?? 0) > 0 }).min(),
              let firstDate  = DataStore.parseDate(earliest),
              let firstMonth = cal.date(from: cal.dateComponents([.year, .month], from: firstDate))
        else { return [] }

        let fmt = DateFormatter()
        fmt.locale     = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMM yy"

        var results: [(String, Int)] = []
        var cursor = firstMonth
        let now    = Date()
        while cursor <= now {
            let comps = cal.dateComponents([.year, .month], from: cursor)
            let chars = totals.reduce(0) { acc, pair in
                guard let d = DataStore.parseDate(pair.key),
                      cal.component(.year,  from: d) == comps.year,
                      cal.component(.month, from: d) == comps.month else { return acc }
                return acc + pair.value
            }
            results.append((fmt.string(from: cursor).capitalized, chars))
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return results
    }

    /// Totaux par mois sur les 6 derniers mois, ordre chronologique (oldest → newest)
    var last6MonthsStats: [(label: String, chars: Int)] {
        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "MMM"
        let totals = dailyTotals()
        return (0..<6).reversed().compactMap { offset -> (String, Int)? in
            guard let date = cal.date(byAdding: .month, value: -offset, to: Date()) else { return nil }
            let comps = cal.dateComponents([.year, .month], from: date)
            let chars = totals.reduce(0) { acc, pair in
                guard let d = DataStore.parseDate(pair.key),
                      cal.component(.year,  from: d) == comps.year,
                      cal.component(.month, from: d) == comps.month else { return acc }
                return acc + pair.value
            }
            return (fmt.string(from: date).capitalized, chars)
        }
    }

    /// Moyenne de caractères par jour de semaine (0 = Lun … 6 = Dim), toute l'histoire
    var weekdayAverages: [(day: String, avg: Int)] {
        let frenchDays = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        var byWeekday: [Int: [Int]] = [:]
        for (dateStr, val) in dailyTotals() where val > 0 {
            guard let date = DataStore.parseDate(dateStr) else { continue }
            let wd  = cal.component(.weekday, from: date) // 1=Sun 2=Mon … 7=Sat
            let idx = (wd + 5) % 7                        // 0=Mon … 6=Sun
            byWeekday[idx, default: []].append(val)
        }
        return (0..<7).map { idx in
            let values = byWeekday[idx] ?? []
            let avg = values.isEmpty ? 0 : values.reduce(0, +) / values.count
            return (frenchDays[idx], avg)
        }
    }

    /// Meilleure semaine de toute l'histoire
    var bestWeekStat: (label: String, chars: Int)? {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        var byWeek: [String: Int] = [:]
        for (dateStr, val) in dailyTotals() where val > 0 {
            guard let date = DataStore.parseDate(dateStr),
                  let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            byWeek[DataStore.dateString(from: weekStart), default: 0] += val
        }
        guard let best = byWeek.max(by: { $0.value < $1.value }),
              let startDate = DataStore.parseDate(best.key) else { return nil }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "fr_FR")
        fmt.dateFormat = "d MMM yyyy"
        return ("Sem. du \(fmt.string(from: startDate))", best.value)
    }

    /// Objectif journalier calculé d'après le deadline du chapitre actif (si défini)
    var deadlineDailyGoal: Int? {
        guard let chapter = activeChapter,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr),
              chapter.goal > 0 else { return nil }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let deadlineDay = cal.startOfDay(for: deadline)
        let daysRemaining = max(1, cal.dateComponents([.day], from: today, to: deadlineDay).day ?? 1)
        let currentTotal = latestTotal(for: chapter.id, in: activeProject?.id ?? UUID())
        let remaining = max(0, chapter.goal - currentTotal)
        guard remaining > 0 else { return 0 }
        return Int(ceil(Double(remaining) / Double(daysRemaining)))
    }

    var deadlineDailyGoalDiffers: Bool {
        guard let ddg = deadlineDailyGoal, data.dailyGoal > 0 else { return false }
        return abs(ddg - data.dailyGoal) > data.dailyGoal / 10
    }

    // MARK: - Undo / Redo

    func undo() {
        guard let entry = undoStack.popLast() else { return }
        redoStack.append(entry)
        applyEntryValue(entry.oldValue, chapterId: entry.chapterId, projectId: entry.projectId, date: entry.date)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func redo() {
        guard let entry = redoStack.popLast() else { return }
        undoStack.append(entry)
        applyEntryValue(entry.newValue, chapterId: entry.chapterId, projectId: entry.projectId, date: entry.date)
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    private func applyEntryValue(_ value: Int, chapterId: UUID, projectId: UUID, date: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        if value == 0 {
            data.projects[projIdx].chapters[chapIdx].entries.removeAll { $0.date == date }
        } else if let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) {
            data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount = value
        } else {
            data.projects[projIdx].chapters[chapIdx].entries.append(DailyEntry(date: date, totalCount: value))
        }
        save()
    }

    // MARK: - Daily summary

    var todayStats: (chars: Int, projects: Int, topProject: String?) {
        let today = DataStore.today
        var totalChars = 0
        var projectsWritten = 0
        var topProject: String? = nil
        var topCount = 0
        for project in data.projects {
            let totals = dailyTotals(projectId: project.id)
            let count = totals[today] ?? 0
            if count > 0 {
                totalChars += count
                projectsWritten += 1
                if count > topCount { topCount = count; topProject = project.name }
            }
        }
        return (totalChars, projectsWritten, topProject)
    }

    func checkAndShowDailySummary() {
        let today = DataStore.today
        guard lastSummaryDate != today else { return }
        let stats = todayStats
        guard stats.chars > 0 else { return }
        let hour = Calendar.current.component(.hour, from: Date())
        guard hour >= 19 else { return }      // Ne montrer qu'après 19h
        lastSummaryDate = today
        showDailySummary = true
        NotificationManager.shared.scheduleDailySummaryNotification(
            chars: stats.chars, topProject: stats.topProject
        )
    }

    func dismissDailySummary() {
        showDailySummary = false
    }

    // MARK: - Weekly summary

    var prevWeekStats: (chars: Int, activeDays: Int, bestDay: Int, topProject: String?) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start,
              let prevWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) else {
            return (0, 0, 0, nil)
        }
        let totals = dailyTotals()
        var totalChars = 0; var activeDays = 0; var bestDay = 0
        var current = prevWeekStart
        for _ in 0..<7 {
            let dayTotal = totals[DataStore.dateString(from: current)] ?? 0
            totalChars += dayTotal
            if dayTotal > 0 { activeDays += 1 }
            if dayTotal > bestDay { bestDay = dayTotal }
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current
        }
        var topProject: String? = nil; var topCount = 0
        for project in data.projects {
            let pt = dailyTotals(projectId: project.id)
            var c2 = prevWeekStart
            var projTotal = 0
            for _ in 0..<7 {
                projTotal += pt[DataStore.dateString(from: c2)] ?? 0
                c2 = cal.date(byAdding: .day, value: 1, to: c2) ?? c2
            }
            if projTotal > topCount { topCount = projTotal; topProject = project.name }
        }
        return (totalChars, activeDays, bestDay, topProject)
    }

    func checkAndShowWeeklySummary() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let now = Date()
        guard cal.component(.weekday, from: now) == 2 else { return }  // lundi
        guard cal.component(.hour, from: now) >= 8 else { return }
        guard let prevWeekDate = cal.date(byAdding: .weekOfYear, value: -1, to: now) else { return }
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: prevWeekDate)
        let key = "\(comps.yearForWeekOfYear ?? 0)-W\(String(format: "%02d", comps.weekOfYear ?? 0))"
        guard lastWeeklySummaryWeek != key else { return }
        let stats = prevWeekStats
        guard stats.chars > 0 else { return }
        lastWeeklySummaryWeek = key
        showWeeklySummary = true
    }

    func dismissWeeklySummary() {
        showWeeklySummary = false
    }

    // MARK: - Accent color theme

    var accentColorHex: String {
        get { UserDefaults.standard.string(forKey: "accentColorHex") ?? "#F59E0B" }
    }

    func setAccentColor(hex: String) {
        UserDefaults.standard.set(hex, forKey: "accentColorHex")
        objectWillChange.send()
    }

    // MARK: - Pinned dates (Calendar)

    func togglePinnedDate(_ dateStr: String, label: String = "") {
        if data.pinnedDates.contains(where: { $0.date == dateStr }) {
            data.pinnedDates.removeAll { $0.date == dateStr }
        } else {
            data.pinnedDates.append(PinnedDate(date: dateStr, label: label))
        }
        save()
    }

    func updatePinnedDateLabel(_ dateStr: String, label: String) {
        guard let idx = data.pinnedDates.firstIndex(where: { $0.date == dateStr }) else { return }
        data.pinnedDates[idx].label = label
        save()
    }

    // MARK: - Template project

    func addProjectWithChapters(name: String, chapters: [(name: String, goal: Int)]) {
        var project = Project(name: name)
        project.chapters = chapters.map { c in
            Chapter(name: c.name, goal: c.goal)
        }
        if let first = project.chapters.first {
            project.activeChapterId = first.id
        }
        data.projects.append(project)
        if data.activeProjectId == nil { data.activeProjectId = project.id }
        save()
    }

    // MARK: - Milestones

    enum MilestoneType: Equatable {
        case streak(Int)
        case chapterComplete(String)
        case challengeComplete(WeeklyChallenge.ChallengeKind)
    }

    static let badgeMilestones = [3, 7, 14, 30, 60, 100]

    /// Paliers de streak débloqués à vie (basé sur longestStreak)
    var unlockedBadgeThresholds: [Int] {
        DataStore.badgeMilestones.filter { longestStreak >= $0 }
    }

    @Published var pendingMilestone: MilestoneType? = nil

    func showMilestone(_ milestone: MilestoneType) {
        guard pendingMilestone == nil else { return }   // pas de double
        pendingMilestone = milestone
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            withAnimation { self?.pendingMilestone = nil }
        }
    }

    func dismissMilestone() {
        withAnimation { pendingMilestone = nil }
    }

    private func checkNewBadgeUnlocks() {
        let key = "toastedStreakMilestones"
        var toasted = Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? [])
        for threshold in DataStore.badgeMilestones {
            guard currentStreak >= threshold, !toasted.contains(threshold) else { continue }
            toasted.insert(threshold)
            UserDefaults.standard.set(Array(toasted), forKey: key)
            showMilestone(.streak(threshold))
            break // un seul toast à la fois
        }
        checkOrGenerateWeeklyChallenge()
        checkWeeklyChallengeCompletion()
    }

    // MARK: - Weekly challenges

    /// ISO week key e.g. "2026-W12"
    static var currentWeekKey: String {
        let cal = Calendar(identifier: .iso8601)
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let y = components.yearForWeekOfYear ?? 2026
        let w = components.weekOfYear ?? 1
        return String(format: "%04d-W%02d", y, w)
    }

    var currentWeekChallenge: WeeklyChallenge? {
        data.weeklyChallenges.first { $0.weekKey == DataStore.currentWeekKey }
    }

    func challengeProgress(_ challenge: WeeklyChallenge) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) else { return 0 }
        switch challenge.kind {
        case .words:
            let totals = dailyTotals()
            return (0..<7).compactMap { offset -> Int? in
                guard let d = cal.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
                return totals[DataStore.dateString(from: d)]
            }.reduce(0, +)
        case .daysWritten:
            let totals = dailyTotals()
            return (0..<7).filter { offset in
                guard let d = cal.date(byAdding: .day, value: offset, to: weekStart) else { return false }
                return (totals[DataStore.dateString(from: d)] ?? 0) > 0
            }.count
        case .streak:
            return currentStreak
        case .sessions:
            return 0  // Would need Pomodoro data; placeholder
        }
    }

    // Calendrier de 50 défis hebdomadaires pré-définis (cycle annuel)
    // Cibles `.words` en caractères ; `.sessions` en sessions Pomodoro
    static let challengeSchedule: [(WeeklyChallenge.ChallengeKind, Int)] = [
        (.daysWritten, 3),   // S01 – Démarrage en douceur
        (.words,    8_000),  // S02 – Premier volume
        (.daysWritten, 4),   // S03 – Régularité
        (.words,   12_000),  // S04 – Montée en puissance
        (.streak,       5),  // S05 – Série de 5 jours
        (.sessions,     5),  // S06 – Focus Pomodoro
        (.daysWritten, 5),   // S07 – Cinq sur sept
        (.words,   15_000),  // S08 – Objectif solide
        (.streak,       7),  // S09 – Semaine parfaite
        (.sessions,     7),  // S10 – Semaine Pomodoro
        (.daysWritten, 6),   // S11 – Six jours
        (.words,   20_000),  // S12 – Bonne cadence
        (.streak,      10),  // S13 – Dizaine consécutive
        (.sessions,    10),  // S14 – Dix sessions focus
        (.daysWritten, 7),   // S15 – Semaine complète
        (.words,   25_000),  // S16 – Sprint de chars
        (.streak,      14),  // S17 – Deux semaines de suite
        (.daysWritten, 5),   // S18 – Retour à la régularité
        (.words,   10_000),  // S19 – Volume modéré
        (.sessions,     5),  // S20 – Relance Pomodoro
        (.daysWritten, 4),   // S21 – Demi-semaine
        (.words,   30_000),  // S22 – Grand sprint
        (.streak,       7),  // S23 – Resserrer la série
        (.sessions,     7),  // S24 – Focus intensif
        (.daysWritten, 6),   // S25 – Presque tous les jours
        (.words,   18_000),  // S26 – Mi-année, bonne cadence
        (.streak,      21),  // S27 – Trois semaines
        (.daysWritten, 7),   // S28 – Semaine sans faille
        (.words,   35_000),  // S29 – Grosse semaine
        (.sessions,    10),  // S30 – Dix sessions
        (.daysWritten, 5),   // S31 – Été : garder le cap
        (.words,   15_000),  // S32 – Volume estival
        (.streak,      14),  // S33 – Reconstituer la série
        (.sessions,     5),  // S34 – Cinq focus
        (.daysWritten, 6),   // S35 – Reprise de rythme
        (.words,   22_000),  // S36 – Automne productif
        (.streak,      10),  // S37 – Série de 10
        (.daysWritten, 7),   // S38 – Semaine pleine
        (.words,   40_000),  // S39 – Défi ambitieux
        (.sessions,    10),  // S40 – Focus de pointe
        (.streak,      21),  // S41 – Trois semaines de suite
        (.daysWritten, 5),   // S42 – Maintien
        (.words,   20_000),  // S43 – Bon volume
        (.sessions,     7),  // S44 – Pomodoro régulier
        (.daysWritten, 7),   // S45 – Semaine parfaite
        (.words,   30_000),  // S46 – Avant la fin d'année
        (.streak,      30),  // S47 – Un mois de suite
        (.sessions,    10),  // S48 – Ultime focus
        (.words,   50_000),  // S49 – Défi final de l'année
        (.daysWritten, 7),   // S50 – Terminer en beauté
    ]

    private func checkOrGenerateWeeklyChallenge() {
        let key = DataStore.currentWeekKey
        guard data.weeklyChallenges.first(where: { $0.weekKey == key }) == nil else { return }

        let cal = Calendar(identifier: .iso8601)
        let weekOfYear = cal.component(.weekOfYear, from: Date())
        let idx = max(0, (weekOfYear - 1) % DataStore.challengeSchedule.count)
        let (kind, target) = DataStore.challengeSchedule[idx]

        data.weeklyChallenges.append(WeeklyChallenge(weekKey: key, kind: kind, target: target))
    }

    private func checkWeeklyChallengeCompletion() {
        guard let idx = data.weeklyChallenges.firstIndex(where: {
            $0.weekKey == DataStore.currentWeekKey && !$0.isCompleted
        }) else { return }
        let challenge = data.weeklyChallenges[idx]
        let progress = challengeProgress(challenge)
        guard progress >= challenge.target else { return }

        // Marquer comme complété en mémoire
        data.weeklyChallenges[idx].completedAt = DataStore.today

        // Persister immédiatement pour éviter la re-notification au prochain lancement
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: activeFileURL, options: .atomic)
        }

        // Guard UserDefaults : n'afficher la notification qu'une seule fois
        let udKey = "notifiedChallengeWeeks"
        var notified = Set(UserDefaults.standard.array(forKey: udKey) as? [String] ?? [])
        guard !notified.contains(challenge.weekKey) else { return }
        notified.insert(challenge.weekKey)
        UserDefaults.standard.set(Array(notified), forKey: udKey)

        showMilestone(.challengeComplete(challenge.kind))
    }

    /// Returns total words/chars written per hour of day (index 0 = midnight, 23 = 11pm)
    var hourlyProductivity: [Int] {
        var counts = [Int](repeating: 0, count: 24)
        for project in data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    guard let hour = entry.savedAtHour, hour >= 0, hour < 24 else { continue }
                    let increment = chapter.increment(for: entry.date)
                    if increment > 0 { counts[hour] += increment }
                }
            }
        }
        return counts
    }

    var chaptersWithDeadlines: [(project: Project, chapter: Chapter)] {
        data.projects.flatMap { project in
            project.chapters.compactMap { chapter in
                chapter.deadline == nil ? nil : (project, chapter)
            }
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.chapter.deadline.flatMap(DataStore.parseDate) ?? .distantFuture
            let rhsDate = rhs.chapter.deadline.flatMap(DataStore.parseDate) ?? .distantFuture
            return lhsDate < rhsDate
        }
    }
}

