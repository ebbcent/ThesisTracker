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
    // Not @Published — cache invalidation uses it directly; re-renders come from `data` changes.
    // Making it @Published would cause a second objectWillChange on every save, dropping frames.
    var dataVersion: Int = 0
    @Published var isUsingICloud: Bool = false
    @Published var showSaveIndicator: Bool = false
    @Published var iCloudSyncActive: Bool = false   // #42 — spinner discret
    @Published var loadErrorMessage: String? = nil
    /// Last unrecoverable save error surfaced to the user. Cleared on next successful save.
    /// Non-nil here means the in-memory state is ahead of disk — the user MUST see it
    /// before they trust today's writing as persisted.
    @Published var saveErrorMessage: String? = nil

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
    /// Timestamp of our most recent self-write. The directory file-watcher fires
    /// on EVERY write to data.json — including ours. Without this, every save()
    /// (i.e. every pause in typing) would trigger a full main-thread JSON
    /// re-load 0.8s later, republishing `data` and re-rendering the entire UI.
    private var lastSelfWriteAt: Date = .distantPast
    private var lastSnapshotSignature: String?
    private let appStorageName = "Writing Process"
    private let legacyStorageNames = ["Writing Process", "WritingTracker", "ThesisTracker"]

    // Shared Calendar instances — never allocate Calendar(identifier:) in hot paths
    static let gregorianCal: Calendar = Calendar(identifier: .gregorian)
    static let isoWeekCal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.firstWeekday = 2; return c
    }()
    static let iso8601Cal: Calendar = Calendar(identifier: .iso8601)

    private static let storageDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    // Shared formatters for Stats — avoids per-call allocations
    static let shortDayMonthFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM"; return f
    }()
    static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM yyyy"; return f
    }()
    static let monthYearKeyFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f
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

    /// Reused encoder/decoder. JSONEncoder/JSONDecoder are non-trivial to
    /// construct (they spin up JSONSerialization state). The encoder/decoder
    /// instances are stateless across encode calls, so reuse is safe.
    static let sharedEncoder: JSONEncoder = JSONEncoder()
    static let sharedDecoder: JSONDecoder = JSONDecoder()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "\u{202F}"
        return formatter
    }()

    private var _dailyTotalsCache: (version: Int, totals: [String: Int])? = nil
    private var _dailyTotalsByProjectCache: [UUID: (version: Int, totals: [String: Int])] = [:]
    // Caches for expensive stat aggregations invalidated with dataVersion
    var _allMonthlyStatsCache: (version: Int, stats: [(label: String, chars: Int)])? = nil
    var _weekdayAveragesCache: (version: Int, averages: [(day: String, avg: Int)])? = nil
    var _hourlyProductivityCache: (version: Int, counts: [Int])? = nil
    // Performance caches (#perf) — keyed on dataVersion
    private var _currentCalMonthProgressCache: (version: Int, value: Int)? = nil
    private var _activeDaysThisMonthCache: (version: Int, value: Int)? = nil
    private var _defenseProjectionCache: (version: Int, value: DefenseProjection)? = nil
    private var _criticalPathCache: (version: Int, items: [CriticalMilestone])? = nil
    private var _chaptersWithDeadlinesCache: (version: Int, items: [(project: Project, chapter: Chapter)])? = nil
    private var _allMilestonesSortedCache: (version: Int, items: [(project: Project, milestone: Milestone)])? = nil
    private var _currentStreakCache: (version: Int, value: Int)? = nil
    private var _longestStreakCache: (version: Int, value: Int)? = nil
    // Stats extension caches (DataStore+Stats)
    var _thesisRemainingCharsCache: (version: Int, value: Int)? = nil
    var _allTimeBestDayCache: (version: Int, value: Int)? = nil
    var _allTimeBestDayDateCache: (version: Int, value: String?)? = nil
    var _daysWrittenThisMonthCache: (version: Int, value: Int)? = nil
    var _velocity14DaysCache: (version: Int, value: Int)? = nil
    var _top10DaysCache: (version: Int, entries: [TopDayEntry])? = nil
    var _hourHeatmapCache: (version: Int, entries: [HourHeatmapEntry])? = nil
    var _plateauChaptersCache: (version: Int, chapters: [PlateauChapter])? = nil
    private var _writingSpeedDataCache: (version: Int, data: WritingSpeedData)? = nil
    private var _weekComparisonDataCache: (version: Int, data: WeekComparisonData)? = nil
    var _projectDistribution30Cache: (version: Int, shares: [ProjectShare])? = nil
    var _bestWeekStatCache: (version: Int, stat: (label: String, chars: Int)?)? = nil
    // Sidebar perf caches — rebuilt once per dataVersion, O(1) thereafter
    private var _latestTotalsAllCache: (version: Int, totals: [UUID: Int])? = nil
    private var _estimatedCompletionDatesAllCache: (version: Int, dates: [UUID: Date?])? = nil
    private var _projectRatiosAllCache: (version: Int, ratios: [UUID: Double])? = nil
    // Dashboard typing perf caches
    private var _weeklyProgressCache: (version: Int, value: Int)? = nil
    private var _monthlyProgressCache: (version: Int, value: Int)? = nil
    private var _currentWeekInfoCache: (version: Int, days: [WeekDayInfo])? = nil
    // Debounce token for background save
    private var saveDebounceTask: DispatchWorkItem?
    /// Anchor for the max-wait : if `save()` is called continuously, the debounce
    /// would never fire. We force a flush after `saveMaxWait` seconds regardless.
    private var saveDebounceAnchor: Date?
    private let saveMaxWait: TimeInterval = 2.0

    // MARK: Persistence state
    /// File série : toutes les lectures/écritures de data.json passent par
    /// elle, dans l'ordre. Une ancienne sauvegarde ne peut plus terminer après
    /// une plus récente, et une lecture ne croise jamais une écriture.
    private let ioQueue = DispatchQueue(label: "com.writingprocess.datastore.io", qos: .userInitiated)
    /// Contenu du fichier tel qu'on l'a lu ou écrit la dernière fois (ioQueue
    /// uniquement) : ancêtre commun pour fusionner les modifications de l'autre Mac.
    private var ioBaseData: Data?
    /// Faux tant que le fichier n'a pas été lu correctement : aucune écriture
    /// n'est alors autorisée, pour ne jamais écraser des données non chargées.
    @Published private(set) var isLoaded: Bool = false
    /// Modifications locales demandées / effectivement écrites (thread principal).
    private var localChangeCount = 0
    private var persistedChangeCount = 0
    private var hasPendingLocalChanges: Bool { localChangeCount != persistedChangeCount }

    // MARK: - File URLs

    /// Chemin vers le fichier iCloud Drive.
    /// Utilise NSHomeDirectory() pour être sûr d'avoir le vrai home dir (non sandboxé).
    private var iCloudDriveFileURL: URL? {
        let fm = FileManager.default
        let iCloudRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        // Vérifie que iCloud Drive est monté (le répertoire racine existe)
        guard fm.fileExists(atPath: iCloudRoot.path) else { return nil }
        let appDir = iCloudRoot.appendingPathComponent(appStorageName)
        // Crée le sous-dossier si absent (no-op s'il existe déjà, on ignore l'erreur)
        try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("data.json")
    }

    private var localFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(appStorageName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data.json")
    }

    var snapshotsDirectoryURLPublic: URL { snapshotsDirectoryURL }

    private var snapshotsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(appStorageName).appendingPathComponent("Snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var legacyICloudFileURLs: [URL] {
        let iCloudRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
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

    /// URL du fichier actuellement utilisé — exposé pour le debug dans Settings
    var activeFileURLPublic: URL { activeFileURL }

    // MARK: - Init

    init() {
        isUsingICloud = iCloudDriveFileURL != nil
        migrateToICloudIfNeeded()
        load()
        // #51 — index initial Spotlight (délai pour laisser le chargement se terminer)
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self else { return }
            SpotlightIndexer.shared.reindex(self.data)
        }
        trackAppOpen()
        validateDataIntegrity()
        startWatchingFile()
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(flushPendingSaveOnTerminate),
            name: NSApplication.willTerminateNotification, object: nil
        )
    }

    /// Preview-only init: in-memory, no disk I/O, no file watcher, no notification
    /// observers, no Spotlight indexing. Lets Xcode Previews render any view that
    /// depends on a DataStore without triggering the full launch flow.
    private init(previewData: AppData) {
        self.data = previewData
        self.isUsingICloud = false
        self.dataVersion = 1
    }

    /// Shared in-memory store with seeded sample data for SwiftUI previews.
    /// Lazily built once per process; safe to pass to any view that expects a DataStore.
    static let preview: DataStore = {
        var sample = AppData()
        sample.dailyGoal = 1500
        sample.useWordCount = false

        let cal = Calendar(identifier: .gregorian)
        let fmt = DateFormatter()
        fmt.calendar = cal
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"

        var intro = Chapter(name: "Introduction", goal: 30_000)
        var litReview = Chapter(name: "État de l'art", goal: 60_000)
        var methodo = Chapter(name: "Méthodologie", goal: 45_000)
        for offset in (0..<14).reversed() {
            let date = cal.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
            let dStr = fmt.string(from: date)
            let base = max(0, 12_000 - offset * 600)
            intro.entries.append(DailyEntry(date: dStr, totalCount: base, note: nil))
            if offset < 10 {
                litReview.entries.append(DailyEntry(date: dStr, totalCount: max(0, 18_000 - offset * 900), note: nil))
            }
            if offset < 5 {
                methodo.entries.append(DailyEntry(date: dStr, totalCount: max(0, 4_000 - offset * 500), note: nil))
            }
        }

        var thesis = Project(name: "Ma thèse — démo")
        thesis.chapters = [intro, litReview, methodo]
        thesis.activeChapterId = intro.id

        sample.projects = [thesis]
        sample.activeProjectId = thesis.id

        return DataStore(previewData: sample)
    }()

    // MARK: - Migration locale → iCloud Drive

    /// Copie l'ancien fichier local vers iCloud Drive UNIQUEMENT si iCloud ne
    /// contient encore rien (ni fichier, ni fichier « .icloud » en attente de
    /// téléchargement). Un fichier iCloud existant n'est jamais remplacé : il
    /// peut venir de l'autre Mac, ou être illisible le temps qu'iCloud finisse
    /// de le télécharger.
    private func migrateToICloudIfNeeded() {
        guard let iCloudFile = iCloudDriveFileURL else { return }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: iCloudFile.path),
              !fm.fileExists(atPath: DataStore.placeholderURL(for: iCloudFile).path) else { return }
        let candidates = [localFileURL] + legacyICloudFileURLs + legacyLocalFileURLs
        guard let source = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else { return }
        try? fm.createDirectory(at: iCloudFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: source, to: iCloudFile)
    }

    // MARK: - Disk access (ioQueue)

    private enum DiskReadResult {
        case data(Data)
        case missing          // aucun fichier : premier lancement
        case notDownloaded    // iCloud ne l'a pas encore téléchargé sur ce Mac
        case failure(Error)
    }

    /// Fichier « .data.json.icloud » laissé par iCloud quand le vrai fichier
    /// n'est pas (encore) présent sur ce Mac.
    static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("." + url.lastPathComponent + ".icloud")
    }

    /// Lecture coordonnée avec iCloud. Si le fichier n'existe que sous forme de
    /// « .icloud », on demande son téléchargement et on attend (au plus
    /// `waitForDownload` secondes). À appeler hors du thread principal.
    private static func readDisk(_ url: URL, waitForDownload: TimeInterval) -> DiskReadResult {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            guard fm.fileExists(atPath: placeholderURL(for: url).path) else { return .missing }
            try? fm.startDownloadingUbiquitousItem(at: url)
            let deadline = Date().addingTimeInterval(waitForDownload)
            while !fm.fileExists(atPath: url.path) && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
            guard fm.fileExists(atPath: url.path) else { return .notDownloaded }
        }
        var result: DiskReadResult = .missing
        var coordinationError: NSError?
        // La lecture coordonnée attend aussi la fin d'un téléchargement iCloud
        // en cours (fichiers « sans données » de macOS 14+).
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do { result = .data(try Data(contentsOf: readURL)) } catch { result = .failure(error) }
        }
        if let coordinationError { return .failure(coordinationError) }
        return result
    }

    /// Décode en ignorant individuellement les éléments abîmés.
    static func decodeAppData(_ bytes: Data) throws -> (data: AppData, dropped: Int) {
        let report = LossyDecodingReport()
        let decoder = JSONDecoder()
        decoder.userInfo[.lossyReport] = report
        let decoded = try decoder.decode(AppData.self, from: bytes)
        return (decoded, report.droppedCount)
    }

    private var recoveryDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent(appStorageName).appendingPathComponent("Recovery")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Met de côté une copie brute d'un fichier problématique avant tout autre traitement.
    private static func writeRecoveryCopy(_ bytes: Data, reason: String, in dir: URL) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("data-\(reason)-\(stamp).json")
        do { try bytes.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// Fusionne dans le fichier principal les copies en conflit créées par
    /// iCloud quand les deux Mac ont écrit en même temps, puis les supprime.
    private func resolveICloudConflictVersions(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path),
              let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }
        let recoveryDir = recoveryDirectoryURL
        guard var merged = try? Data(contentsOf: url) else { return }
        for version in conflicts {
            guard let theirs = try? Data(contentsOf: version.url) else { continue }
            _ = DataStore.writeRecoveryCopy(theirs, reason: "conflit-icloud", in: recoveryDir)
            if let result = DataSync.merge(base: nil, mine: merged, theirs: theirs),
               var decoded = try? DataStore.decodeAppData(result).data {
                DataSync.normalize(&decoded)
                if let encoded = try? DataStore.sharedEncoder.encode(decoded) { merged = encoded }
            }
        }
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            lastSelfWriteAt = Date()
            try? merged.write(to: writeURL, options: .atomic)
        }
        for version in conflicts { version.isResolved = true }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    // MARK: - Load

    /// Autorise les écritures : appelé une fois le fichier lu correctement,
    /// quand il n'existe pas encore, ou quand l'utilisateur restaure un snapshot.
    func markLoaded() {
        if !isLoaded { isLoaded = true }
        if saveErrorMessage != nil && !hasPendingLocalChanges { saveErrorMessage = nil }
    }

    func load() {
        let url = activeFileURL
        let recoveryDir = recoveryDirectoryURL
        // Lecture + décodage hors du thread principal, sur la même file série
        // que les écritures : une lecture ne croise jamais une écriture.
        ioQueue.async { [weak self] in
            guard let self else { return }
            self.resolveICloudConflictVersions(at: url)
            switch DataStore.readDisk(url, waitForDownload: 20) {
            case .missing:
                // Aucun fichier (premier lancement) : on peut écrire, y compris
                // ce qui a été saisi avant la fin de cette vérification.
                DispatchQueue.main.async {
                    self.loadErrorMessage = nil
                    let wasLoaded = self.isLoaded
                    self.markLoaded()
                    if !wasLoaded && self.hasPendingLocalChanges { self.save() }
                }
            case .notDownloaded:
                DispatchQueue.main.async {
                    self.loadErrorMessage = "Le fichier iCloud n'est pas encore téléchargé sur ce Mac. Nouvel essai automatique…"
                    if !self.isLoaded {
                        self.saveErrorMessage = "Données pas encore arrivées d'iCloud : rien n'est enregistré pour l'instant."
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.load() }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.loadErrorMessage = "Lecture impossible : \(error.localizedDescription)"
                    if !self.isLoaded {
                        self.saveErrorMessage = "Données non chargées : écriture bloquée pour protéger le fichier."
                    }
                }
            case .data(let bytes):
                // Rien de nouveau depuis notre dernière lecture/écriture.
                if bytes == self.ioBaseData { return }
                do {
                    let result = try DataStore.decodeAppData(bytes)
                    var decoded = result.data
                    let dropped = result.dropped
                    self.applyLegacyMigration(&decoded)
                    var warning: String? = nil
                    if dropped > 0 {
                        let copy = DataStore.writeRecoveryCopy(bytes, reason: "elements-illisibles", in: recoveryDir)
                        warning = "\(dropped) élément(s) illisible(s) ignoré(s) au chargement. Copie du fichier d'origine : Recovery/\(copy?.lastPathComponent ?? "échec de la copie")."
                    }
                    DispatchQueue.main.async {
                        self.adoptLoaded(decoded, diskBytes: bytes, warning: warning)
                    }
                } catch {
                    let copy = DataStore.writeRecoveryCopy(bytes, reason: "illisible", in: recoveryDir)
                    DispatchQueue.main.async {
                        self.loadErrorMessage = "Fichier de données illisible (\(error.localizedDescription)). Copie mise de côté : Recovery/\(copy?.lastPathComponent ?? "—"). Restaure un snapshot depuis les Réglages."
                        if !self.isLoaded {
                            self.saveErrorMessage = "Données illisibles : écriture bloquée pour protéger le fichier. Restaure un snapshot."
                        }
                    }
                }
            }
        }
    }

    /// Thread principal. N'écrase jamais des modifications locales pas encore
    /// écrites : dans ce cas, la prochaine sauvegarde fusionne avec le disque.
    private func adoptLoaded(_ decoded: AppData, diskBytes: Data, warning: String?) {
        loadErrorMessage = warning
        if isLoaded && hasPendingLocalChanges {
            save()
            return
        }
        ioQueue.async { [weak self] in self?.ioBaseData = diskBytes }
        if !isLoaded {
            // Premier chargement : ce qui a été modifié sur l'état vide d'avant
            // chargement n'a jamais été écrit et est remplacé par le fichier.
            persistedChangeCount = localChangeCount
        }
        markLoaded()
        data = decoded
        dataVersion += 1
    }

    private func applyLegacyMigration(_ decoded: inout AppData) {
        if decoded.projects.isEmpty, let old = decoded.legacyChapters, !old.isEmpty {
            var project = Project(name: "Ma thèse")
            project.chapters = old
            project.activeChapterId = decoded.legacyActiveChapterId
            decoded.projects = [project]
            decoded.activeProjectId = project.id
        }
    }

    // MARK: - Save

    func save() {
        localChangeCount += 1
        guard isLoaded else {
            // Jamais d'écriture tant que le fichier n'a pas été lu : on
            // risquerait d'écraser les vraies données avec un état vide.
            saveErrorMessage = "Données pas encore chargées : cette modification n'est pas enregistrée."
            return
        }
        // Debounce : pendant une rafale de frappe, on n'écrit qu'après 0,35 s
        // de pause. Max-wait : au-delà de `saveMaxWait` secondes de rafale
        // continue, on laisse partir la tâche déjà planifiée. L'état est lu au
        // moment où la tâche part, donc la dernière frappe est toujours incluse.
        let now = Date()
        if saveDebounceAnchor == nil { saveDebounceAnchor = now }
        let elapsed = now.timeIntervalSince(saveDebounceAnchor ?? now)
        if elapsed >= saveMaxWait, saveDebounceTask != nil {
            return
        }
        saveDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveDebounceTask = nil
            self.saveDebounceAnchor = nil
            self.enqueueWrite()
        }
        saveDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: task)
    }

    /// Thread principal : capture l'état courant et l'envoie à la file d'écriture.
    private func enqueueWrite() {
        let snapshot    = data
        let changeCount = localChangeCount
        let fileURL     = activeFileURL
        let mirrorURL   = isUsingICloud ? localFileURL : nil
        let usingICloud = isUsingICloud
        let todayStr    = DataStore.today
        ioQueue.async { [weak self] in
            self?.performWrite(snapshot, changeCount: changeCount, fileURL: fileURL, mirrorURL: mirrorURL,
                               usingICloud: usingICloud, todayStr: todayStr, waitForDownload: 20, notify: true)
        }
    }

    /// ioQueue uniquement. Fusionne avec le fichier si l'autre Mac l'a modifié
    /// depuis notre dernière lecture/écriture, puis écrit de façon coordonnée.
    private func performWrite(_ snapshot: AppData, changeCount: Int, fileURL: URL, mirrorURL: URL?,
                              usingICloud: Bool, todayStr: String, waitForDownload: TimeInterval, notify: Bool) {
        let mine: Data
        do {
            mine = try DataStore.sharedEncoder.encode(snapshot)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.saveErrorMessage = "Encodage impossible : \(error.localizedDescription)"
            }
            return
        }

        var toWrite = mine
        var merged: AppData? = nil
        switch DataStore.readDisk(fileURL, waitForDownload: waitForDownload) {
        case .data(let disk):
            if let base = ioBaseData, disk != base, disk != mine {
                // L'autre Mac a écrit entre-temps : on garde une copie de sa
                // version, puis on fusionne au lieu d'écraser.
                saveSnapshotIfNeeded(for: disk)
                if let mergedBytes = DataSync.merge(base: base, mine: mine, theirs: disk),
                   var decoded = try? DataStore.decodeAppData(mergedBytes).data {
                    DataSync.normalize(&decoded)
                    if let encoded = try? DataStore.sharedEncoder.encode(decoded) {
                        toWrite = encoded
                        merged = decoded
                    }
                }
            }
        case .notDownloaded:
            // Ne jamais écrire par-dessus un fichier qu'iCloud n'a pas encore livré.
            if notify {
                DispatchQueue.main.async { [weak self] in
                    self?.saveErrorMessage = "iCloud n'a pas encore téléchargé data.json : nouvel essai dans 10 s."
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.save() }
                }
            }
            return
        case .missing, .failure:
            break
        }

        // Marquer AVANT l'écriture : le watcher du dossier ignore nos propres écritures.
        lastSelfWriteAt = Date()
        var writeError: Error?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { writeURL in
            do { try toWrite.write(to: writeURL, options: .atomic) } catch { writeError = error }
        }
        if let error = writeError ?? coordinationError {
            DispatchQueue.main.async { [weak self] in
                self?.saveErrorMessage = "Sauvegarde impossible : \(error.localizedDescription)"
            }
            return
        }
        lastSelfWriteAt = Date()
        ioBaseData = toWrite
        // Copie de secours locale (hors iCloud) du dernier état écrit.
        if let mirrorURL { try? toWrite.write(to: mirrorURL, options: .atomic) }
        saveSnapshotIfNeeded(for: toWrite)
        guard notify else { return }
        SpotlightIndexer.shared.reindex(merged ?? snapshot)

        // ── Main thread: cache invalidation + UI indicators + notifications ──
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.persistedChangeCount = max(self.persistedChangeCount, changeCount)
            self.saveErrorMessage = nil
            if let merged { self.integrateMerged(merged, mergedBytes: toWrite, mineBytes: mine) }
            // Invalidate dataVersion-keyed caches and trigger one re-render so
            // stats catch up after the burst. objectWillChange is needed because
            // dataVersion itself is not @Published.
            self.dataVersion += 1
            self.objectWillChange.send()

            let todayTotal = self.dailyProgress
            let goal       = max(1, self.data.dailyGoal)
            NSApp.mainWindow?.title = todayTotal > 0
                ? "Writing Process — +\(self.formatCount(todayTotal)) aujourd'hui"
                : "Writing Process"
            if todayTotal <= 0 {
                NSApp.dockTile.badgeLabel = nil
            } else if todayTotal >= goal {
                NSApp.dockTile.badgeLabel = "✓"
            } else {
                NSApp.dockTile.badgeLabel = "\(min(99, Int(Double(todayTotal) / Double(goal) * 100)))%"
            }

            self.showSaveIndicator = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.showSaveIndicator = false
            }
            if usingICloud {
                self.iCloudSyncActive = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                    self?.iCloudSyncActive = false
                }
            }
            self.scheduleSaveNotifications(todayTotal: todayTotal, todayStr: todayStr)
            self.checkAndShowDailySummary()
            self.checkAndShowWeeklySummary()
            self.checkWeeklyReportIfNeeded()
            self.checkNewBadgeUnlocks()
        }
    }

    /// Thread principal : intègre le résultat d'une fusion sans perdre ce qui
    /// a été saisi pendant l'écriture.
    private func integrateMerged(_ merged: AppData, mergedBytes: Data, mineBytes: Data) {
        guard let current = try? DataStore.sharedEncoder.encode(data) else { return }
        if current == mineBytes {
            data = merged
        } else if let rebased = DataSync.merge(base: mineBytes, mine: current, theirs: mergedBytes),
                  var decoded = try? DataStore.decodeAppData(rebased).data {
            DataSync.normalize(&decoded)
            data = decoded
            save()
        }
    }

    /// Écrit immédiatement ce qui est en attente (fermeture de l'app).
    @objc private func flushPendingSaveOnTerminate() {
        guard isLoaded, hasPendingLocalChanges else { return }
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        let snapshot  = data
        let count     = localChangeCount
        let fileURL   = activeFileURL
        let mirrorURL = isUsingICloud ? localFileURL : nil
        let usingICloud = isUsingICloud
        ioQueue.sync {
            performWrite(snapshot, changeCount: count, fileURL: fileURL, mirrorURL: mirrorURL,
                         usingICloud: usingICloud, todayStr: DataStore.today, waitForDownload: 2, notify: false)
        }
    }

    /// All notification scheduling, called once per debounce cycle — main thread.
    private func scheduleSaveNotifications(todayTotal: Int, todayStr: String) {
        let hasWrittenToday = !data.projects.flatMap { $0.chapters }
            .allSatisfy { $0.increment(for: todayStr) == 0 }
        NotificationManager.shared.scheduleDeadlineNotifications(chaptersWithDeadlines: chaptersWithDeadlines)
        scheduleDeadlinePaceAlertsIfNeeded()
        scheduleMilestoneNotificationsIfNeeded()
        scheduleDeadlineConflictAlertsIfNeeded()
        NotificationManager.shared.scheduleStreakWarningIfNeeded(
            currentStreak: currentStreak, hasWrittenToday: hasWrittenToday)
        schedulePlateauAlertsIfNeeded()
        NotificationManager.shared.scheduleDailyRecapIfNeeded(
            totalToday: todayTotal, streak: currentStreak,
            dailyGoal: effectiveDailyGoal, useWordCount: data.useWordCount)
        NotificationManager.shared.scheduleCongratulationsIfNeeded(streak: currentStreak)
        scheduleWeeklyReportNotificationIfNeeded()
        NotificationManager.shared.scheduleDoubleGoalAlertIfNeeded(
            total: todayTotal, goal: effectiveDailyGoal, useWordCount: data.useWordCount)
        NotificationManager.shared.scheduleEmptyDayReminderIfNeeded(hasWrittenToday: hasWrittenToday)
        if !NSApp.isActive {
            NotificationManager.shared.scheduleBackgroundGoalNotification(
                total: todayTotal, goal: effectiveDailyGoal, useWordCount: data.useWordCount)
        }
    }

    /// ioQueue. Garde les 30 snapshots les plus récents ET le dernier de chacun
    /// des 60 derniers jours : une grosse séance ou un import ne fait plus
    /// disparaître l'historique de la veille.
    private func saveSnapshotIfNeeded(for encoded: Data) {
        var hasher = Hasher()
        encoded.withUnsafeBytes { hasher.combine(bytes: $0) }
        let signature = "\(encoded.count)-\(hasher.finalize())"
        guard signature != lastSnapshotSignature else { return }
        lastSnapshotSignature = signature
        let snapshotsDir = snapshotsDirectoryURL

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = snapshotsDir.appendingPathComponent("snapshot-\(timestamp).json")
        try? encoded.write(to: url, options: .atomic)

        let urls = (try? FileManager.default.contentsOfDirectory(
            at: snapshotsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let dated: [(url: URL, date: Date)] = urls.map { u in
            (u, (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }.sorted { $0.date > $1.date }

        var keep = Set(dated.prefix(30).map(\.url))
        let cal = DataStore.gregorianCal
        let horizon = cal.date(byAdding: .day, value: -60, to: Date()) ?? .distantPast
        var seenDays = Set<DateComponents>()
        for item in dated where item.date >= horizon {
            let day = cal.dateComponents([.year, .month, .day], from: item.date)
            if seenDays.insert(day).inserted { keep.insert(item.url) }
        }
        for item in dated where !keep.contains(item.url) {
            try? FileManager.default.removeItem(at: item.url)
        }
    }

    // MARK: - File watcher

    private func startWatchingFile() {
        let dirURL = activeFileURL.deletingLastPathComponent()
        let fd = open(dirURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename],   // .rename capte les remplacements atomiques d'iCloud
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            // Ignore events triggered by our OWN writes — otherwise every save()
            // (= every typing pause) would cause a full main-thread JSON reload
            // and re-publish of `data`, re-rendering the entire UI.
            guard let self else { return }
            if Date().timeIntervalSince(self.lastSelfWriteAt) < 3.0 { return }
            // Délai court pour laisser iCloud finir l'écriture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                // Re-check after the delay in case we wrote during the wait
                if Date().timeIntervalSince(self.lastSelfWriteAt) < 3.0 { return }
                self.iCloudSyncActive = true   // #42 — incoming iCloud change
                self.load()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    self.iCloudSyncActive = false
                }
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
        checkWeeklyReportIfNeeded()
        // Recalcule les rappels à l'activation (l'utilisateur peut avoir écrit ou non)
        let todayStr = DataStore.today
        let hasWrittenToday = !data.projects.flatMap { $0.chapters }.allSatisfy { $0.increment(for: todayStr) == 0 }
        NotificationManager.shared.scheduleEmptyDayReminderIfNeeded(hasWrittenToday: hasWrittenToday)
        NotificationManager.shared.scheduleStreakWarningIfNeeded(currentStreak: currentStreak, hasWrittenToday: hasWrittenToday)
    }

    // MARK: - Date helpers

    static var today: String {
        storageDateFormatter.string(from: Date())
    }

    static func dateString(from date: Date) -> String {
        storageDateFormatter.string(from: date)
    }

    static func parseDate(_ dateString: String) -> Date? {
        storageDateFormatter.date(from: dateString)
    }

    static func formatLongDate(_ date: Date, capitalize: Bool = false) -> String {
        let value = frenchLongDateFormatter.string(from: date)
        return capitalize ? value.prefix(1).uppercased() + value.dropFirst() : value
    }

    static func formatDate(_ date: Date) -> String {
        frenchDateFormatter.string(from: date)
    }

    static func formatMonthYear(_ date: Date) -> String {
        frenchMonthYearFormatter.string(from: date)
    }

    static func formatNumber(_ value: Int) -> String {
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

    // V5 — Tri des chapitres par progression (amélioration #8)
    var sortChaptersByProgress: Bool {
        get { UserDefaults.standard.bool(forKey: "sortChaptersByProgress") }
        set { UserDefaults.standard.set(newValue, forKey: "sortChaptersByProgress") }
    }

    func sortedChapters(_ chapters: [Chapter]) -> [Chapter] {
        if sortChaptersByProgress {
            return chapters.sorted { lhs, rhs in
                let lp: Double = lhs.goal > 0
                    ? Double(lhs.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0) / Double(lhs.goal)
                    : 0
                let rp: Double = rhs.goal > 0
                    ? Double(rhs.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0) / Double(rhs.goal)
                    : 0
                return lp < rp  // moins avancés en premier
            }
        }
        return data.sortChaptersAlphabetically
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
        if projectId == nil && chapterId == nil {
            if let cache = _dailyTotalsCache, cache.version == dataVersion {
                return cache.totals
            }
            let totals = _computeDailyTotals(projectId: nil, chapterId: nil)
            _dailyTotalsCache = (dataVersion, totals)
            return totals
        }
        if let pid = projectId, chapterId == nil {
            if let cache = _dailyTotalsByProjectCache[pid], cache.version == dataVersion {
                return cache.totals
            }
            let totals = _computeDailyTotals(projectId: pid, chapterId: nil)
            _dailyTotalsByProjectCache[pid] = (dataVersion, totals)
            return totals
        }
        return _computeDailyTotals(projectId: projectId, chapterId: chapterId)
    }

    private func _computeDailyTotals(projectId: UUID?, chapterId: UUID?) -> [String: Int] {
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
        if let c = _weeklyProgressCache, c.version == dataVersion { return c.value }
        let calendar = DataStore.gregorianCal
        var cal = calendar; cal.firstWeekday = 2
        let now = Date()
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        let totals = dailyTotals()
        var total = 0; var current = weekStart
        while current <= now {
            total += totals[DataStore.dateString(from: current)] ?? 0
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? now + 1
        }
        _weeklyProgressCache = (dataVersion, total)
        return total
    }

    var monthlyProgress: Int {
        if let c = _monthlyProgressCache, c.version == dataVersion { return c.value }
        let cal = DataStore.gregorianCal
        let now = Date()
        let totals = dailyTotals()
        var total = 0
        for i in 0..<30 {
            guard let date = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            total += totals[DataStore.dateString(from: date)] ?? 0
        }
        _monthlyProgressCache = (dataVersion, total)
        return total
    }

    var chapterProgress: Int {
        guard let chapter = activeChapter else { return 0 }
        return latestTotalsAll[chapter.id] ?? 0
    }

    /// Somme des caractères écrits dans le mois calendaire en cours (feature #70)
    var currentCalendarMonthProgress: Int {
        if let c = _currentCalMonthProgressCache, c.version == dataVersion { return c.value }
        let cal  = DataStore.gregorianCal
        let now  = Date()
        guard let monthStart = cal.dateInterval(of: .month, for: now)?.start else { return 0 }
        let startStr = DataStore.dateString(from: monthStart)
        let endStr   = DataStore.dateString(from: now)
        let value = data.projects
            .flatMap(\.chapters)
            .flatMap(\.entries)
            .filter { $0.date >= startStr && $0.date <= endStr }
            .reduce(0) { $0 + $1.totalCount }
        _currentCalMonthProgressCache = (dataVersion, value)
        return value
    }

    /// Nombre de jours avec au moins une entrée dans le mois en cours (feature #70)
    var activeDaysThisMonth: Int {
        if let c = _activeDaysThisMonthCache, c.version == dataVersion { return c.value }
        let cal  = Calendar(identifier: .gregorian)
        let now  = Date()
        guard let monthStart = cal.dateInterval(of: .month, for: now)?.start else { return 0 }
        let startStr = DataStore.dateString(from: monthStart)
        let endStr   = DataStore.dateString(from: now)
        let dates = data.projects
            .flatMap(\.chapters)
            .flatMap(\.entries)
            .filter { $0.date >= startStr && $0.date <= endStr && $0.totalCount > 0 }
            .map(\.date)
        let value = Set(dates).count
        _activeDaysThisMonthCache = (dataVersion, value)
        return value
    }

    /// Jours restants dans le mois en cours (feature #70)
    var daysRemainingInMonth: Int {
        let cal = DataStore.gregorianCal
        let now = Date()
        guard let range = cal.range(of: .day, in: .month, for: now) else { return 0 }
        let day = cal.component(.day, from: now)
        return range.count - day
    }

    /// Moyenne quotidienne sur les 7 derniers jours (jour courant inclus).
    /// Inclut les jours à zéro pour une moyenne réaliste.
    var sevenDayAverage: Int {
        let cal = DataStore.gregorianCal
        let totals = dailyTotals()
        var sum = 0
        let now = Date()
        for i in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            sum += totals[DataStore.dateString(from: date)] ?? 0
        }
        return sum / 7
    }

    /// Totaux des 7 derniers jours (du plus ancien au plus récent), pour mini-sparkline.
    var lastSevenDaysTotals: [Int] {
        let cal = DataStore.gregorianCal
        let totals = dailyTotals()
        let now = Date()
        var out: [Int] = []
        for i in (0..<7).reversed() {
            guard let date = cal.date(byAdding: .day, value: -i, to: now) else { continue }
            out.append(totals[DataStore.dateString(from: date)] ?? 0)
        }
        return out
    }

    // MARK: - Dashboard widget data (#9 / #10 / #11 / #15)

    struct WritingSpeedData {
        let avgCharsPerDay: Int   // moyenne sur jours actifs des 7 derniers jours
        let trend: Double         // ratio vs 7 jours précédents (1.0 = stable)
        let activeDaysCount: Int
        let last7Values: [Int]    // valeurs brutes J-6 → aujourd'hui
    }

    var writingSpeedData: WritingSpeedData {
        if let c = _writingSpeedDataCache, c.version == dataVersion { return c.data }
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        let now = Date()
        func dayValue(_ offset: Int) -> Int {
            guard let d = cal.date(byAdding: .day, value: -offset, to: now) else { return 0 }
            return totals[DataStore.dateString(from: d)] ?? 0
        }
        let recent = (0..<7).map { dayValue($0) }
        let prior  = (7..<14).map { dayValue($0) }
        let recentActive = recent.filter { $0 > 0 }
        let priorTotal   = prior.reduce(0, +)
        let recentTotal  = recent.reduce(0, +)
        let avg   = recentActive.isEmpty ? 0 : recentTotal / recentActive.count
        let trend: Double = priorTotal > 0 ? Double(recentTotal) / Double(priorTotal)
                          : (recentTotal > 0 ? 1.5 : 1.0)
        let result = WritingSpeedData(
            avgCharsPerDay: avg,
            trend: trend,
            activeDaysCount: recentActive.count,
            last7Values: recent.reversed()
        )
        _writingSpeedDataCache = (dataVersion, result)
        return result
    }

    struct WeekComparisonData {
        let dayLabels: [String]   // L M M J V S D
        let thisWeek:  [Int]
        let lastWeek:  [Int]
        let thisTotal: Int
        let lastTotal: Int
    }

    var weekComparisonData: WeekComparisonData {
        if let c = _weekComparisonDataCache, c.version == dataVersion { return c.data }
        let cal = DataStore.iso8601Cal
        let now = Date()
        guard let thisStart = cal.dateInterval(of: .weekOfYear, for: now)?.start else {
            return WeekComparisonData(dayLabels: [], thisWeek: [], lastWeek: [], thisTotal: 0, lastTotal: 0)
        }
        let lastStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisStart) ?? thisStart
        let totals = dailyTotals()
        var thisW = [Int](); var lastW = [Int]()
        for i in 0..<7 {
            let td = cal.date(byAdding: .day, value: i, to: thisStart) ?? now
            let ld = cal.date(byAdding: .day, value: i, to: lastStart) ?? now
            thisW.append(totals[DataStore.dateString(from: td)] ?? 0)
            lastW.append(totals[DataStore.dateString(from: ld)] ?? 0)
        }
        let result = WeekComparisonData(
            dayLabels: ["L","M","M","J","V","S","D"],
            thisWeek: thisW, lastWeek: lastW,
            thisTotal: thisW.reduce(0, +), lastTotal: lastW.reduce(0, +)
        )
        _weekComparisonDataCache = (dataVersion, result)
        return result
    }

    struct UpcomingMilestoneItem: Identifiable {
        let id: UUID
        let projectName: String
        let title: String
        let daysUntil: Int   // négatif = dépassé
        let isOverdue: Bool
    }

    func upcomingMilestonesData(limit: Int = 3) -> [UpcomingMilestoneItem] {
        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())
        return data.projects
            .filter { !$0.isArchived }
            .flatMap { proj in
                proj.milestones.filter { !$0.isCompleted }.compactMap { m -> UpcomingMilestoneItem? in
                    guard let date = DataStore.parseDate(m.date) else { return nil }
                    let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: date)).day ?? 0
                    return UpcomingMilestoneItem(id: m.id, projectName: proj.name,
                                                title: m.title, daysUntil: days, isOverdue: days < 0)
                }
            }
            .sorted { abs($0.daysUntil) < abs($1.daysUntil) }
            .prefix(limit).map { $0 }
    }

    /// Snapshot d'hier pour le widget #15
    var yesterdayTotal: Int {
        let cal = DataStore.gregorianCal
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return 0 }
        return dailyTotals()[DataStore.dateString(from: yesterday)] ?? 0
    }
    var dayBeforeYesterdayTotal: Int {
        let cal = DataStore.gregorianCal
        guard let d = cal.date(byAdding: .day, value: -2, to: Date()) else { return 0 }
        return dailyTotals()[DataStore.dateString(from: d)] ?? 0
    }

    // MARK: - Entry mutations

    func setTotalForDate(_ count: Int, for chapterId: UUID, in projectId: UUID, date: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let existingEntry = data.projects[projIdx].chapters[chapIdx].entries.first(where: { $0.date == date })
        let oldValue = existingEntry?.totalCount ?? 0
        // Early return when nothing changed: avoids @Published re-render, undo bloat,
        // and a wasted save() debounce on every keystroke that re-types the same value.
        let isToday = date == DataStore.today
        if let existingEntry, existingEntry.totalCount == count,
           existingEntry.savedAtHour != nil || !isToday {
            return
        }
        if count != oldValue {
            let entry = UndoEntry(projectId: projectId, chapterId: chapterId, date: date, oldValue: oldValue, newValue: count)
            undoStack.append(entry)
            redoStack.removeAll()
            canUndo = true; canRedo = false
            if undoStack.count > 50 { undoStack.removeFirst() }
        }
        let currentHour = Calendar.current.component(.hour, from: Date())
        if let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) {
            // #6 — Enregistrer l'édition si la valeur change
            if data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount != count {
                let rec = EntryEditRecord(timestamp: EntryEditRecord.now(),
                                         oldValue: data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount,
                                         newValue: count)
                data.projects[projIdx].chapters[chapIdx].entries[entryIdx].editHistory.append(rec)
                if data.projects[projIdx].chapters[chapIdx].entries[entryIdx].editHistory.count > 50 {
                    data.projects[projIdx].chapters[chapIdx].entries[entryIdx].editHistory.removeFirst()
                }
            }
            data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount = count
            // L'heure de saisie n'a de sens que pour une saisie du jour même
            // (pas pour une date passée ni pour un import).
            if isToday, data.projects[projIdx].chapters[chapIdx].entries[entryIdx].savedAtHour == nil {
                data.projects[projIdx].chapters[chapIdx].entries[entryIdx].savedAtHour = currentHour
            }
        } else {
            var entry = DailyEntry(date: date, totalCount: count)
            if isToday { entry.savedAtHour = currentHour }
            data.projects[projIdx].chapters[chapIdx].entries.append(entry)
        }
        // V5 — log automatique si le compteur a changé
        if count != oldValue {
            let unit = data.useWordCount ? "mots" : "car."
            let delta = count - oldValue
            let sign = delta > 0 ? "+" : ""
            let logContent = "\(DataStore.formatNumber(count)) \(unit) (\(sign)\(DataStore.formatNumber(delta)) ce jour)"
            let logEntry = ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                                           type: .wordUpdate, content: logContent)
            data.projects[projIdx].chapters[chapIdx].logEntries.append(logEntry)
            if data.projects[projIdx].chapters[chapIdx].logEntries.count > 200 {
                data.projects[projIdx].chapters[chapIdx].logEntries.removeFirst()
            }
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

    // MARK: - Chapter log entries (V5 — amélioration #9)

    func addLogEntry(_ entry: ChapterLogEntry, for chapterId: UUID, in projectId: UUID) {
        guard let pi = data.projects.firstIndex(where: { $0.id == projectId }),
              let ci = data.projects[pi].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[pi].chapters[ci].logEntries.append(entry)
        // Limite à 200 entrées par chapitre
        if data.projects[pi].chapters[ci].logEntries.count > 200 {
            data.projects[pi].chapters[ci].logEntries.removeFirst()
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

    func addProject(name: String, type: ProjectType? = nil, supervisor: String? = nil) {
        var project = Project(name: name)
        project.projectType = type
        project.supervisor  = supervisor
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

    // MARK: - Project archive / notes (#16, #17)

    func archiveProject(_ id: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == id }) else { return }
        data.projects[idx].isArchived = true
        // Deactivate if it was the active project
        if data.activeProjectId == id {
            data.activeProjectId = data.projects.first(where: { !$0.isArchived && $0.id != id })?.id
        }
        save()
    }

    func unarchiveProject(_ id: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == id }) else { return }
        data.projects[idx].isArchived = false
        save()
    }

    func updateProjectNotes(_ notes: String?, for projectId: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        data.projects[idx].notes = (trimmed?.isEmpty == false) ? trimmed : nil
        save()
    }

    // MARK: - Chapter duplication (#15)

    func duplicateChapter(_ chapterId: UUID, in projectId: UUID) {
        duplicateChapter(chapterId, from: projectId, to: projectId)
    }

    // #8 — Duplication vers un projet cible (peut être le même)
    func duplicateChapter(_ chapterId: UUID, from sourceProjectId: UUID, to targetProjectId: UUID) {
        guard let srcIdx = data.projects.firstIndex(where: { $0.id == sourceProjectId }),
              let source = data.projects[srcIdx].chapters.first(where: { $0.id == chapterId }) else { return }
        var copy = Chapter(name: source.name + " (copie)", goal: source.goal, deadline: source.deadline)
        copy.notes           = source.notes
        copy.notesPlan       = source.notesPlan
        copy.notesIdeas      = source.notesIdeas
        copy.notesBlockers   = source.notesBlockers
        copy.nextStep        = source.nextStep
        copy.draftVersion    = source.draftVersion
        copy.status          = source.status
        copy.priority        = source.priority
        copy.customTags      = source.customTags
        // Entries intentionally NOT copied
        guard let dstIdx = data.projects.firstIndex(where: { $0.id == targetProjectId }) else { return }
        data.projects[dstIdx].chapters.append(copy)
        save()
    }

    // #4 — Alerte de régression
    struct RegressionWarning {
        let todayDelta: Int
        let avg7: Int
        let ratio: Double   // todayDelta / avg7
    }

    func regressionWarning(for chapterId: UUID, in projectId: UUID, date: String) -> RegressionWarning? {
        guard let proj = data.projects.first(where: { $0.id == projectId }),
              let ch = proj.chapters.first(where: { $0.id == chapterId }) else { return nil }

        // Today's delta
        let todayTotal = ch.entryForDate(date)?.totalCount ?? 0
        let prev = ch.previousTotal(before: date)
        let todayDelta = max(0, todayTotal - prev)

        // 7-day average (excluding today)
        let cal = DataStore.gregorianCal
        guard let todayDate = DataStore.parseDate(date) else { return nil }
        var sum = 0; var count = 0
        for d in 1...7 {
            guard let day = cal.date(byAdding: .day, value: -d, to: todayDate) else { continue }
            let ds = DataStore.dateString(from: day)
            let dayTotal = ch.entryForDate(ds)?.totalCount ?? 0
            let dayPrev  = ch.previousTotal(before: ds)
            let delta    = max(0, dayTotal - dayPrev)
            if delta > 0 { sum += delta; count += 1 }
        }
        guard count >= 3 else { return nil }   // pas assez d'historique
        let avg7 = sum / count
        guard avg7 > 0, todayDelta > 0 else { return nil }
        let ratio = Double(todayDelta) / Double(avg7)
        guard ratio < 0.5 else { return nil }  // seulement si < 50% de la moyenne
        return RegressionWarning(todayDelta: todayDelta, avg7: avg7, ratio: ratio)
    }

    // MARK: - Chapter reorder (#18)

    func moveChapter(_ chapterId: UUID, direction: Int, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let newIdx = cIdx + direction
        guard newIdx >= 0, newIdx < data.projects[pIdx].chapters.count else { return }
        data.projects[pIdx].chapters.swapAt(cIdx, newIdx)
        save()
    }

    // MARK: - Milestone CRUD (V5)

    func addMilestone(_ milestone: Milestone, to projectId: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[idx].milestones.append(milestone)
        save()
    }

    func updateMilestone(_ milestone: Milestone, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let mIdx = data.projects[pIdx].milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        data.projects[pIdx].milestones[mIdx] = milestone
        save()
    }

    func toggleMilestone(_ milestoneId: UUID, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let mIdx = data.projects[pIdx].milestones.firstIndex(where: { $0.id == milestoneId }) else { return }
        let wasCompleted = data.projects[pIdx].milestones[mIdx].isCompleted
        data.projects[pIdx].milestones[mIdx].isCompleted.toggle()
        // #28 — si on vient de compléter un jalon récurrent, créer la prochaine occurrence
        if !wasCompleted, let recurrence = data.projects[pIdx].milestones[mIdx].recurrence {
            let completed = data.projects[pIdx].milestones[mIdx]
            if let nextDate = nextRecurrenceDate(from: completed.date, recurrence: recurrence) {
                let next = Milestone(
                    id: UUID(),
                    title: completed.title,
                    date: DataStore.dateString(from: nextDate),
                    isCompleted: false,
                    notes: completed.notes,
                    recurrence: recurrence
                )
                data.projects[pIdx].milestones.append(next)
            }
        }
        save()
    }

    private func nextRecurrenceDate(from dateStr: String, recurrence: MilestoneRecurrence) -> Date? {
        guard let date = DataStore.parseDate(dateStr) else { return nil }
        switch recurrence {
        case .weekly:  return DataStore.gregorianCal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return DataStore.gregorianCal.date(byAdding: .month,      value: 1, to: date)
        }
    }

    func deleteMilestone(_ milestoneId: UUID, from projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[pIdx].milestones.removeAll { $0.id == milestoneId }
        save()
    }

    /// Tous les jalons de tous les projets, triés par date.
    var allMilestonesSorted: [(project: Project, milestone: Milestone)] {
        if let c = _allMilestonesSortedCache, c.version == dataVersion { return c.items }
        let items = data.projects.flatMap { project in
            project.milestones.map { (project: project, milestone: $0) }
        }
        .sorted { a, b in a.milestone.date < b.milestone.date }
        _allMilestonesSortedCache = (dataVersion, items)
        return items
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

    func addFolder(name: String, parentId: UUID? = nil) {
        var folder = ProjectFolder(name: name)
        // Valide que le parent existe encore (sinon : créé à la racine)
        if let pid = parentId, data.folders.contains(where: { $0.id == pid }) {
            folder.parentId = pid
        }
        data.folders.append(folder)
        save()
    }

    /// À la suppression d'un dossier : promeut ses enfants directs (sous-dossiers + projets)
    /// au niveau du parent du dossier supprimé (ou racine si pas de parent).
    func deleteFolder(id: UUID, keepProjects: Bool = true) {
        guard let folder = data.folders.first(where: { $0.id == id }) else { return }
        let promotedParentId = folder.parentId

        // 1) Sous-dossiers directs → promus au parent du dossier supprimé
        for i in data.folders.indices where data.folders[i].parentId == id {
            data.folders[i].parentId = promotedParentId
        }

        // 2) Projets : si on garde les projets, ils sont rattachés au parent (ou à la racine)
        if keepProjects {
            for projId in folder.projectIds {
                if let idx = data.projects.firstIndex(where: { $0.id == projId }) {
                    data.projects[idx].folderId = promotedParentId
                }
            }
            if let parentIdx = promotedParentId.flatMap({ pid in
                data.folders.firstIndex(where: { $0.id == pid })
            }) {
                for projId in folder.projectIds where !data.folders[parentIdx].projectIds.contains(projId) {
                    data.folders[parentIdx].projectIds.append(projId)
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

    /// Déplace un dossier de projets dans un dossier parent (ou nil = racine).
    /// Refuse les cycles : on ne peut pas mettre un dossier dans son propre descendant.
    func moveProjectFolder(_ folderId: UUID, toParent parentId: UUID?) {
        guard let idx = data.folders.firstIndex(where: { $0.id == folderId }),
              folderId != parentId else { return }
        if let pid = parentId, isDescendantProjectFolder(pid, of: folderId) { return }
        // Valide le parent
        if let pid = parentId, !data.folders.contains(where: { $0.id == pid }) { return }
        data.folders[idx].parentId = parentId
        save()
    }

    /// Vrai si `candidateId` est un descendant (direct ou indirect) de `ancestorId`.
    private func isDescendantProjectFolder(_ candidateId: UUID, of ancestorId: UUID) -> Bool {
        var current: UUID? = candidateId
        while let c = current {
            if c == ancestorId { return true }
            current = data.folders.first(where: { $0.id == c })?.parentId
        }
        return false
    }

    /// Sous-dossiers directs (parentId == parent) d'un dossier de projets, ou racines si parent == nil.
    func childProjectFolders(of parentId: UUID?) -> [ProjectFolder] {
        data.folders.filter { $0.parentId == parentId }
    }

    /// Déplace un dossier de projets juste avant un autre dossier (et aligne son parentId
    /// sur celui de la cible, pour rester cohérent avec l'imbrication).
    func moveProjectFolderById(_ sourceId: UUID, before targetId: UUID) {
        guard sourceId != targetId,
              let fromIdx = data.folders.firstIndex(where: { $0.id == sourceId }) else { return }
        if isDescendantProjectFolder(targetId, of: sourceId) { return }
        let targetParent = data.folders.first(where: { $0.id == targetId })?.parentId
        var folder = data.folders.remove(at: fromIdx)
        folder.parentId = targetParent
        let insertIdx = data.folders.firstIndex(where: { $0.id == targetId }) ?? data.folders.count
        data.folders.insert(folder, at: insertIdx)
        save()
    }

    /// Déplace un dossier de projets en queue de liste (racine).
    func moveProjectFolderToEnd(_ sourceId: UUID) {
        guard let fromIdx = data.folders.firstIndex(where: { $0.id == sourceId }) else { return }
        var folder = data.folders.remove(at: fromIdx)
        folder.parentId = nil
        data.folders.append(folder)
        save()
    }

    /// Renommage rapide d'un projet (utilisé par l'inline rename)
    func renameProject(_ projectId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[idx].name = trimmed
        save()
    }

    /// Renommage rapide d'un chapitre
    func renameChapter(_ chapterId: UUID, in projectId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[pIdx].chapters[cIdx].name = trimmed
        save()
    }

    // MARK: - Export / import sous-arbre

    enum SubtreeExportError: Error { case projectNotFound, chapterNotFound, decode, invalidPayload }

    /// Wrapper unifié pour exporter un projet, un dossier (avec ses chapitres) ou un chapitre seul.
    struct SubtreeExportPayload: Codable {
        let kind: String   // "project" | "chapterFolder" | "chapter"
        let exportedAt: String
        let version: Int
        let project: Project?
        let chapterFolder: ChapterFolder?
        let chapters: [Chapter]?
        let chapter: Chapter?
    }

    func exportProjectPayload(_ projectId: UUID) throws -> Data {
        guard let proj = data.projects.first(where: { $0.id == projectId }) else { throw SubtreeExportError.projectNotFound }
        let payload = SubtreeExportPayload(kind: "project", exportedAt: DataStore.dateString(from: Date()),
                                           version: 1, project: proj, chapterFolder: nil, chapters: nil, chapter: nil)
        return try JSONEncoder().encode(payload)
    }

    func exportChapterFolderPayload(_ folderId: UUID, in projectId: UUID) throws -> Data {
        guard let proj = data.projects.first(where: { $0.id == projectId }),
              let folder = proj.chapterFolders.first(where: { $0.id == folderId }) else { throw SubtreeExportError.projectNotFound }
        let chapters = proj.chapters.filter { $0.chapterFolderId == folderId }
        let payload = SubtreeExportPayload(kind: "chapterFolder", exportedAt: DataStore.dateString(from: Date()),
                                           version: 1, project: nil, chapterFolder: folder, chapters: chapters, chapter: nil)
        return try JSONEncoder().encode(payload)
    }

    func exportChapterPayload(_ chapterId: UUID, in projectId: UUID) throws -> Data {
        guard let proj = data.projects.first(where: { $0.id == projectId }),
              let chap = proj.chapters.first(where: { $0.id == chapterId }) else { throw SubtreeExportError.chapterNotFound }
        let payload = SubtreeExportPayload(kind: "chapter", exportedAt: DataStore.dateString(from: Date()),
                                           version: 1, project: nil, chapterFolder: nil, chapters: nil, chapter: chap)
        return try JSONEncoder().encode(payload)
    }

    /// Importe un payload exporté. `intoProjectId` est utilisé pour les payloads chapitre/dossier
    /// (ils ont besoin d'un projet cible). Pour un projet, il est ajouté avec un nouvel UUID.
    @discardableResult
    func importSubtreePayload(_ data: Data, intoProjectId: UUID?) throws -> String {
        let payload = try JSONDecoder().decode(SubtreeExportPayload.self, from: data)
        switch payload.kind {
        case "project":
            guard var p = payload.project else { throw SubtreeExportError.invalidPayload }
            p = renumberProject(p)
            self.data.projects.append(p)
            save()
            return "Projet « \(p.name) » importé."
        case "chapterFolder":
            guard let folder = payload.chapterFolder, let chapters = payload.chapters,
                  let pid = intoProjectId,
                  let pIdx = self.data.projects.firstIndex(where: { $0.id == pid })
            else { throw SubtreeExportError.invalidPayload }
            var newFolder = folder
            newFolder.id = UUID()
            // Le parent vient d'un autre arbre : on rattache à la racine.
            newFolder.parentId = nil
            self.data.projects[pIdx].chapterFolders.append(newFolder)
            for c in chapters {
                var nc = c
                nc.id = UUID()
                nc.chapterFolderId = newFolder.id
                self.data.projects[pIdx].chapters.append(nc)
            }
            save()
            return "Dossier « \(newFolder.name) » + \(chapters.count) chapitres importés."
        case "chapter":
            guard let c = payload.chapter,
                  let pid = intoProjectId,
                  let pIdx = self.data.projects.firstIndex(where: { $0.id == pid })
            else { throw SubtreeExportError.invalidPayload }
            var nc = c
            nc.id = UUID()
            nc.chapterFolderId = nil
            self.data.projects[pIdx].chapters.append(nc)
            save()
            return "Chapitre « \(nc.name) » importé."
        default:
            throw SubtreeExportError.invalidPayload
        }
    }

    /// Re-numérote un projet importé : nouvel UUID projet, nouveaux UUIDs chapitres / folders,
    /// remap des chapterFolderId et parentId des dossiers vers les nouveaux ids.
    private func renumberProject(_ project: Project) -> Project {
        var p = project
        p.id = UUID()
        var folderMap: [UUID: UUID] = [:]
        // Étape 1 : régénérer les ids ; on remappera les parentId en étape 2 (l'ordre du tableau peut placer un parent après son enfant).
        p.chapterFolders = p.chapterFolders.map { f in
            var nf = f; nf.id = UUID(); folderMap[f.id] = nf.id; return nf
        }
        p.chapterFolders = p.chapterFolders.map { f in
            var nf = f
            if let old = f.parentId { nf.parentId = folderMap[old] }
            return nf
        }
        p.chapters = p.chapters.map { c in
            var nc = c; nc.id = UUID()
            if let old = c.chapterFolderId { nc.chapterFolderId = folderMap[old] }
            return nc
        }
        p.activeChapterId = nil
        return p
    }

    /// Renommage rapide d'un dossier de projets
    func renameProjectFolder(_ folderId: UUID, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = data.folders.firstIndex(where: { $0.id == folderId }) else { return }
        data.folders[idx].name = trimmed
        save()
    }

    /// Archive (ou désarchive) un chapitre. Préserve toutes ses entrées.
    func setChapterArchived(_ archived: Bool, chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].isArchived = archived
        if archived, data.projects[projIdx].activeChapterId == chapterId {
            // Sélectionner un autre chapitre actif si on archive le courant
            data.projects[projIdx].activeChapterId = data.projects[projIdx].chapters
                .first(where: { !$0.isArchived && $0.id != chapterId })?.id
        }
        save()
    }

    /// Renvoie l'ensemble des chapitres archivés du projet (utilisé par la section Archives).
    func archivedChapters(in projectId: UUID) -> [Chapter] {
        data.projects.first(where: { $0.id == projectId })?.chapters.filter { $0.isArchived } ?? []
    }

    /// Bascule l'épinglage d'un projet
    func toggleProjectPinned(_ projectId: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        data.projects[idx].isPinned.toggle()
        save()
    }

    /// Bascule l'épinglage d'un chapitre
    func toggleChapterPinned(_ chapterId: UUID, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[pIdx].chapters[cIdx].isPinned.toggle()
        save()
    }

    /// Tous les chapitres épinglés (avec leur projet) à travers tous les projets
    func allPinnedChapters() -> [(project: Project, chapter: Chapter)] {
        data.projects.flatMap { proj in
            proj.chapters.filter { $0.isPinned && !$0.isArchived }.map { (proj, $0) }
        }
    }

    /// Tous les projets épinglés (non-archivés)
    func allPinnedProjects() -> [Project] {
        data.projects.filter { $0.isPinned && !$0.isArchived }
    }

    /// Plie/déplie tous les dossiers de chapitres d'un projet (V — utilisateur)
    func setAllChapterFoldersExpanded(_ expanded: Bool, in projectId: UUID) {
        guard let idx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        for i in data.projects[idx].chapterFolders.indices {
            data.projects[idx].chapterFolders[i].isExpanded = expanded
        }
        save()
    }

    func toggleFolderExpanded(_ folderId: UUID) {
        guard let idx = data.folders.firstIndex(where: { $0.id == folderId }) else { return }
        data.folders[idx].isExpanded.toggle()
        save()
    }

    // MARK: - Chapter mutations

    func addChapter(name: String, goal: Int, deadline: String? = nil, notes: String? = nil, draftVersion: Int = 1, to projectId: UUID, chapterFolderId: UUID? = nil) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        var chapter = Chapter(name: name, goal: goal, deadline: deadline)
        chapter.notes           = notes
        chapter.draftVersion    = draftVersion
        chapter.chapterFolderId = chapterFolderId
        data.projects[projIdx].chapters.append(chapter)
        if data.projects[projIdx].activeChapterId == nil {
            data.projects[projIdx].activeChapterId = chapter.id
        }
        save()
    }

    // MARK: - Chapter folder mutations

    func addChapterFolder(name: String, to projectId: UUID, parentId: UUID? = nil) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        var folder = ChapterFolder(name: name)
        if let pid = parentId, data.projects[projIdx].chapterFolders.contains(where: { $0.id == pid }) {
            folder.parentId = pid
        }
        data.projects[projIdx].chapterFolders.append(folder)
        save()
    }

    /// À la suppression : promeut sous-dossiers et chapitres au parent du dossier supprimé.
    func deleteChapterFolder(id folderId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }) else { return }
        let promotedParentId = data.projects[projIdx].chapterFolders
            .first(where: { $0.id == folderId })?.parentId

        // 1) Sous-dossiers directs → parent du dossier supprimé
        for i in data.projects[projIdx].chapterFolders.indices
            where data.projects[projIdx].chapterFolders[i].parentId == folderId {
            data.projects[projIdx].chapterFolders[i].parentId = promotedParentId
        }
        // 2) Chapitres rattachés à ce dossier → parent (peut être nil = racine du projet)
        for chapIdx in data.projects[projIdx].chapters.indices {
            if data.projects[projIdx].chapters[chapIdx].chapterFolderId == folderId {
                data.projects[projIdx].chapters[chapIdx].chapterFolderId = promotedParentId
            }
        }
        data.projects[projIdx].chapterFolders.removeAll { $0.id == folderId }
        save()
    }

    /// Déplace un dossier de chapitres dans un dossier parent (ou nil = racine du projet).
    /// Refuse les cycles.
    func moveChapterFolder(_ folderId: UUID, toParent parentId: UUID?, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let idx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == folderId }),
              folderId != parentId else { return }
        if let pid = parentId,
           isDescendantChapterFolder(pid, of: folderId, in: projectId) { return }
        if let pid = parentId,
           !data.projects[projIdx].chapterFolders.contains(where: { $0.id == pid }) { return }
        data.projects[projIdx].chapterFolders[idx].parentId = parentId
        save()
    }

    private func isDescendantChapterFolder(_ candidateId: UUID, of ancestorId: UUID, in projectId: UUID) -> Bool {
        guard let proj = data.projects.first(where: { $0.id == projectId }) else { return false }
        var current: UUID? = candidateId
        while let c = current {
            if c == ancestorId { return true }
            current = proj.chapterFolders.first(where: { $0.id == c })?.parentId
        }
        return false
    }

    /// Sous-dossiers de chapitres ayant ce parent (ou racine si parent == nil) dans un projet.
    func childChapterFolders(of parentId: UUID?, in projectId: UUID) -> [ChapterFolder] {
        guard let proj = data.projects.first(where: { $0.id == projectId }) else { return [] }
        return proj.chapterFolders.filter { $0.parentId == parentId }
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

    /// Déplace un dossier juste avant un autre dossier dans le même projet
    /// (et aligne son parentId sur celui de la cible).
    func moveChapterFolderById(_ sourceId: UUID, before targetId: UUID, in projectId: UUID) {
        guard sourceId != targetId,
              let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let fromIdx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == sourceId }) else { return }
        if isDescendantChapterFolder(targetId, of: sourceId, in: projectId) { return }
        let targetParent = data.projects[projIdx].chapterFolders.first(where: { $0.id == targetId })?.parentId
        var folder = data.projects[projIdx].chapterFolders.remove(at: fromIdx)
        folder.parentId = targetParent
        let insertIdx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == targetId })
                        ?? data.projects[projIdx].chapterFolders.count
        data.projects[projIdx].chapterFolders.insert(folder, at: insertIdx)
        save()
    }

    /// Déplace un dossier à la fin de la liste (racine du projet).
    func moveChapterFolderToEnd(_ sourceId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let fromIdx = data.projects[projIdx].chapterFolders.firstIndex(where: { $0.id == sourceId }) else { return }
        var folder = data.projects[projIdx].chapterFolders.remove(at: fromIdx)
        folder.parentId = nil
        data.projects[projIdx].chapterFolders.append(folder)
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
        let oldStatus = data.projects[projIdx].chapters[chapIdx].status
        data.projects[projIdx].chapters[chapIdx].status = status
        if status == .termine {
            data.projects[projIdx].chapters[chapIdx].isCompleted = true
        } else if status != nil && status != .termine {
            data.projects[projIdx].chapters[chapIdx].isCompleted = false
        }
        // V5 — log automatique du changement de statut
        if status != oldStatus {
            let from = oldStatus?.label ?? "Non défini"
            let to   = status?.label   ?? "Non défini"
            let logEntry = ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                                           type: .statusChange,
                                           content: "Statut : \(from) → \(to)")
            data.projects[projIdx].chapters[chapIdx].logEntries.append(logEntry)
            if data.projects[projIdx].chapters[chapIdx].logEntries.count > 200 {
                data.projects[projIdx].chapters[chapIdx].logEntries.removeFirst()
            }
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

    /// Renvoie l'id du projet qui contient le chapitre donné, ou nil.
    func projectId(containingChapter chapterId: UUID) -> UUID? {
        for project in data.projects {
            if project.chapters.contains(where: { $0.id == chapterId }) { return project.id }
        }
        return nil
    }

    /// Déplace un chapitre (et toutes ses entrées / progression) vers un autre projet.
    /// Si `folderId` est fourni et existe dans la cible, le chapitre y est placé,
    /// sinon il est placé à la racine du projet. Insertion à la fin par défaut.
    @discardableResult
    func moveChapterToProject(_ chapterId: UUID,
                              from sourceProjectId: UUID,
                              to targetProjectId: UUID,
                              folderId: UUID? = nil,
                              beforeChapterId: UUID? = nil) -> Bool {
        if sourceProjectId == targetProjectId {
            // Même projet : éventuel changement de groupe + réordonnancement
            moveChapterToFolder(chapterId, folderId: folderId, in: sourceProjectId)
            if let target = beforeChapterId {
                moveChapterById(chapterId, before: target, in: sourceProjectId)
            }
            return true
        }
        guard let srcIdx = data.projects.firstIndex(where: { $0.id == sourceProjectId }),
              let chapIdx = data.projects[srcIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let dstIdx = data.projects.firstIndex(where: { $0.id == targetProjectId }) else { return false }
        var chapter = data.projects[srcIdx].chapters.remove(at: chapIdx)
        if let fid = folderId,
           data.projects[dstIdx].chapterFolders.contains(where: { $0.id == fid }) {
            chapter.chapterFolderId = fid
        } else {
            chapter.chapterFolderId = nil
        }
        // Si c'était le chapitre actif du projet source, nettoyer
        if data.projects[srcIdx].activeChapterId == chapterId {
            data.projects[srcIdx].activeChapterId = data.projects[srcIdx].chapters.first?.id
        }
        if let target = beforeChapterId,
           let insertIdx = data.projects[dstIdx].chapters.firstIndex(where: { $0.id == target }) {
            data.projects[dstIdx].chapters.insert(chapter, at: insertIdx)
        } else {
            data.projects[dstIdx].chapters.append(chapter)
        }
        save()
        return true
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

    // MARK: - Suivi des relectures directeur (#1)

    /// Démarre un nouveau cycle de relecture (chapitre envoyé au directeur).
    /// `expectedReturnDate` est une date "yyyy-MM-dd" optionnelle.
    func sendChapterForReview(chapterId: UUID, in projectId: UUID,
                              expectedReturnDate: String? = nil) {
        // Fige l'état avant l'envoi pour pouvoir y revenir si le directeur conteste
        _ = saveCheckpoint(chapterId: chapterId, in: projectId, label: "",
                           trigger: .beforeReview)
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let draftVersion = data.projects[projIdx].chapters[chapIdx].draftVersion
        let review = SupervisorReview(
            state: .sent,
            sentDate: DataStore.today,
            expectedReturnDate: expectedReturnDate,
            draftVersion: draftVersion
        )
        data.projects[projIdx].chapters[chapIdx].supervisorReviews.append(review)
        // Log dans l'historique du chapitre
        data.projects[projIdx].chapters[chapIdx].logEntries.append(
            ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                            type: .statusChange,
                            content: "Envoyé en relecture (draft v\(draftVersion))")
        )
        save()
    }

    /// Le directeur a renvoyé son feedback.
    func markChapterReviewReceived(chapterId: UUID, in projectId: UUID,
                                   feedbackNotes: String? = nil) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let revIdx  = data.projects[projIdx].chapters[chapIdx].supervisorReviews.indices.last else { return }
        data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].state = .received
        data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].receivedDate = DataStore.today
        if let notes = feedbackNotes, !notes.isEmpty {
            data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].feedbackNotes = notes
        }
        data.projects[projIdx].chapters[chapIdx].logEntries.append(
            ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                            type: .statusChange,
                            content: "Retour directeur reçu")
        )
        save()
    }

    /// Marque le feedback comme intégré — termine le cycle.
    /// Incrémente automatiquement `draftVersion` pour le prochain cycle.
    func markChapterReviewAddressed(chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let revIdx  = data.projects[projIdx].chapters[chapIdx].supervisorReviews.indices.last else { return }
        data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].state = .addressed
        data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].addressedDate = DataStore.today
        data.projects[projIdx].chapters[chapIdx].draftVersion += 1
        data.projects[projIdx].chapters[chapIdx].logEntries.append(
            ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                            type: .draftBump,
                            content: "Feedback intégré → draft v\(data.projects[projIdx].chapters[chapIdx].draftVersion)")
        )
        save()
        // Fige l'état nouvellement intégré
        _ = saveCheckpoint(chapterId: chapterId, in: projectId, label: "",
                           trigger: .afterAddressed)
    }

    /// Met à jour les notes de feedback du cycle courant.
    func updateChapterReviewNotes(chapterId: UUID, in projectId: UUID, notes: String) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let revIdx  = data.projects[projIdx].chapters[chapIdx].supervisorReviews.indices.last else { return }
        data.projects[projIdx].chapters[chapIdx].supervisorReviews[revIdx].feedbackNotes = notes
        save()
    }

    /// Annule le dernier cycle de relecture (utile en cas d'erreur de manipulation).
    func cancelLastChapterReview(chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              !data.projects[projIdx].chapters[chapIdx].supervisorReviews.isEmpty else { return }
        data.projects[projIdx].chapters[chapIdx].supervisorReviews.removeLast()
        save()
    }

    /// Tous les chapitres en attente de retour directeur (état `.sent`).
    var chaptersAwaitingReview: [(project: Project, chapter: Chapter)] {
        data.projects.flatMap { project in
            project.chapters.compactMap { chapter -> (project: Project, chapter: Chapter)? in
                chapter.reviewState == .sent ? (project, chapter) : nil
            }
        }
    }

    /// Tous les chapitres avec un retour reçu mais pas encore intégré (état `.received`).
    var chaptersWithUnaddressedFeedback: [(project: Project, chapter: Chapter)] {
        data.projects.flatMap { project in
            project.chapters.compactMap { chapter -> (project: Project, chapter: Chapter)? in
                chapter.reviewState == .received ? (project, chapter) : nil
            }
        }
    }

    // MARK: - Points de sauvegarde du chapitre (#3)

    /// Crée un point de sauvegarde figeant l'état narratif courant du chapitre.
    @discardableResult
    func saveCheckpoint(chapterId: UUID, in projectId: UUID,
                        label: String,
                        trigger: ChapterCheckpoint.Trigger = .manual) -> ChapterCheckpoint? {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return nil }
        let chapter = data.projects[projIdx].chapters[chapIdx]
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = trimmedLabel.isEmpty ? defaultCheckpointLabel(for: trigger, draft: chapter.draftVersion) : trimmedLabel
        let checkpoint = ChapterCheckpoint(
            timestamp:     ChapterLogEntry.nowTimestamp(),
            draftVersion:  chapter.draftVersion,
            label:         finalLabel,
            notes:         chapter.notes,
            notesPlan:     chapter.notesPlan,
            notesIdeas:    chapter.notesIdeas,
            notesBlockers: chapter.notesBlockers,
            nextStep:      chapter.nextStep,
            latestTotal:   latestTotal(for: chapterId, in: projectId),
            trigger:       trigger
        )
        data.projects[projIdx].chapters[chapIdx].checkpoints.append(checkpoint)
        data.projects[projIdx].chapters[chapIdx].logEntries.append(
            ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                            type: .manual,
                            content: "Point de sauvegarde : \(finalLabel)")
        )
        save()
        return checkpoint
    }

    /// Supprime un point de sauvegarde.
    func deleteCheckpoint(checkpointId: UUID, chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].checkpoints.removeAll { $0.id == checkpointId }
        save()
    }

    /// Restaure les champs narratifs depuis un checkpoint (ne touche pas aux entries/log/draftVersion).
    /// Avant restauration, un checkpoint "Avant restauration" est créé automatiquement.
    func restoreCheckpoint(checkpointId: UUID, chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let checkpoint = data.projects[projIdx].chapters[chapIdx].checkpoints.first(where: { $0.id == checkpointId }) else { return }
        // Sauvegarde l'état actuel avant la restauration (filet de sécurité)
        let beforeRestore = ChapterCheckpoint(
            timestamp:     ChapterLogEntry.nowTimestamp(),
            draftVersion:  data.projects[projIdx].chapters[chapIdx].draftVersion,
            label:         "Avant restauration de « \(checkpoint.label) »",
            notes:         data.projects[projIdx].chapters[chapIdx].notes,
            notesPlan:     data.projects[projIdx].chapters[chapIdx].notesPlan,
            notesIdeas:    data.projects[projIdx].chapters[chapIdx].notesIdeas,
            notesBlockers: data.projects[projIdx].chapters[chapIdx].notesBlockers,
            nextStep:      data.projects[projIdx].chapters[chapIdx].nextStep,
            latestTotal:   latestTotal(for: chapterId, in: projectId),
            trigger:       .manual
        )
        data.projects[projIdx].chapters[chapIdx].checkpoints.append(beforeRestore)
        // Restauration des champs narratifs
        data.projects[projIdx].chapters[chapIdx].notes         = checkpoint.notes
        data.projects[projIdx].chapters[chapIdx].notesPlan     = checkpoint.notesPlan
        data.projects[projIdx].chapters[chapIdx].notesIdeas    = checkpoint.notesIdeas
        data.projects[projIdx].chapters[chapIdx].notesBlockers = checkpoint.notesBlockers
        data.projects[projIdx].chapters[chapIdx].nextStep      = checkpoint.nextStep
        data.projects[projIdx].chapters[chapIdx].logEntries.append(
            ChapterLogEntry(timestamp: ChapterLogEntry.nowTimestamp(),
                            type: .manual,
                            content: "Restauration du point « \(checkpoint.label) »")
        )
        save()
    }

    private func defaultCheckpointLabel(for trigger: ChapterCheckpoint.Trigger, draft: Int) -> String {
        switch trigger {
        case .manual:         return "Draft v\(draft)"
        case .beforeReview:   return "Avant envoi en relecture (v\(draft))"
        case .afterAddressed: return "Après intégration (v\(draft))"
        }
    }

    // MARK: - Visibilité des widgets sur le tableau de bord d'un chapitre

    /// Active/désactive l'affichage d'un widget sur le tableau de bord d'un chapitre.
    func toggleChapterWidgetHidden(_ widgetKey: String, chapterId: UUID, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        if let idx = data.projects[pIdx].chapters[cIdx].hiddenWidgets.firstIndex(of: widgetKey) {
            data.projects[pIdx].chapters[cIdx].hiddenWidgets.remove(at: idx)
        } else {
            data.projects[pIdx].chapters[cIdx].hiddenWidgets.append(widgetKey)
        }
        save()
    }

    /// Tout réafficher pour un chapitre (utile pour le bouton « Tout réafficher »).
    func resetChapterWidgetsVisibility(chapterId: UUID, in projectId: UUID) {
        guard let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[pIdx].chapters[cIdx].hiddenWidgets.removeAll()
        save()
    }

    // MARK: - Plan de bataille hebdomadaire (#1)

    /// Le plan correspondant à la semaine ISO en cours, créé à la volée si besoin.
    var currentWeeklyPlan: WeeklyPlan? {
        data.weeklyPlans.first { $0.weekKey == DataStore.currentWeekKey }
    }

    @discardableResult
    func ensureCurrentWeeklyPlan() -> WeeklyPlan {
        if let existing = currentWeeklyPlan { return existing }
        let plan = WeeklyPlan(weekKey: DataStore.currentWeekKey, items: [], createdAt: DataStore.today)
        data.weeklyPlans.append(plan)
        save()
        return plan
    }

    func addWeeklyPlanItem(text: String, chapterId: UUID? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = ensureCurrentWeeklyPlan()
        guard let idx = data.weeklyPlans.firstIndex(where: { $0.weekKey == DataStore.currentWeekKey }) else { return }
        data.weeklyPlans[idx].items.append(WeeklyPlanItem(text: trimmed, chapterId: chapterId))
        save()
    }

    func toggleWeeklyPlanItem(itemId: UUID) {
        guard let pIdx = data.weeklyPlans.firstIndex(where: { $0.weekKey == DataStore.currentWeekKey }),
              let iIdx = data.weeklyPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else { return }
        data.weeklyPlans[pIdx].items[iIdx].isDone.toggle()
        data.weeklyPlans[pIdx].items[iIdx].doneDate = data.weeklyPlans[pIdx].items[iIdx].isDone ? DataStore.today : nil
        save()
    }

    func updateWeeklyPlanItemText(itemId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let pIdx = data.weeklyPlans.firstIndex(where: { $0.weekKey == DataStore.currentWeekKey }),
              let iIdx = data.weeklyPlans[pIdx].items.firstIndex(where: { $0.id == itemId }) else { return }
        data.weeklyPlans[pIdx].items[iIdx].text = trimmed
        save()
    }

    func deleteWeeklyPlanItem(itemId: UUID) {
        guard let pIdx = data.weeklyPlans.firstIndex(where: { $0.weekKey == DataStore.currentWeekKey }) else { return }
        data.weeklyPlans[pIdx].items.removeAll { $0.id == itemId }
        save()
    }

    /// Le plan de la semaine précédente, pour rétrospective dominicale.
    var lastWeekPlan: WeeklyPlan? {
        var cal = Calendar(identifier: .iso8601); cal.firstWeekday = 2
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: Date()),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start) else { return nil }
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: lastWeekStart)
        let key = String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 2026, comps.weekOfYear ?? 1)
        return data.weeklyPlans.first { $0.weekKey == key }
    }

    // MARK: - Niveau d'énergie quotidien (#4)

    /// Met à jour le niveau d'énergie (1-5) pour l'entrée du jour du chapitre actif.
    func setEnergyLevel(_ level: Int?, for date: String, chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) else { return }
        let clamped = level.map { max(1, min(5, $0)) }
        data.projects[projIdx].chapters[chapIdx].entries[entryIdx].energyLevel = clamped
        save()
    }

    /// Renvoie le niveau d'énergie le plus élevé enregistré sur la date donnée tous chapitres confondus.
    func energyLevel(for date: String) -> Int? {
        var max: Int? = nil
        for project in data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries where entry.date == date {
                    if let lvl = entry.energyLevel {
                        if max == nil || lvl > max! { max = lvl }
                    }
                }
            }
        }
        return max
    }

    /// Tous les couples (date, énergie moyenne) sur les `days` derniers jours.
    func energyHistory(days: Int = 30) -> [(date: String, energy: Int)] {
        var perDate: [String: (sum: Int, count: Int)] = [:]
        for project in data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    guard let lvl = entry.energyLevel else { continue }
                    let acc = perDate[entry.date] ?? (0, 0)
                    perDate[entry.date] = (acc.sum + lvl, acc.count + 1)
                }
            }
        }
        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())
        var result: [(String, Int)] = []
        for offset in 0..<days {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dateStr = DataStore.dateString(from: d)
            if let acc = perDate[dateStr], acc.count > 0 {
                result.append((dateStr, acc.sum / acc.count))
            }
        }
        return result.reversed()
    }

    // MARK: - Jours de repos planifiés (#5)

    func isRestDay(_ date: String) -> Bool { data.restDays.contains(date) }

    func toggleRestDay(_ date: String) {
        if let idx = data.restDays.firstIndex(of: date) {
            data.restDays.remove(at: idx)
        } else {
            data.restDays.append(date)
        }
        save()
    }

    // MARK: - Notes de soutenance (#2)

    func addDefenseNote(chapterId: UUID, in projectId: UUID, kind: DefenseNote.Kind, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let note = DefenseNote(kind: kind, text: trimmed, createdAt: DataStore.today)
        data.projects[projIdx].chapters[chapIdx].defenseNotes.append(note)
        save()
    }

    func updateDefenseNote(noteId: UUID, chapterId: UUID, in projectId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }),
              let nIdx = data.projects[projIdx].chapters[chapIdx].defenseNotes.firstIndex(where: { $0.id == noteId }) else { return }
        data.projects[projIdx].chapters[chapIdx].defenseNotes[nIdx].text = trimmed
        save()
    }

    func deleteDefenseNote(noteId: UUID, chapterId: UUID, in projectId: UUID) {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        data.projects[projIdx].chapters[chapIdx].defenseNotes.removeAll { $0.id == noteId }
        save()
    }

    /// Toutes les notes de soutenance du projet actif, indexées par chapitre.
    var allDefenseNotesForActiveProject: [(chapter: Chapter, notes: [DefenseNote])] {
        guard let project = activeProject else { return [] }
        return project.chapters.compactMap { chapter in
            chapter.defenseNotes.isEmpty ? nil : (chapter, chapter.defenseNotes)
        }
    }

    // MARK: - Projections de date de fin (#7)

    struct VelocityProjection {
        let velocityWindow: Int      // jours pris en compte
        let avgPerDay: Double        // caractères / jour
        let estimatedDate: Date?     // nil si vitesse 0
    }

    /// Calcule trois projections de date de fin :
    /// - last60 : moyenne des 60 derniers jours
    /// - last30 : moyenne des 30 derniers jours
    /// - ideal  : basé sur l'objectif quotidien `dailyGoal`
    /// Le "reste à écrire" = somme des (chapter.goal - latestTotal) pour les chapitres non terminés.
    func velocityProjections() -> (last60: VelocityProjection, last30: VelocityProjection, ideal: VelocityProjection) {
        // Reste à écrire (sur tous les projets non archivés)
        var remaining = 0
        for project in data.projects where !project.isArchived {
            for chapter in project.chapters where !chapter.isCompleted {
                let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                remaining += max(0, chapter.goal - latest)
            }
        }

        let cal = DataStore.gregorianCal
        let today = cal.startOfDay(for: Date())
        let totals = dailyTotals()

        func avgOver(days: Int) -> Double {
            var sum = 0
            for offset in 1...days {
                guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                sum += totals[DataStore.dateString(from: d)] ?? 0
            }
            return Double(sum) / Double(days)
        }

        func project(avg: Double) -> Date? {
            guard avg > 0, remaining > 0 else { return remaining == 0 ? today : nil }
            let daysNeeded = Int(ceil(Double(remaining) / avg))
            return cal.date(byAdding: .day, value: daysNeeded, to: today)
        }

        let avg60 = avgOver(days: 60)
        let avg30 = avgOver(days: 30)
        let avgIdeal = Double(data.dailyGoal)

        return (
            VelocityProjection(velocityWindow: 60, avgPerDay: avg60, estimatedDate: project(avg: avg60)),
            VelocityProjection(velocityWindow: 30, avgPerDay: avg30, estimatedDate: project(avg: avg30)),
            VelocityProjection(velocityWindow: 0,  avgPerDay: avgIdeal, estimatedDate: project(avg: avgIdeal))
        )
    }

    var targetDefenseDate: Date? {
        get { data.targetDefenseDate.flatMap(DataStore.parseDate) }
        set {
            data.targetDefenseDate = newValue.map(DataStore.dateString)
            save()
        }
    }

    // MARK: - Journal de bord doctoral

    @discardableResult
    func addJournalEntry(content: String, date: String? = nil, mood: Int? = nil, tags: [String] = []) -> JournalEntry? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let now = ChapterLogEntry.nowTimestamp()
        let entry = JournalEntry(
            date: date ?? DataStore.today,
            content: trimmed,
            mood: mood.map { max(1, min(5, $0)) },
            tags: tags,
            createdAt: now,
            updatedAt: now
        )
        data.journalEntries.append(entry)
        save()
        return entry
    }

    func updateJournalEntry(_ id: UUID, content: String? = nil, mood: Int?? = nil, tags: [String]? = nil) {
        guard let idx = data.journalEntries.firstIndex(where: { $0.id == id }) else { return }
        if let content {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { data.journalEntries[idx].content = trimmed }
        }
        if let mood { data.journalEntries[idx].mood = mood.map { max(1, min(5, $0)) } }
        if let tags { data.journalEntries[idx].tags = tags }
        data.journalEntries[idx].updatedAt = ChapterLogEntry.nowTimestamp()
        save()
    }

    func deleteJournalEntry(_ id: UUID) {
        data.journalEntries.removeAll { $0.id == id }
        save()
    }

    /// Entrées triées (récent en premier) optionnellement filtrées par texte.
    func journalEntriesSorted(matching query: String = "") -> [JournalEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = data.journalEntries.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.createdAt > rhs.createdAt
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { entry in
            entry.content.lowercased().contains(q)
                || entry.tags.contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: - Carnet de fragments

    @discardableResult
    func addFragment(content: String, tags: [String] = []) -> Fragment? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let frag = Fragment(content: trimmed, createdAt: ChapterLogEntry.nowTimestamp(), tags: tags)
        data.fragments.append(frag)
        save()
        return frag
    }

    func updateFragment(_ id: UUID, content: String? = nil, tags: [String]? = nil) {
        guard let idx = data.fragments.firstIndex(where: { $0.id == id }) else { return }
        if let content {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { data.fragments[idx].content = trimmed }
        }
        if let tags { data.fragments[idx].tags = tags }
        save()
    }

    func archiveFragment(_ id: UUID) {
        guard let idx = data.fragments.firstIndex(where: { $0.id == id }) else { return }
        data.fragments[idx].archivedAt = DataStore.today
        save()
    }

    func unarchiveFragment(_ id: UUID) {
        guard let idx = data.fragments.firstIndex(where: { $0.id == id }) else { return }
        data.fragments[idx].archivedAt = nil
        save()
    }

    func deleteFragment(_ id: UUID) {
        data.fragments.removeAll { $0.id == id }
        save()
    }

    /// Déplace un fragment vers les idées d'un chapitre. Le fragment est marqué `movedToChapterId`.
    func moveFragmentToChapter(fragmentId: UUID, chapterId: UUID, in projectId: UUID) {
        guard let fIdx = data.fragments.firstIndex(where: { $0.id == fragmentId }),
              let pIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let cIdx = data.projects[pIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        let fragment = data.fragments[fIdx]
        let stamp = "[\(DataStore.today)] "
        let newIdeas = (data.projects[pIdx].chapters[cIdx].notesIdeas?.isEmpty == false
            ? data.projects[pIdx].chapters[cIdx].notesIdeas! + "\n\n" : "") + stamp + fragment.content
        data.projects[pIdx].chapters[cIdx].notesIdeas = newIdeas
        data.fragments[fIdx].movedToChapterId = chapterId
        data.fragments[fIdx].movedAt = DataStore.today
        save()
    }

    var activeFragments: [Fragment] {
        data.fragments.filter { $0.isActive }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Bilan mensuel automatique

    static var currentMonthKey: String { String(DataStore.today.prefix(7)) }

    func monthlyReportForCurrentMonth() -> MonthlyReport? {
        data.monthlyReports.first { $0.monthKey == DataStore.currentMonthKey }
    }

    /// Génère le bilan pour un mois donné s'il n'existe pas encore.
    /// Appelé automatiquement au début du mois suivant.
    @discardableResult
    func generateMonthlyReportIfNeeded(for monthKey: String) -> MonthlyReport? {
        guard data.monthlyReports.first(where: { $0.monthKey == monthKey }) == nil else { return nil }
        let totals = dailyTotals()
        let monthly = totals.filter { $0.key.hasPrefix(monthKey) }
        let chars = monthly.values.reduce(0, +)
        let activeDays = monthly.values.filter { $0 > 0 }.count
        let bestPair = monthly.filter { $0.value > 0 }.max(by: { $0.value < $1.value })
        let chaptersFinishedThisMonth = data.projects.flatMap { $0.chapters }.filter { chapter in
            guard chapter.isCompleted,
                  let last = chapter.logEntries.filter({ $0.type == .statusChange }).max(by: { $0.timestamp < $1.timestamp }) else {
                return false
            }
            return last.timestamp.hasPrefix(monthKey)
        }.count
        let headline = makeHeadline(chars: chars, days: activeDays, finished: chaptersFinishedThisMonth)

        let report = MonthlyReport(
            monthKey: monthKey,
            generatedAt: ChapterLogEntry.nowTimestamp(),
            charsWritten: chars,
            daysActive: activeDays,
            chaptersFinished: chaptersFinishedThisMonth,
            bestDay: bestPair?.key,
            bestDayCount: bestPair?.value ?? 0,
            streakAtMonthEnd: currentStreak,
            headline: headline
        )
        data.monthlyReports.append(report)
        save()
        return report
    }

    /// À appeler au démarrage : si on est dans un nouveau mois et que le mois précédent
    /// n'a pas de bilan généré, on le génère et on remonte une notification.
    /// **Sécurité critique** : ne génère RIEN si `data.projects` est vide, sinon un
    /// appel précoce (avant que `load()` async ait peuplé `data`) déclencherait un
    /// `save()` sur AppData vide et écraserait le fichier.
    func checkAndGenerateMonthlyReport() {
        guard !data.projects.isEmpty else { return }
        let cal = DataStore.gregorianCal
        guard let lastMonth = cal.date(byAdding: .month, value: -1, to: Date()) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        let lastMonthKey = fmt.string(from: lastMonth)
        _ = generateMonthlyReportIfNeeded(for: lastMonthKey)
    }

    func updateMonthlyReportNotes(monthKey: String, notes: String) {
        guard let idx = data.monthlyReports.firstIndex(where: { $0.monthKey == monthKey }) else { return }
        data.monthlyReports[idx].userNotes = notes
        save()
    }

    private func makeHeadline(chars: Int, days: Int, finished: Int) -> String {
        if chars == 0 { return "Mois sans écriture." }
        var parts: [String] = []
        parts.append("\(DataStore.formatNumber(chars)) car. en \(days) jour\(days > 1 ? "s" : "")")
        if finished > 0 { parts.append("\(finished) chapitre\(finished > 1 ? "s" : "") terminé\(finished > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Self-review par chapitre

    @discardableResult
    func addSelfReview(chapterId: UUID, in projectId: UUID,
                       clarity: Int, argumentation: Int, citations: Int,
                       transitions: Int, originality: Int,
                       notes: String? = nil) -> SelfReview? {
        guard let projIdx = data.projects.firstIndex(where: { $0.id == projectId }),
              let chapIdx = data.projects[projIdx].chapters.firstIndex(where: { $0.id == chapterId }) else { return nil }
        let review = SelfReview(
            date: DataStore.today,
            draftVersion: data.projects[projIdx].chapters[chapIdx].draftVersion,
            clarity: clamp(clarity), argumentation: clamp(argumentation),
            citations: clamp(citations), transitions: clamp(transitions),
            originality: clamp(originality),
            notes: notes.flatMap { let t = $0.trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        )
        data.projects[projIdx].chapters[chapIdx].selfReviews.append(review)
        save()
        return review
    }

    func latestSelfReview(chapterId: UUID, in projectId: UUID) -> SelfReview? {
        guard let project = data.projects.first(where: { $0.id == projectId }),
              let chapter = project.chapters.first(where: { $0.id == chapterId }) else { return nil }
        return chapter.selfReviews.max(by: { $0.date < $1.date })
    }

    private func clamp(_ value: Int) -> Int { max(1, min(5, value)) }

    // MARK: - Indice "chapitre qui fait mal"

    struct PainfulChapter: Identifiable {
        let id: UUID
        let project: Project
        let chapter: Chapter
        let reasons: [String]
        let score: Int          // 1-5, plus élevé = plus douloureux
    }

    var painfulChapters: [PainfulChapter] {
        var result: [PainfulChapter] = []
        let cal = DataStore.gregorianCal
        let today = Date()
        for project in data.projects where !project.isArchived {
            for chapter in project.chapters where !chapter.isCompleted {
                var reasons: [String] = []
                var score = 0
                // Critère 1 : 3+ cycles de relecture
                if chapter.supervisorReviews.count >= 3 {
                    reasons.append("\(chapter.supervisorReviews.count) cycles de relecture")
                    score += 2
                }
                // Critère 2 : > 3 checkpoints (signe de refonte fréquente)
                if chapter.checkpoints.count >= 4 {
                    reasons.append("\(chapter.checkpoints.count) points de sauvegarde")
                    score += 1
                }
                // Critère 3 : deadline approche et peu d'avancement récent
                if let deadlineStr = chapter.deadline,
                   let deadlineDate = DataStore.parseDate(deadlineStr) {
                    let daysUntil = cal.dateComponents([.day], from: today, to: deadlineDate).day ?? 0
                    let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                    let progress = chapter.goal > 0 ? Double(latest) / Double(chapter.goal) : 0
                    if daysUntil > 0, daysUntil <= 30, progress < 0.7 {
                        reasons.append("deadline dans \(daysUntil) j, \(Int(progress * 100))% atteint")
                        score += 2
                    }
                }
                // Critère 4 : stagnation > 14 j
                if let lastEntry = chapter.entries.max(by: { $0.date < $1.date }),
                   let lastDate = DataStore.parseDate(lastEntry.date) {
                    let daysSince = cal.dateComponents([.day], from: lastDate, to: today).day ?? 0
                    if daysSince >= 14 {
                        reasons.append("\(daysSince) j sans avancée")
                        score += 1
                    }
                }
                if score >= 2 {
                    result.append(PainfulChapter(
                        id: chapter.id, project: project, chapter: chapter,
                        reasons: reasons, score: min(5, score)
                    ))
                }
            }
        }
        return result.sorted { $0.score > $1.score }
    }

    // MARK: - Checklist administrative

    @discardableResult
    func addAdminTask(title: String, kind: AdminTask.Kind, dueDate: String? = nil, notes: String? = nil) -> AdminTask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let task = AdminTask(title: trimmed, kind: kind, dueDate: dueDate, notes: notes,
                             createdAt: ChapterLogEntry.nowTimestamp())
        data.adminTasks.append(task)
        save()
        return task
    }

    func updateAdminTask(_ id: UUID, title: String? = nil, kind: AdminTask.Kind? = nil,
                        dueDate: String?? = nil, notes: String?? = nil) {
        guard let idx = data.adminTasks.firstIndex(where: { $0.id == id }) else { return }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { data.adminTasks[idx].title = trimmed }
        }
        if let kind { data.adminTasks[idx].kind = kind }
        if let dueDate { data.adminTasks[idx].dueDate = dueDate }
        if let notes { data.adminTasks[idx].notes = notes }
        save()
    }

    func toggleAdminTask(_ id: UUID) {
        guard let idx = data.adminTasks.firstIndex(where: { $0.id == id }) else { return }
        data.adminTasks[idx].isCompleted.toggle()
        data.adminTasks[idx].completedAt = data.adminTasks[idx].isCompleted ? DataStore.today : nil
        save()
    }

    func deleteAdminTask(_ id: UUID) {
        data.adminTasks.removeAll { $0.id == id }
        save()
    }

    var upcomingAdminTasks: [AdminTask] {
        let pending = data.adminTasks.filter { !$0.isCompleted }
        return pending.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (l?, r?): return l < r
            case (nil, _?):    return false
            case (_?, nil):    return true
            default:           return a.createdAt < b.createdAt
            }
        }
    }

    // MARK: - Helpers

    // MARK: - Week calendar cache (Dashboard typing perf)

    /// Snapshot d'une journée pour le calendrier de la semaine.
    struct WeekDayInfo {
        let dateStr: String
        let written: Int
        let isToday: Bool
        let isFuture: Bool
        let letter: String
        let dayNumber: Int
    }

    /// 7 jours de la semaine courante — recalculé une fois par dataVersion, O(1) ensuite.
    /// Utilise dailyTotals() (déjà caché) → O(1) par jour, pas de chapter.increment() appelé.
    var currentWeekInfo: [WeekDayInfo] {
        if let c = _currentWeekInfoCache, c.version == dataVersion { return c.days }
        var cal = DataStore.gregorianCal
        cal.firstWeekday = 2
        let today = Date()
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today) else {
            _currentWeekInfoCache = (dataVersion, [])
            return []
        }
        let todayStr = DataStore.today
        let totals = dailyTotals()
        let letters = ["D", "L", "M", "M", "J", "V", "S"]
        var result: [WeekDayInfo] = []
        var current = weekInterval.start
        for _ in 0..<7 {
            let dateStr = DataStore.dateString(from: current)
            let weekday = cal.component(.weekday, from: current)
            result.append(WeekDayInfo(
                dateStr:   dateStr,
                written:   totals[dateStr] ?? 0,
                isToday:   dateStr == todayStr,
                isFuture:  current > today,
                letter:    letters[max(0, weekday - 1)],
                dayNumber: cal.component(.day, from: current)
            ))
            current = cal.date(byAdding: .day, value: 1, to: current)!
        }
        _currentWeekInfoCache = (dataVersion, result)
        return result
    }

    // MARK: - Sidebar perf caches

    /// All chapter latest totals in one pass — O(1) after first call per dataVersion.
    var latestTotalsAll: [UUID: Int] {
        if let c = _latestTotalsAllCache, c.version == dataVersion { return c.totals }
        var result: [UUID: Int] = [:]
        for project in data.projects {
            for chapter in project.chapters {
                result[chapter.id] = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            }
        }
        _latestTotalsAllCache = (dataVersion, result)
        return result
    }

    /// Estimated completion dates for all chapters — O(1) after first call per dataVersion.
    var estimatedCompletionDatesAll: [UUID: Date?] {
        if let c = _estimatedCompletionDatesAllCache, c.version == dataVersion { return c.dates }
        let cal = DataStore.gregorianCal
        let today = Date()
        let lookback = 14
        var result: [UUID: Date?] = [:]
        for project in data.projects {
            for chapter in project.chapters {
                let latest = latestTotalsAll[chapter.id] ?? 0
                let goal   = chapter.goal
                guard goal > 0, latest < goal else { result[chapter.id] = nil; continue }
                let remaining = goal - latest
                // Build increment dict from sorted entries — single O(n log n) pass
                let sorted = chapter.entries.sorted { $0.date < $1.date }
                var prev = 0
                var incByDate: [String: Int] = [:]
                for entry in sorted {
                    let inc = max(0, entry.totalCount - prev)
                    if inc > 0 { incByDate[entry.date] = inc }
                    prev = entry.totalCount
                }
                var increments: [Int] = []
                for offset in 1...lookback {
                    guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                    if let inc = incByDate[DataStore.dateString(from: d)], inc > 0 { increments.append(inc) }
                }
                guard !increments.isEmpty else { result[chapter.id] = nil; continue }
                let avgPerDay = increments.reduce(0, +) / increments.count
                guard avgPerDay > 0 else { result[chapter.id] = nil; continue }
                let daysNeeded = Int(ceil(Double(remaining) / Double(avgPerDay)))
                result[chapter.id] = cal.date(byAdding: .day, value: daysNeeded, to: today)
            }
        }
        _estimatedCompletionDatesAllCache = (dataVersion, result)
        return result
    }

    /// Completion ratios for all projects — O(1) after first call per dataVersion.
    var projectRatiosAll: [UUID: Double] {
        if let c = _projectRatiosAllCache, c.version == dataVersion { return c.ratios }
        let totals = latestTotalsAll
        var result: [UUID: Double] = [:]
        for project in data.projects {
            let totalGoal    = project.chapters.reduce(0) { $0 + $1.goal }
            let totalWritten = project.chapters.reduce(0) { $0 + (totals[$1.id] ?? 0) }
            result[project.id] = totalGoal > 0 ? min(1.0, Double(totalWritten) / Double(totalGoal)) : 0
        }
        _projectRatiosAllCache = (dataVersion, result)
        return result
    }

    func latestTotal(for chapterId: UUID, in projectId: UUID) -> Int {
        latestTotalsAll[chapterId] ?? 0
    }

    func statusColor(for chapterId: UUID, in projectId: UUID, goal: Int) -> Color {
        guard goal > 0 else { return .gray }
        let ratio = Double(latestTotal(for: chapterId, in: projectId)) / Double(goal)
        if ratio >= 1.0  { return Color(red: 0.196, green: 0.784, blue: 0.549) }
        if ratio >= 0.66 { return Color(red: 0.961, green: 0.620, blue: 0.043) }
        if ratio >= 0.33 { return Color(red: 0.929, green: 0.435, blue: 0.114) }
        return Color(red: 0.929, green: 0.329, blue: 0.329)
    }


    /// Projection de fin de chapitre — O(1) via estimatedCompletionDatesAll.
    /// Le paramètre lookbackDays est ignoré (toujours 14) quand on passe par le cache global.
    func estimatedCompletionDate(for chapterId: UUID, in projectId: UUID, lookbackDays: Int = 14) -> Date? {
        estimatedCompletionDatesAll[chapterId] ?? nil
    }

    func estimatedCompletionDate(for projectId: UUID, lookbackDays: Int = 14) -> Date? {
        guard let project = data.projects.first(where: { $0.id == projectId }) else { return nil }
        let chapters = project.chapters.filter { !$0.isCompleted && $0.goal > 0 }
        guard !chapters.isEmpty else { return nil }

        let remaining = chapters.reduce(0) { total, chapter in
            let latest = chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            return total + max(0, chapter.goal - latest)
        }
        guard remaining > 0 else { return nil }

        let cal = DataStore.gregorianCal
        let today = Date()
        // Use cached project-scoped totals (O(1) after first call per dataVersion)
        let projectTotals = dailyTotals(projectId: projectId)
        var increments: [Int] = []
        for offset in 1...lookbackDays {
            guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let total = projectTotals[DataStore.dateString(from: date)] ?? 0
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
        if let c = _currentStreakCache, c.version == dataVersion { return c.value }
        let cal = DataStore.gregorianCal
        let totals = dailyTotals()
        let todayStr = DataStore.today
        let todayTotal = totals[todayStr] ?? 0
        let startOffset = todayTotal > 0 ? 0 : 1
        var streak = 0; var offset = startOffset
        while offset < 730 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let total = totals[DataStore.dateString(from: date)] ?? 0
            if total > 0 { streak += 1; offset += 1 } else { break }
        }
        _currentStreakCache = (dataVersion, streak)
        return streak
    }

    /// Meilleure série de jours consécutifs de toute l'histoire
    var longestStreak: Int {
        if let c = _longestStreakCache, c.version == dataVersion { return c.value }
        let totals = dailyTotals()
        let sorted = totals.keys.filter { (totals[$0] ?? 0) > 0 }.sorted()
        guard !sorted.isEmpty else { _longestStreakCache = (dataVersion, 0); return 0 }
        let cal = DataStore.gregorianCal
        var longest = 1, current = 1
        for i in 1..<sorted.count {
            guard let prev = DataStore.parseDate(sorted[i-1]),
                  let curr = DataStore.parseDate(sorted[i]) else { continue }
            let diff = cal.dateComponents([.day], from: prev, to: curr).day ?? 0
            if diff == 1 { current += 1; if current > longest { longest = current } }
            else { current = 1 }
        }
        _longestStreakCache = (dataVersion, longest)
        return longest
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
        var cal = DataStore.gregorianCal
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

    // MARK: - Objectif variable par jour de semaine (V5)

    /// Objectifs journaliers spécifiques à chaque jour. Clé = weekday Calendar (1=Dim … 7=Sam).
    /// Stocké dans UserDefaults sous forme de JSON pour ne pas toucher AppData.
    var weekdayGoals: [Int: Int] {
        get {
            guard let raw  = UserDefaults.standard.data(forKey: "weekdayGoals"),
                  let dict = try? DataStore.sharedDecoder.decode([String: Int].self, from: raw)
            else { return [:] }
            return Dictionary(uniqueKeysWithValues: dict.compactMap { k, v in
                guard let i = Int(k) else { return nil }; return (i, v)
            })
        }
        set {
            let stringDict = Dictionary(uniqueKeysWithValues: newValue.map { (String($0.key), $0.value) })
            if let encoded = try? DataStore.sharedEncoder.encode(stringDict) {
                UserDefaults.standard.set(encoded, forKey: "weekdayGoals")
            }
        }
    }

    /// Objectif journalier effectif pour aujourd'hui.
    /// Retourne l'objectif spécifique au jour courant s'il est défini et > 0, sinon `data.dailyGoal`.
    var effectiveDailyGoal: Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1=Dim…7=Sam
        if let specific = weekdayGoals[weekday], specific > 0 { return specific }
        return data.dailyGoal
    }

    // MARK: - V3.3 Daily session

    /// Caractères écrits la veille (tous chapitres confondus)
    var yesterdayProgress: Int {
        let cal = DataStore.gregorianCal
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

    /// Objectif journalier calculé d'après le deadline du chapitre actif (si défini)
    var deadlineDailyGoal: Int? {
        guard let chapter = activeChapter,
              let deadlineStr = chapter.deadline,
              let deadline = DataStore.parseDate(deadlineStr),
              chapter.goal > 0 else { return nil }
        let cal = DataStore.gregorianCal
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
        if value == 0, let entryIdx = data.projects[projIdx].chapters[chapIdx].entries.firstIndex(where: { $0.date == date }) {
            let entry = data.projects[projIdx].chapters[chapIdx].entries[entryIdx]
            let hasOtherContent = !(entry.note ?? "").isEmpty || entry.energyLevel != nil
            if hasOtherContent {
                // Ne pas perdre la note : on garde l'entrée avec un incrément nul.
                data.projects[projIdx].chapters[chapIdx].entries[entryIdx].totalCount =
                    data.projects[projIdx].chapters[chapIdx].previousTotal(before: date)
            } else {
                data.projects[projIdx].chapters[chapIdx].entries.remove(at: entryIdx)
            }
        } else if value == 0 {
            // Rien à annuler : l'entrée n'existe déjà plus.
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
        var cal = DataStore.gregorianCal
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
        var prevWeekDateSet = Set<String>()
        var dc = prevWeekStart
        for _ in 0..<7 {
            prevWeekDateSet.insert(DataStore.dateString(from: dc))
            dc = cal.date(byAdding: .day, value: 1, to: dc) ?? dc
        }
        var topProject: String? = nil; var topCount = 0
        for project in data.projects {
            var projTotal = 0
            for chapter in project.chapters {
                var prev = 0
                for entry in chapter.entries.sorted(by: { $0.date < $1.date }) {
                    let inc = max(0, entry.totalCount - prev)
                    if prevWeekDateSet.contains(entry.date) && inc > 0 { projTotal += inc }
                    prev = entry.totalCount
                }
            }
            if projTotal > topCount { topCount = projTotal; topProject = project.name }
        }
        return (totalChars, activeDays, bestDay, topProject)
    }

    func checkAndShowWeeklySummary() {
        var cal = DataStore.gregorianCal
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
        Color.refreshAccent()
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

    func addProjectWithChapters(name: String, chapters: [(name: String, goal: Int)],
                                type: ProjectType? = nil, supervisor: String? = nil) {
        var project = Project(name: name)
        project.projectType = type
        project.supervisor  = supervisor
        project.chapters    = chapters.map { c in Chapter(name: c.name, goal: c.goal) }
        if let first = project.chapters.first { project.activeChapterId = first.id }
        data.projects.append(project)
        if data.activeProjectId == nil { data.activeProjectId = project.id }
        save()
    }

    // MARK: - Milestones

    enum MilestoneType: Equatable {
        case streak(Int)
        case chapterComplete(String)
        case challengeComplete(WeeklyChallenge.ChallengeKind)
        case volumeMilestone(Int)               // total caractères jamais écrits
        case projectPercent(String, Int)        // (nom de projet, pourcentage atteint)
        case firstChapterCompleted(String)      // nom du projet — premier chapitre fini
        case dailyRecord(Int)                   // record personnel de caractères dans une journée
    }

    static let badgeMilestones = [3, 7, 14, 30, 60, 100, 200, 365]

    /// Paliers de volume total (caractères) qui déclenchent une célébration
    static let volumeCelebrationMilestones = [100_000, 500_000, 1_000_000, 2_000_000, 5_000_000]

    /// Paliers de pourcentage d'avancement projet qui déclenchent une célébration
    static let projectPercentMilestones = [50, 75, 100]

    /// Paliers de streak débloqués à vie (basé sur longestStreak)
    var unlockedBadgeThresholds: [Int] {
        DataStore.badgeMilestones.filter { longestStreak >= $0 }
    }

    @Published var pendingMilestone: MilestoneType? = nil

    /// Sessions Pomodoro complétées sur la semaine ISO en cours.
    /// Alimenté depuis l'extérieur (MainView observe PomodoroAppController).
    @Published var weeklyPomodoroSessionCount: Int = 0

    func setWeeklyPomodoroSessionCount(_ count: Int) {
        guard count != weeklyPomodoroSessionCount else { return }
        weeklyPomodoroSessionCount = count
        // Une nouvelle session peut compléter un défi `.sessions`
        checkWeeklyChallengeCompletion()
    }

    // #31 — Rapport hebdomadaire automatique le lundi matin
    @Published var showWeeklyReportPrompt: Bool = false
    private var lastWeeklyReportMonday: String {
        get { UserDefaults.standard.string(forKey: "lastWeeklyReportMonday") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "lastWeeklyReportMonday") }
    }

    func checkWeeklyReportIfNeeded() {
        var cal = DataStore.gregorianCal; cal.firstWeekday = 2
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        guard weekday == 2 else { return } // 2 = Monday in gregorian with firstWeekday=2
        let mondayKey = DataStore.dateString(from: today)
        guard lastWeeklyReportMonday != mondayKey else { return }
        // Only if there's data from last week
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: today),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekInterval.start) else { return }
        let lastWeekStartStr = DataStore.dateString(from: lastWeekStart)
        let lastWeekEndStr   = DataStore.dateString(from: cal.date(byAdding: .day, value: 6, to: lastWeekStart) ?? weekInterval.start)
        let hasLastWeekData  = dailyTotals().keys.contains { $0 >= lastWeekStartStr && $0 <= lastWeekEndStr }
        guard hasLastWeekData else { return }
        lastWeeklyReportMonday = mondayKey
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showWeeklyReportPrompt = true
        }
    }

    func dismissWeeklyReportPrompt() {
        showWeeklyReportPrompt = false
    }

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
        checkVolumeMilestones()
        checkProjectPercentMilestones()
        checkDailyRecord()
        checkFirstChapterCompleted()
    }

    // MARK: - Volume / projet / record milestones (nouveaux)

    private func checkVolumeMilestones() {
        let udKey = "toastedVolumeMilestones"
        var toasted = Set(UserDefaults.standard.array(forKey: udKey) as? [Int] ?? [])
        let total = totalCharsEverWritten
        for threshold in DataStore.volumeCelebrationMilestones {
            guard total >= threshold, !toasted.contains(threshold) else { continue }
            toasted.insert(threshold)
            UserDefaults.standard.set(Array(toasted), forKey: udKey)
            showMilestone(.volumeMilestone(threshold))
            return
        }
    }

    private func checkProjectPercentMilestones() {
        let udKey = "toastedProjectPercentMilestones"
        var toasted = Set(UserDefaults.standard.array(forKey: udKey) as? [String] ?? [])
        for project in data.projects {
            let chapters = project.chapters
            guard !chapters.isEmpty else { continue }
            let totalGoal = chapters.map { $0.goal }.reduce(0, +)
            guard totalGoal > 0 else { continue }
            let totalWritten = chapters.map { ch -> Int in
                ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            }.reduce(0, +)
            let pct = Int((Double(totalWritten) / Double(totalGoal)) * 100.0)
            for milestone in DataStore.projectPercentMilestones where pct >= milestone {
                let key = "\(project.id.uuidString)-\(milestone)"
                guard !toasted.contains(key) else { continue }
                toasted.insert(key)
                UserDefaults.standard.set(Array(toasted), forKey: udKey)
                showMilestone(.projectPercent(project.name, milestone))
                return
            }
        }
    }

    private func checkDailyRecord() {
        let udKey = "toastedDailyRecord"
        let totals = dailyTotals()
        let todayValue = totals[DataStore.today] ?? 0
        // Record uniquement si on bat le précédent et au-delà d'un seuil minimal (1000 car)
        guard todayValue >= 1000 else { return }
        let previousMax = totals.filter { $0.key != DataStore.today }.values.max() ?? 0
        guard todayValue > previousMax else { return }
        let lastRecorded = UserDefaults.standard.integer(forKey: udKey)
        guard todayValue > lastRecorded else { return }
        UserDefaults.standard.set(todayValue, forKey: udKey)
        showMilestone(.dailyRecord(todayValue))
    }

    private func checkFirstChapterCompleted() {
        let udKey = "toastedFirstChapterCompleted"
        var toasted = Set(UserDefaults.standard.array(forKey: udKey) as? [String] ?? [])
        for project in data.projects {
            guard !toasted.contains(project.id.uuidString) else { continue }
            let completedCount = project.chapters.filter { $0.isCompleted }.count
            if completedCount >= 1 {
                toasted.insert(project.id.uuidString)
                UserDefaults.standard.set(Array(toasted), forKey: udKey)
                showMilestone(.firstChapterCompleted(project.name))
                return
            }
        }
    }

    // MARK: - Weekly challenges

    /// ISO week key e.g. "2026-W12"
    static var currentWeekKey: String {
        let cal = Calendar(identifier: .iso8601) // iso8601 — can't use gregorianCal here
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let y = components.yearForWeekOfYear ?? 2026
        let w = components.weekOfYear ?? 1
        return String(format: "%04d-W%02d", y, w)
    }

    var currentWeekChallenge: WeeklyChallenge? {
        data.weeklyChallenges.first { $0.weekKey == DataStore.currentWeekKey }
    }

    func challengeProgress(_ challenge: WeeklyChallenge) -> Int {
        // Semaine ISO (lundi → dimanche), comme `currentWeekKey`.
        let cal = DataStore.iso8601Cal
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
            return weeklyPomodoroSessionCount
        case .chapterCompletion:
            // Chapitres terminés durant la semaine en cours (basé sur le dernier log statusChange vers "termine"
            // ou, à défaut, la dernière entrée si le chapitre est marqué isCompleted).
            guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return 0 }
            let weekStartStr = DataStore.dateString(from: weekStart)
            let weekEndStr   = DataStore.dateString(from: weekEnd)
            var count = 0
            for project in data.projects {
                for chapter in project.chapters where chapter.isCompleted {
                    let completionDate = chapterCompletionDate(chapter)
                    if let d = completionDate, d >= weekStartStr && d <= weekEndStr {
                        count += 1
                    }
                }
            }
            return count
        case .chaptersAdvanced:
            // Chapitres dont le statut a progressé durant la semaine
            guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else { return 0 }
            let weekStartStr = DataStore.dateString(from: weekStart)
            let weekEndStr   = DataStore.dateString(from: weekEnd)
            var seen = Set<UUID>()
            for project in data.projects {
                for chapter in project.chapters {
                    for log in chapter.logEntries where log.type == .statusChange {
                        let day = String(log.timestamp.prefix(10))
                        if day >= weekStartStr && day <= weekEndStr {
                            seen.insert(chapter.id)
                            break
                        }
                    }
                }
            }
            return seen.count
        }
    }

    /// Date "yyyy-MM-dd" à laquelle un chapitre est passé à l'état terminé (best effort).
    private func chapterCompletionDate(_ chapter: Chapter) -> String? {
        // Cherche le dernier log statusChange vers "termine"
        let termineLog = chapter.logEntries
            .filter { $0.type == .statusChange && $0.content.localizedCaseInsensitiveContains("termin") }
            .max(by: { $0.timestamp < $1.timestamp })
        if let log = termineLog { return String(log.timestamp.prefix(10)) }
        // À défaut, la date de la dernière entrée
        return chapter.entries.max(by: { $0.date < $1.date })?.date
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
        (.chapterCompletion, 1), // S51 – Boucler un chapitre
        (.chaptersAdvanced,  2), // S52 – Faire avancer 2 chapitres
    ]

    private func checkOrGenerateWeeklyChallenge() {
        let key = DataStore.currentWeekKey
        guard data.weeklyChallenges.first(where: { $0.weekKey == key }) == nil else { return }

        let cal = Calendar(identifier: .iso8601) // iso8601 — can't use gregorianCal here
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

        // Persister via le circuit normal (fusion iCloud, snapshots, file série)
        save()

        // Guard UserDefaults : n'afficher la notification qu'une seule fois
        let udKey = "notifiedChallengeWeeks"
        var notified = Set(UserDefaults.standard.array(forKey: udKey) as? [String] ?? [])
        guard !notified.contains(challenge.weekKey) else { return }
        notified.insert(challenge.weekKey)
        UserDefaults.standard.set(Array(notified), forKey: udKey)

        showMilestone(.challengeComplete(challenge.kind))
    }

    var chaptersWithDeadlines: [(project: Project, chapter: Chapter)] {
        if let c = _chaptersWithDeadlinesCache, c.version == dataVersion { return c.items }
        let items = data.projects.flatMap { project in
            project.chapters.compactMap { chapter -> (project: Project, chapter: Chapter)? in
                chapter.deadline == nil || chapter.isCompleted ? nil : (project, chapter)
            }
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.chapter.deadline.flatMap(DataStore.parseDate) ?? .distantFuture
            let rhsDate = rhs.chapter.deadline.flatMap(DataStore.parseDate) ?? .distantFuture
            return lhsDate < rhsDate
        }
        _chaptersWithDeadlinesCache = (dataVersion, items)
        return items
    }

    // MARK: - Deadline pace alerts (#14)

    private func scheduleDeadlinePaceAlertsIfNeeded() {
        let cal = DataStore.gregorianCal
        let today = Date()
        var items: [NotificationManager.DeadlinePaceItem] = []

        for item in chaptersWithDeadlines {
            guard let deadlineDate = item.chapter.deadline.flatMap(DataStore.parseDate),
                  deadlineDate > today else { continue }
            guard let etaDate = estimatedCompletionDate(for: item.chapter.id, in: item.project.id) else { continue }
            guard etaDate > deadlineDate else { continue }

            // Calcule la velocity nécessaire
            let latest = item.chapter.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
            let remaining = max(0, item.chapter.goal - latest)
            let daysLeft = cal.dateComponents([.day], from: today, to: deadlineDate).day ?? 1
            guard daysLeft > 0, remaining > 0 else { continue }
            let required = Int(ceil(Double(remaining) / Double(daysLeft)))

            // Velocity actuelle (7 derniers jours)
            var increments: [Int] = []
            for offset in 1...7 {
                guard let date = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
                let inc = item.chapter.increment(for: DataStore.dateString(from: date))
                if inc > 0 { increments.append(inc) }
            }
            let current = increments.isEmpty ? 0 : increments.reduce(0, +) / increments.count

            items.append(NotificationManager.DeadlinePaceItem(
                chapterName: item.chapter.name,
                projectName: item.project.name,
                deadline: deadlineDate,
                etaDate: etaDate,
                requiredPerDay: required,
                currentPerDay: current,
                useWordCount: data.useWordCount
            ))
        }

        if !items.isEmpty {
            NotificationManager.shared.scheduleDeadlinePaceAlerts(items)
        }
    }

    // MARK: - Plateau detection alerts (V5 — amélioration #6)

    private func schedulePlateauAlertsIfNeeded() {
        let plateaux = plateauChapters
        guard !plateaux.isEmpty else { return }
        // Limite : ne déclenche la notif qu'une fois par jour
        let todayKey = "lastPlateauAlertDate"
        let today = DataStore.today
        guard UserDefaults.standard.string(forKey: todayKey) != today else { return }
        UserDefaults.standard.set(today, forKey: todayKey)
        NotificationManager.shared.schedulePlateauAlerts(plateaux)
    }

    // MARK: - #24 Buffer de sécurité

    /// Nombre de jours à soustraire à toutes les deadlines (0 = pas de buffer).
    var deadlineBuffer: Int {
        get { UserDefaults.standard.integer(forKey: "deadlineBuffer") }
        set { UserDefaults.standard.set(newValue, forKey: "deadlineBuffer") }
    }

    /// Date effective d'une deadline après application du buffer.
    func effectiveDeadlineDate(for deadlineStr: String?) -> Date? {
        guard let str = deadlineStr, let date = DataStore.parseDate(str) else { return nil }
        let buffer = deadlineBuffer
        guard buffer > 0 else { return date }
        return Calendar.current.date(byAdding: .day, value: -buffer, to: date)
    }

    // MARK: - #27 Rythme nécessaire par chapitre

    /// Retourne le nombre de car./jour nécessaires pour finir un chapitre avant sa deadline.
    /// Nil si pas de deadline, si le chapitre est terminé, ou si le buffer rend la deadline déjà passée.
    func requiredPacePerDay(for chapter: Chapter, in project: Project) -> Int? {
        guard !chapter.isCompleted,
              let deadline = effectiveDeadlineDate(for: chapter.deadline) else { return nil }
        let today = Date()
        guard deadline > today else { return nil }
        let latest = latestTotal(for: chapter.id, in: project.id)
        let remaining = max(0, chapter.goal - latest)
        guard remaining > 0 else { return nil }
        let daysLeft = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                                               to: Calendar.current.startOfDay(for: deadline)).day ?? 1)
        return Int(ceil(Double(remaining) / Double(daysLeft)))
    }

    // MARK: - #23 Alerte chevauchement de deadlines

    private func scheduleDeadlineConflictAlertsIfNeeded() {
        let todayKey = "lastConflictAlertDate"
        let today = DataStore.today
        guard UserDefaults.standard.string(forKey: todayKey) != today else { return }

        let cal = Calendar.current
        let now = Date()
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: now) else { return }

        // Chapitres dont la deadline tombe dans les 7 prochains jours et non terminés
        let upcoming = chaptersWithDeadlines.filter {
            guard let d = effectiveDeadlineDate(for: $0.chapter.deadline),
                  !$0.chapter.isCompleted else { return false }
            return d >= now && d <= weekEnd
        }
        guard upcoming.count >= 2 else { return }

        // Vérifie si la velocity actuelle permet de finir plusieurs à la fois
        var conflictingNames: [String] = []
        var totalRequired = 0
        for item in upcoming {
            if let pace = requiredPacePerDay(for: item.chapter, in: item.project) {
                totalRequired += pace
                conflictingNames.append(item.chapter.name)
            }
        }
        guard conflictingNames.count >= 2 else { return }

        UserDefaults.standard.set(today, forKey: todayKey)
        let names = conflictingNames.prefix(2).joined(separator: " & ")
        NotificationManager.shared.scheduleDeadlineConflictAlert(
            chapterNames: names,
            totalRequiredPerDay: totalRequired,
            useWordCount: data.useWordCount
        )
    }

    // MARK: - #25 Export .ics

    func generateICS() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd"
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//ThesisTracker//Writing Process//FR",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH"
        ]

        // Chapitres avec deadline
        for item in chaptersWithDeadlines {
            guard let deadline = DataStore.parseDate(item.chapter.deadline ?? "") else { continue }
            let effectiveDeadline = effectiveDeadlineDate(for: item.chapter.deadline) ?? deadline
            // DTEND = lendemain (exclusif dans iCal)
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: effectiveDeadline) ?? effectiveDeadline
            let progress = "\(DataStore.formatNumber(latestTotal(for: item.chapter.id, in: item.project.id))) / \(DataStore.formatNumber(item.chapter.goal)) car."
            lines += [
                "BEGIN:VEVENT",
                "UID:\(item.chapter.id.uuidString)@thesistracker",
                "DTSTART;VALUE=DATE:\(fmt.string(from: effectiveDeadline))",
                "DTEND;VALUE=DATE:\(fmt.string(from: endDate))",
                "SUMMARY:[Deadline] \(item.chapter.name) — \(item.project.name)",
                "DESCRIPTION:Progression : \(progress)\\nProjet : \(item.project.name)",
                "CATEGORIES:DEADLINE",
                "STATUS:\(item.chapter.isCompleted ? "COMPLETED" : "CONFIRMED")",
                "END:VEVENT"
            ]
        }

        // Jalons
        for item in allMilestonesSorted {
            guard let date = DataStore.parseDate(item.milestone.date) else { continue }
            let endDate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            var desc = "Projet : \(item.project.name)"
            desc += "\\nStatut : \(item.milestone.milestoneStatus.label)"
            if let notes = item.milestone.notes, !notes.isEmpty {
                desc += "\\nNotes : \(notes)"
            }
            // #45 — VALARM avec jours de rappel personnalisés
            let alarmTrigger = "-P\(item.milestone.reminderDays)DT\(item.milestone.reminderHour)H"
            let alarmBlock: [String] = [
                "BEGIN:VALARM",
                "ACTION:DISPLAY",
                "DESCRIPTION:Rappel jalon : \(item.milestone.title)",
                "TRIGGER:\(alarmTrigger)",
                "END:VALARM"
            ]
            lines += [
                "BEGIN:VEVENT",
                "UID:\(item.milestone.id.uuidString)@thesistracker",
                "DTSTART;VALUE=DATE:\(fmt.string(from: date))",
                "DTEND;VALUE=DATE:\(fmt.string(from: endDate))",
                "SUMMARY:[Jalon] \(item.milestone.title) — \(item.project.name)",
                "DESCRIPTION:\(desc)",
                "CATEGORIES:MILESTONE",
                "STATUS:\(item.milestone.isCompleted ? "COMPLETED" : "CONFIRMED")"
            ]
            lines += alarmBlock
            lines.append("END:VEVENT")
        }

        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n")
    }

    // MARK: - Milestone notifications (#59)

    private func scheduleMilestoneNotificationsIfNeeded() {
        // #42 — Rappels personnalisables par jalon
        let today = Date()
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        var items: [NotificationManager.MilestoneNotifItem] = []
        for project in data.projects where !project.isArchived {
            for milestone in project.milestones where !milestone.isCompleted && milestone.milestoneStatus != .validated {
                guard let date = fmt.date(from: milestone.date), date > today else { continue }
                items.append(NotificationManager.MilestoneNotifItem(
                    projectName:   project.name,
                    milestoneName: milestone.title,
                    date:          date,
                    milestoneId:   milestone.id.uuidString,
                    reminderDays:  milestone.reminderDays,
                    reminderHour:  milestone.reminderHour
                ))
            }
        }
        NotificationManager.shared.scheduleMilestoneNotifications(milestones: items)
    }

    // MARK: - #46 Chemin critique

    struct CriticalMilestone: Identifiable {
        let id: UUID
        let project: Project
        let milestone: Milestone
        let daysLeft: Int
        let urgency: CriticalUrgency
        /// True if another incomplete milestone in the same project follows this one
        let isBlocking: Bool
    }

    enum CriticalUrgency: Int, Comparable {
        case urgent   = 0   // ≤ 7j
        case high     = 1   // ≤ 14j
        case medium   = 2   // ≤ 30j
        case low      = 3   // > 30j but rejected or has a blocker
        static func < (l: Self, r: Self) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self {
            case .urgent:  return "Critique"
            case .high:    return "Risque élevé"
            case .medium:  return "À surveiller"
            case .low:     return "À anticiper"
            }
        }
        var color: Color {
            switch self {
            case .urgent:  return Color(red: 0.93, green: 0.26, blue: 0.26)
            case .high:    return Color(red: 0.96, green: 0.55, blue: 0.10)
            case .medium:  return Color(red: 0.93, green: 0.75, blue: 0.12)
            case .low:     return Color(red: 0.40, green: 0.70, blue: 0.90)
            }
        }
        var icon: String {
            switch self {
            case .urgent: return "exclamationmark.triangle.fill"
            case .high:   return "exclamationmark.circle.fill"
            case .medium: return "clock.badge.exclamationmark"
            case .low:    return "info.circle"
            }
        }
    }

    var criticalPathMilestones: [CriticalMilestone] {
        if let c = _criticalPathCache, c.version == dataVersion { return c.items }
        let cal  = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [CriticalMilestone] = []

        for project in data.projects where !project.isArchived {
            let incompleteSorted = project.milestones
                .filter { !$0.isCompleted && $0.milestoneStatus != .validated }
                .compactMap { m -> (Milestone, Date)? in
                    guard let d = DataStore.parseDate(m.date) else { return nil }
                    return (m, cal.startOfDay(for: d))
                }
                .sorted { $0.1 < $1.1 }

            for (idx, (milestone, mDate)) in incompleteSorted.enumerated() {
                let days = cal.dateComponents([.day], from: today, to: mDate).day ?? 0

                // Is blocking: there are later incomplete milestones in the same project
                let isBlocking = idx < incompleteSorted.count - 1

                // Urgency based on days + rejection status
                let urgency: CriticalUrgency
                if milestone.milestoneStatus == .rejected || days < 0 {
                    urgency = .urgent
                } else if days <= 7 {
                    urgency = .urgent
                } else if days <= 14 {
                    urgency = .high
                } else if days <= 30 {
                    urgency = .medium
                } else if isBlocking {
                    urgency = .low
                } else {
                    continue  // Not critical enough to show
                }

                result.append(CriticalMilestone(
                    id: milestone.id, project: project,
                    milestone: milestone, daysLeft: days,
                    urgency: urgency, isBlocking: isBlocking
                ))
            }
        }

        let sorted = result.sorted { $0.urgency < $1.urgency }
        _criticalPathCache = (dataVersion, sorted)
        return sorted
    }

    // MARK: - Weekly report notification (#60)

    private func scheduleWeeklyReportNotificationIfNeeded() {
        // Calcule les stats de la semaine courante et planifie la notif hebdo (dimanche 19h)
        let cal = DataStore.gregorianCal
        var calMon = cal; calMon.firstWeekday = 2
        let now = Date()
        guard let weekStart = calMon.dateInterval(of: .weekOfYear, for: now)?.start else { return }

        var weekTotal = 0; var daysWritten = 0; var bestDay = 0
        let totals = dailyTotals()
        var cursor = weekStart
        while cursor <= now {
            let val = totals[DataStore.dateString(from: cursor)] ?? 0
            weekTotal += val
            if val > 0 { daysWritten += 1 }
            if val > bestDay { bestDay = val }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? now + 1
        }

        NotificationManager.shared.scheduleWeeklyReportNotification(
            weekTotal: weekTotal, daysWritten: daysWritten,
            bestDay: bestDay, useWordCount: data.useWordCount)
    }

    // MARK: - #64 Snapshot restoration

    func listSnapshots() -> [(url: URL, date: Date, size: Int64)] {
        let dir = snapshotsDirectoryURL
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> (URL, Date, Int64)? in
                let res = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let date = res?.contentModificationDate ?? .distantPast
                let size = Int64(res?.fileSize ?? 0)
                return (url, date, size)
            }
            .sorted { $0.date > $1.date }
    }

    func restoreSnapshot(from url: URL) throws {
        let jsonData = try Data(contentsOf: url)
        var decoded = try DataStore.decodeAppData(jsonData).data
        applyLegacyMigration(&decoded)
        data = decoded
        dataVersion += 1
        // Restauration volontaire : autorise de nouveau l'écriture.
        markLoaded()
        loadErrorMessage = nil
        save()
    }

    // MARK: - #66 Manual JSON export

    func exportJSONData() -> Data? {
        try? DataStore.sharedEncoder.encode(data)
    }

    // MARK: - #67 Corruption detection

    struct CorruptionIssue: Identifiable {
        let id = UUID()
        let severity: Severity
        let message: String
        enum Severity { case warning, error }
    }

    @Published var corruptionIssues: [CorruptionIssue] = []

    func validateDataIntegrity() {
        // Snapshot projects (struct copy-on-write — no real copy until mutation)
        // and run the O(N) validation off the main thread so it never blocks
        // first-frame rendering on launch.
        let snapshot = data.projects
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let dateFmt = DateFormatter(); dateFmt.dateFormat = "yyyy-MM-dd"
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
            let tomorrowStr = DataStore.dateString(from: tomorrow)
            var issues: [CorruptionIssue] = []

            for project in snapshot {
                for chapter in project.chapters {
                    for entry in chapter.entries {
                        if entry.totalCount < 0 {
                            issues.append(.init(severity: .error,
                                message: "Total négatif dans \"\(chapter.name)\" (\(project.name)) à la date \(entry.date) : \(entry.totalCount)"))
                        }
                        if dateFmt.date(from: entry.date) == nil {
                            issues.append(.init(severity: .error,
                                message: "Date invalide dans \"\(chapter.name)\" : \"\(entry.date)\""))
                        }
                        if entry.date > tomorrowStr {
                            issues.append(.init(severity: .warning,
                                message: "Entrée dans le futur dans \"\(chapter.name)\" : \(entry.date)"))
                        }
                    }
                    if chapter.goal < 0 {
                        issues.append(.init(severity: .warning,
                            message: "Objectif négatif pour \"\(chapter.name)\" (\(project.name)) : \(chapter.goal)"))
                    }
                }
            }
            DispatchQueue.main.async { self?.corruptionIssues = issues }
        }
    }

    // MARK: - #68 Entry compaction

    func compactOldEntries(olderThanYears years: Int = 2) -> Int {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .year, value: -years, to: Date()) else { return 0 }
        let cutoffStr = DataStore.dateString(from: cutoff)
        var count = 0

        for projIdx in data.projects.indices {
            for chapIdx in data.projects[projIdx].chapters.indices {
                let chapter = data.projects[projIdx].chapters[chapIdx]
                let (old, recent) = chapter.entries.reduce(into: ([DailyEntry](), [DailyEntry]())) { acc, e in
                    if e.date < cutoffStr { acc.0.append(e) } else { acc.1.append(e) }
                }
                guard !old.isEmpty else { continue }

                // Group by YYYY-MM → keep last entry of each month
                var byMonth = [String: DailyEntry]()
                for entry in old {
                    let monthKey = String(entry.date.prefix(7))
                    if let existing = byMonth[monthKey] {
                        if entry.date > existing.date { byMonth[monthKey] = entry }
                    } else {
                        byMonth[monthKey] = entry
                    }
                }
                let compacted = byMonth.values.sorted { $0.date < $1.date }
                let removed = old.count - compacted.count
                count += removed
                data.projects[projIdx].chapters[chapIdx].entries = (compacted + recent)
                    .sorted { $0.date < $1.date }
            }
        }
        if count > 0 {
            dataVersion += 1
            save()
        }
        return count
    }

    // MARK: - #69 Usage statistics

    private static let usageDefaultsPrefix = "appUsage_"

    func trackAppOpen() {
        let key = Self.usageDefaultsPrefix + "opens_" + currentMonthKey
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(count + 1, forKey: key)
    }

    var appOpensThisMonth: Int {
        UserDefaults.standard.integer(forKey: Self.usageDefaultsPrefix + "opens_" + currentMonthKey)
    }

    private var currentMonthKey: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    // MARK: - #70 iCloud conflict detection

    struct iCloudConflict {
        let localURL: URL
        let iCloudURL: URL
        let localData: AppData
        let iCloudData: AppData
        let localModified: Date
        let iCloudModified: Date
    }

    @Published var pendingConflict: iCloudConflict? = nil

    func checkForConflict() {
        guard let iCloudURL = iCloudDriveFileURL else { return }
        let localURL = localFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: localURL.path),
              fm.fileExists(atPath: iCloudURL.path) else { return }

        guard let localData = try? Data(contentsOf: localURL),
              let iCloudData = try? Data(contentsOf: iCloudURL),
              localData != iCloudData else { return }  // identical → no conflict

        guard let localDecoded  = try? DataStore.sharedDecoder.decode(AppData.self, from: localData),
              let iCloudDecoded = try? DataStore.sharedDecoder.decode(AppData.self, from: iCloudData) else { return }

        let localMod  = (try? localURL.resourceValues(forKeys:  [.contentModificationDateKey]).contentModificationDate)  ?? .distantPast
        let iCloudMod = (try? iCloudURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast

        let localEntries  = localDecoded.projects.flatMap(\.chapters).flatMap(\.entries).count
        let iCloudEntries = iCloudDecoded.projects.flatMap(\.chapters).flatMap(\.entries).count
        guard localEntries != iCloudEntries || localMod.timeIntervalSince(iCloudMod).magnitude > 60 else { return }

        DispatchQueue.main.async {
            self.pendingConflict = iCloudConflict(
                localURL: localURL, iCloudURL: iCloudURL,
                localData: localDecoded, iCloudData: iCloudDecoded,
                localModified: localMod, iCloudModified: iCloudMod)
        }
    }

    func resolveConflict(keepLocal: Bool) {
        guard let conflict = pendingConflict else { return }
        pendingConflict = nil
        let chosen = keepLocal ? conflict.localData : conflict.iCloudData
        // Write the SAME encoded bytes to BOTH files so the next launch sees
        // identical data + matching mod dates → no spurious re-conflict.
        if let encoded = try? DataStore.sharedEncoder.encode(chosen) {
            try? encoded.write(to: conflict.localURL,  options: .atomic)
            try? encoded.write(to: conflict.iCloudURL, options: .atomic)
        }
        data = chosen
        dataVersion += 1
        objectWillChange.send()
    }

    // MARK: - Research entries (feature #2)

    func addResearchEntry(_ entry: ResearchEntry) {
        data.researchEntries.insert(entry, at: 0)
        save()
    }

    func deleteResearchEntry(_ id: UUID) {
        data.researchEntries.removeAll { $0.id == id }
        save()
    }

    func researchEntries(for date: String) -> [ResearchEntry] {
        data.researchEntries.filter { $0.date == date }
    }

    func totalResearchMinutes(for date: String) -> Int {
        researchEntries(for: date).reduce(0) { $0 + $1.durationMinutes }
    }

    /// Minutes de recherche des 14 derniers jours, par date "yyyy-MM-dd"
    func researchTotals14Days() -> [String: Int] {
        let cal = Calendar.current
        let today = Date()
        var result: [String: Int] = [:]
        for day in 0..<14 {
            guard let d = cal.date(byAdding: .day, value: -day, to: today) else { continue }
            let key = Self.dateString(from: d)
            result[key] = researchEntries(for: key).reduce(0) { $0 + $1.durationMinutes }
        }
        return result
    }

    // MARK: - Chapter next step (feature #1)

    func updateNextStep(_ text: String?, for chapterId: UUID, in projectId: UUID) {
        guard let pi = data.projects.firstIndex(where: { $0.id == projectId }),
              let ci = data.projects[pi].chapters.firstIndex(where: { $0.id == chapterId })
        else { return }
        data.projects[pi].chapters[ci].nextStep = text?.isEmpty == true ? nil : text
        save()
    }

    // MARK: - Chapter structured notes (feature #5)

    func updateChapterNotes(plan: String?, ideas: String?, blockers: String?, general: String?,
                            for chapterId: UUID, in projectId: UUID) {
        guard let pi = data.projects.firstIndex(where: { $0.id == projectId }),
              let ci = data.projects[pi].chapters.firstIndex(where: { $0.id == chapterId })
        else { return }
        data.projects[pi].chapters[ci].notesPlan     = plan?.isEmpty     == true ? nil : plan
        data.projects[pi].chapters[ci].notesIdeas    = ideas?.isEmpty    == true ? nil : ideas
        data.projects[pi].chapters[ci].notesBlockers = blockers?.isEmpty == true ? nil : blockers
        data.projects[pi].chapters[ci].notes         = general?.isEmpty  == true ? nil : general
        save()
    }

    // MARK: - Thesis health score (feature #7)

    enum HealthStatus { case good, warning, critical }

    struct ThesisHealth {
        let score: Int           // 0–100
        let status: HealthStatus
        let headline: String     // ex. "Retard sur 2 chapitres"
        let details: [String]    // sous-points
    }

    var thesisHealth: ThesisHealth {
        var score = 100
        var details: [String] = []

        let cal = Calendar.current

        // 1. Jours sans écriture
        let lastWriteDate = data.projects
            .flatMap { $0.chapters }
            .flatMap { $0.entries }
            .filter { !$0.date.isEmpty }
            .map { $0.date }
            .max()
        let daysSinceWrite: Int
        if let last = lastWriteDate,
           let d = Self.parseDate(last) {
            daysSinceWrite = cal.dateComponents([.day], from: d, to: Date()).day ?? 0
        } else {
            daysSinceWrite = 999
        }
        if daysSinceWrite >= 7 {
            score -= 35
            details.append("Aucune écriture depuis \(daysSinceWrite) jours")
        } else if daysSinceWrite >= 3 {
            score -= 15
            details.append("Aucune écriture depuis \(daysSinceWrite) jours")
        }

        // 2. Deadlines dépassées
        let overdueChapters = data.projects
            .flatMap { p in p.chapters.map { (p, $0) } }
            .filter { _, ch in
                guard let dl = ch.deadline, let d = Self.parseDate(dl) else { return false }
                return d < Date() && ch.status != .termine
            }
        if !overdueChapters.isEmpty {
            score -= min(30, overdueChapters.count * 15)
            details.append("\(overdueChapters.count) deadline\(overdueChapters.count > 1 ? "s" : "") dépassée\(overdueChapters.count > 1 ? "s" : "")")
        }

        // 3. Rythme insuffisant pour deadlines à venir (J-30)
        let slowChapters = data.projects.flatMap { p in
            p.chapters.compactMap { ch -> String? in
                guard let dl = ch.deadline, let dDate = Self.parseDate(dl) else { return nil }
                let daysLeft = cal.dateComponents([.day], from: Date(), to: dDate).day ?? 0
                guard daysLeft > 0, daysLeft <= 30 else { return nil }
                let latest = latestTotal(for: ch.id, in: p.id)
                let needed = ch.goal > 0 ? ch.goal - latest : 0
                guard needed > 0 else { return nil }
                let v = velocity14Days  // global velocity as proxy
                let eta = v > 0 ? needed / v : 999
                return eta > daysLeft ? ch.name : nil
            }
        }
        if !slowChapters.isEmpty {
            score -= min(20, slowChapters.count * 10)
            details.append("Rythme insuffisant : \(slowChapters.prefix(2).joined(separator: ", "))")
        }

        // 4. Aucun chapitre en rédaction active
        let activeChapters = data.projects
            .flatMap(\.chapters)
            .filter { $0.status == .redaction }
        if activeChapters.isEmpty && !data.projects.flatMap(\.chapters).isEmpty {
            score -= 10
            details.append("Aucun chapitre en cours de rédaction")
        }

        // 5. Bonus streak
        if currentStreak >= 7 { score = min(100, score + 10) }

        score = max(0, min(100, score))
        let status: HealthStatus = score >= 70 ? .good : score >= 40 ? .warning : .critical
        let headline: String
        switch status {
        case .good:     headline = details.isEmpty ? "Tout va bien" : details[0]
        case .warning:  headline = details.first ?? "Quelques points d'attention"
        case .critical: headline = details.first ?? "Action requise"
        }
        return ThesisHealth(score: score, status: status, headline: headline, details: details)
    }

    // MARK: - #26 Projection de soutenance

    struct DefenseProjection {
        let totalGoal: Int
        let totalWritten: Int
        let avgDailyChars: Int      // realistic (median of last 30 active days)
        let optimisticDate: Date?   // top-quartile pace
        let realisticDate: Date?    // median pace
        let pessimisticDate: Date?  // bottom-quartile pace
        let daysRemainingRealistic: Int?
    }

    var defenseProjection: DefenseProjection {
        if let c = _defenseProjectionCache, c.version == dataVersion { return c.value }
        let result = _computeDefenseProjection()
        _defenseProjectionCache = (dataVersion, result)
        return result
    }

    private func _computeDefenseProjection() -> DefenseProjection {
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        var totalGoal = 0; var totalWritten = 0
        for proj in data.projects where !proj.isArchived {
            for ch in proj.chapters where !ch.isCompleted {
                totalGoal += ch.goal
                if let latest = ch.entries.max(by: { $0.date < $1.date }) {
                    totalWritten += latest.totalCount
                }
            }
        }
        let remaining = max(0, totalGoal - totalWritten)
        // Collect daily increments (uses shared storageDateFormatter, no alloc)
        var allIncrements: [Int] = []
        for d in 1...60 {
            guard let date     = cal.date(byAdding: .day, value: -d,     to: Date()),
                  let prevDate = cal.date(byAdding: .day, value: -(d+1), to: Date()) else { continue }
            let delta = (totals[DataStore.dateString(from: date)] ?? 0)
                      - (totals[DataStore.dateString(from: prevDate)] ?? 0)
            if delta > 0 { allIncrements.append(delta) }
        }
        guard !allIncrements.isEmpty else {
            return DefenseProjection(totalGoal: totalGoal, totalWritten: totalWritten,
                                      avgDailyChars: 0, optimisticDate: nil,
                                      realisticDate: nil, pessimisticDate: nil,
                                      daysRemainingRealistic: nil)
        }
        let sorted  = allIncrements.sorted()
        let median  = sorted[sorted.count / 2]
        let q75     = sorted[min(sorted.count - 1, sorted.count * 3 / 4)]
        let q25     = sorted[max(0, sorted.count / 4)]
        func projDate(charsPerDay: Int) -> Date? {
            guard charsPerDay > 0, remaining > 0 else { return nil }
            return cal.date(byAdding: .day, value: Int(ceil(Double(remaining) / Double(charsPerDay))), to: Date())
        }
        let realisticDate = projDate(charsPerDay: median)
        let daysRemaining: Int? = realisticDate.map { cal.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
        return DefenseProjection(
            totalGoal: totalGoal, totalWritten: totalWritten, avgDailyChars: median,
            optimisticDate: projDate(charsPerDay: q75),
            realisticDate:  realisticDate,
            pessimisticDate: projDate(charsPerDay: max(1, q25)),
            daysRemainingRealistic: daysRemaining
        )
    }

    // MARK: - #27 Taux de consistance

    func consistencyRate(days: Int) -> Double {
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        var activeDays = 0
        for d in 0..<days {
            guard let date = cal.date(byAdding: .day, value: -d, to: Date()) else { continue }
            let ds = DataStore.dateString(from: date)
            if (totals[ds] ?? 0) > 0 { activeDays += 1 }
        }
        return Double(activeDays) / Double(max(1, days))
    }

    // MARK: - #28 Courbe d'accélération

    struct AccelerationData {
        let recentAvg: Int    // avg chars/day over last 14 days
        let priorAvg: Int     // avg chars/day over days 15–28
        let trend: Double     // (recentAvg / priorAvg) - 1 — positive = accelerating
        let last14Increments: [Int]
    }

    var accelerationData: AccelerationData {
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        var recentSum = 0; var priorSum = 0
        var recent14: [Int] = []
        for d in 1...28 {
            guard let date = cal.date(byAdding: .day, value: -d, to: Date()),
                  let prev  = cal.date(byAdding: .day, value: -(d+1), to: Date()) else { continue }
            let ds = DataStore.dateString(from: date)
            let ps = DataStore.dateString(from: prev)
            let delta = max(0, (totals[ds] ?? 0) - (totals[ps] ?? 0))
            if d <= 14 {
                recentSum += delta
                recent14.append(delta)
            } else {
                priorSum += delta
            }
        }
        let recentAvg = recentSum / 14
        let priorAvg  = priorSum  / 14
        let trend     = priorAvg > 0 ? (Double(recentAvg) / Double(priorAvg) - 1.0) : 0.0
        return AccelerationData(recentAvg: recentAvg, priorAvg: priorAvg,
                                trend: trend, last14Increments: recent14.reversed())
    }

    // MARK: - #29 Tableau comparatif chapitres

    struct ChapterComparisonRow: Identifiable {
        let id: UUID
        let projectName: String
        let chapterName: String
        let progressPct: Int
        let avgCharsPerDay: Int
        let estimatedDaysRemaining: Int?
        let latestTotal: Int
        let goal: Int
        let isCompleted: Bool
    }

    var chapterComparisonRows: [ChapterComparisonRow] {
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        // avg from last 14 active days overall
        var rows: [ChapterComparisonRow] = []
        for proj in data.projects where !proj.isArchived {
            for ch in proj.chapters {
                let latest = ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0
                let pct = ch.goal > 0 ? min(100, Int(Double(latest) / Double(ch.goal) * 100)) : 0
                // Chapter-specific daily avg over last 30 days
                var chIncrements: [Int] = []
                let sortedEntries = ch.entries.sorted { $0.date < $1.date }
                for i in 1..<sortedEntries.count {
                    let delta = max(0, sortedEntries[i].totalCount - sortedEntries[i-1].totalCount)
                    if delta > 0 { chIncrements.append(delta) }
                }
                let avgPerDay = chIncrements.isEmpty ? 0 : chIncrements.reduce(0, +) / max(1, chIncrements.count)
                let remaining = max(0, ch.goal - latest)
                let estDays: Int? = (avgPerDay > 0 && remaining > 0 && !ch.isCompleted)
                    ? Int(ceil(Double(remaining) / Double(avgPerDay)))
                    : nil
                rows.append(ChapterComparisonRow(
                    id: ch.id, projectName: proj.name, chapterName: ch.name,
                    progressPct: pct, avgCharsPerDay: avgPerDay,
                    estimatedDaysRemaining: estDays,
                    latestTotal: latest, goal: ch.goal, isCompleted: ch.isCompleted
                ))
            }
        }
        return rows.sorted { $0.progressPct > $1.progressPct }
    }

    // MARK: - #30 Mois en revue

    struct MonthReview {
        let monthLabel: String
        let totalChars: Int
        let activeDays: Int
        let bestDayChars: Int
        let bestDayDate: String
        let prevMonthTotal: Int
        let prevMonthActiveDays: Int
        let growthPct: Double  // vs previous month
    }

    var currentMonthReview: MonthReview {
        let cal = DataStore.gregorianCal
        let now = Date()
        let totals = dailyTotals()

        let thisMonth  = cal.component(.month, from: now)
        let thisYear   = cal.component(.year,  from: now)
        let prevMonth  = thisMonth == 1 ? 12 : thisMonth - 1
        let prevYear   = thisMonth == 1 ? thisYear - 1 : thisYear

        var thisTotal = 0; var thisActive = 0
        var bestChars = 0; var bestDate  = ""
        var prevTotal = 0; var prevActive = 0

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        for (ds, val) in totals where val > 0 {
            guard let d = fmt.date(from: ds) else { continue }
            let m = cal.component(.month, from: d)
            let y = cal.component(.year,  from: d)
            if m == thisMonth && y == thisYear {
                thisTotal  += val; thisActive += 1
                if val > bestChars { bestChars = val; bestDate = ds }
            } else if m == prevMonth && y == prevYear {
                prevTotal += val; prevActive += 1
            }
        }

        let growth = prevTotal > 0 ? (Double(thisTotal) / Double(prevTotal) - 1.0) * 100 : 0.0

        let monthFmt = DateFormatter()
        monthFmt.locale = Locale(identifier: "fr_FR")
        monthFmt.dateFormat = "MMMM yyyy"
        let monthLabel = monthFmt.string(from: now).capitalized

        return MonthReview(monthLabel: monthLabel, totalChars: thisTotal, activeDays: thisActive,
                           bestDayChars: bestChars, bestDayDate: bestDate,
                           prevMonthTotal: prevTotal, prevMonthActiveDays: prevActive,
                           growthPct: growth)
    }

    // MARK: - #31 Vélocité glissante (fenêtre 14j)

    struct VelocityPoint14: Identifiable {
        let id = UUID()
        let dateStr: String
        let rollingAvg: Double
    }

    var rollingVelocity14: [VelocityPoint14] {
        let totals = dailyTotals()
        let cal = DataStore.gregorianCal
        var result: [VelocityPoint14] = []
        for d in (0..<60).reversed() {
            guard let date = cal.date(byAdding: .day, value: -d, to: Date()) else { continue }
            let ds = DataStore.dateString(from: date)
            var windowSum = 0; var windowCount = 0
            for w in 0..<14 {
                guard let wDate = cal.date(byAdding: .day, value: -w, to: date) else { continue }
                let ws = DataStore.dateString(from: wDate)
                if let v = totals[ws], v > 0 { windowSum += v; windowCount += 1 }
            }
            let avg = windowCount > 0 ? Double(windowSum) / Double(windowCount) : 0
            result.append(VelocityPoint14(dateStr: ds, rollingAvg: avg))
        }
        return result
    }

    // MARK: - #32 Heatmap horaire d'écriture

    struct HourHeatmapEntry: Identifiable {
        let id = UUID()
        let hour: Int
        let totalChars: Int
        let entryCount: Int
    }

    var hourHeatmapData: [HourHeatmapEntry] {
        if let c = _hourHeatmapCache, c.version == dataVersion { return c.entries }
        var charsByHour  = [Int](repeating: 0, count: 24)
        var countsByHour = [Int](repeating: 0, count: 24)
        for proj in data.projects {
            for ch in proj.chapters {
                let sorted = ch.entries.sorted { $0.date < $1.date }
                var prev = 0
                for entry in sorted {
                    let delta = max(0, entry.totalCount - prev)
                    if delta > 0, let h = entry.savedAtHour, h >= 0, h < 24 {
                        charsByHour[h]  += delta
                        countsByHour[h] += 1
                    }
                    prev = entry.totalCount
                }
            }
        }
        let entries = (0..<24).map { h in
            HourHeatmapEntry(hour: h, totalChars: charsByHour[h], entryCount: countsByHour[h])
        }
        _hourHeatmapCache = (dataVersion, entries)
        return entries
    }
}
