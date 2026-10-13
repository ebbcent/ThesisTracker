import Foundation

struct PomodoroStoreBootstrap {
    let data: PomodoroAppData
    let fileURL: URL
    let locationDescription: String
    /// `false` quand le fichier existe (iCloud) mais n'a pas pu être lu : toute écriture est refusée
    /// pour ne jamais écraser les données de l'autre Mac.
    var isWritable: Bool = true
    /// Message à afficher à l'utilisateur (restauration, mode lecture seule…).
    var warning: String? = nil
}

struct PomodoroStoreError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

actor PomodoroDataStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let fileName = "pomodoro-data.json"
    private let directoryName = "POMODORO"
    private let backupDirectoryName = "Backups"
    private let iCloudDriveFolder = "Library/Mobile Documents/com~apple~CloudDocs"

    /// Durée maximale d'attente du téléchargement d'un fichier iCloud évincé.
    private let downloadTimeout: TimeInterval = 10
    /// Durée de conservation des pierres tombales de suppression.
    nonisolated static let tombstoneRetention: TimeInterval = 180 * 24 * 3600

    /// Passe à `false` si le fichier de données n'a pas pu être lu : on refuse alors d'écrire.
    private var isWriteSafe = true

    private enum LoadOutcome {
        case loaded(PomodoroAppData)
        /// Lecture impossible (fichier iCloud non matérialisé, hors ligne, permissions…)
        case unreadable
        /// Fichier lu mais JSON invalide
        case corrupt
    }

    func bootstrap(bundleIdentifier: String) async throws -> PomodoroStoreBootstrap {
        let storageLocation = try resolveStorageLocation(bundleIdentifier: bundleIdentifier)
        let container = storageLocation.directoryURL
        let dataURL = container.appending(path: fileName)
        let backupsURL = container.appending(path: backupDirectoryName, directoryHint: .isDirectory)
        let placeholderURL = container.appending(path: ".\(fileName).icloud")
        let description = storageLocation.description

        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        func makeBootstrap(_ data: PomodoroAppData, writable: Bool = true, warning: String? = nil) -> PomodoroStoreBootstrap {
            PomodoroStoreBootstrap(
                data: data,
                fileURL: dataURL,
                locationDescription: description,
                isWritable: writable,
                warning: warning
            )
        }

        // 1. Fichier évincé par iCloud (« .pomodoro-data.json.icloud ») : demander le téléchargement et patienter.
        if !fileExists(dataURL) && fileExists(placeholderURL) {
            try? FileManager.default.startDownloadingUbiquitousItem(at: dataURL)
            let deadline = Date().addingTimeInterval(downloadTimeout)
            while !fileExists(dataURL) && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !fileExists(dataURL) {
                isWriteSafe = false
                return makeBootstrap(
                    Self.readOnlyPlaceholder(),
                    writable: false,
                    warning: "Le fichier Pomodoro n'est pas encore téléchargé depuis iCloud : enregistrement désactivé. Ouvre le dossier POMODORO d'iCloud Drive dans le Finder puis relance l'app."
                )
            }
        }

        // 2. Fichier absent (premier lancement) : restaurer une sauvegarde si possible. Sinon on démarre
        // en mémoire SANS écrire de fichier vide : la première sauvegarde fusionnera avec ce qu'iCloud
        // aura éventuellement synchronisé entre-temps.
        if !fileExists(dataURL) {
            if let restored = try? restoreLatestBackup(from: backupsURL, to: dataURL) {
                return makeBootstrap(Self.normalized(restored), warning: "Fichier de données absent : dernière sauvegarde restaurée.")
            }
            return makeBootstrap(PomodoroAppData.empty())
        }

        // 3. Lecture (avec nouvelle tentative si le fichier iCloud n'est pas matérialisé).
        var outcome = attemptLoad(from: dataURL)
        if case .unreadable = outcome {
            try? FileManager.default.startDownloadingUbiquitousItem(at: dataURL)
            let deadline = Date().addingTimeInterval(downloadTimeout)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(500))
                outcome = attemptLoad(from: dataURL)
                if case .unreadable = outcome { continue }
                break
            }
        }

        switch outcome {
        case .loaded(let data):
            return makeBootstrap(Self.normalized(data))
        case .unreadable:
            isWriteSafe = false
            return makeBootstrap(
                Self.readOnlyPlaceholder(),
                writable: false,
                warning: "Impossible de lire le fichier Pomodoro (iCloud ?) : enregistrement désactivé pour ne pas l'écraser. Relance l'app une fois le fichier disponible."
            )
        case .corrupt:
            // Ne jamais écraser un fichier illisible : on le met de côté avant toute restauration.
            guard moveAsideCorruptFile(dataURL) else {
                isWriteSafe = false
                return makeBootstrap(
                    Self.readOnlyPlaceholder(),
                    writable: false,
                    warning: "Fichier Pomodoro illisible et impossible à mettre de côté : enregistrement désactivé."
                )
            }
            if let restored = try? restoreLatestBackup(from: backupsURL, to: dataURL) {
                return makeBootstrap(Self.normalized(restored), warning: "Fichier Pomodoro illisible mis de côté (.corrupt) : dernière sauvegarde restaurée.")
            }
            return makeBootstrap(PomodoroAppData.empty(), warning: "Fichier Pomodoro illisible mis de côté (.corrupt) et aucune sauvegarde valide.")
        }
    }

    func save(_ data: PomodoroAppData, to fileURL: URL) throws -> PomodoroAppData {
        guard isWriteSafe else {
            throw PomodoroStoreError(message: "Enregistrement désactivé : le fichier Pomodoro n'a pas pu être lu au démarrage.")
        }
        let directoryURL = fileURL.deletingLastPathComponent()
        let backupsURL = directoryURL.appending(path: backupDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let merged: PomodoroAppData
        if fileExists(fileURL) {
            switch attemptLoad(from: fileURL) {
            case .loaded(let disk):
                merged = Self.merge(local: data, remote: disk)
            case .unreadable:
                // Fichier présent mais pas lisible (téléchargement iCloud en cours…) : ne pas l'écraser.
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                throw PomodoroStoreError(message: "Fichier Pomodoro momentanément illisible (iCloud) : enregistrement reporté.")
            case .corrupt:
                guard moveAsideCorruptFile(fileURL) else {
                    throw PomodoroStoreError(message: "Fichier Pomodoro illisible : enregistrement annulé.")
                }
                merged = Self.normalized(data)
            }
        } else {
            let placeholderURL = directoryURL.appending(path: ".\(fileURL.lastPathComponent).icloud")
            if fileExists(placeholderURL) {
                // Évincé par iCloud entre-temps : ne jamais écrire par-dessus.
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
                throw PomodoroStoreError(message: "Fichier Pomodoro évincé par iCloud : enregistrement reporté.")
            }
            merged = Self.normalized(data)
        }

        if fileExists(fileURL) {
            let backupName = "pomodoro-\(ISO8601DateFormatter().string(from: .now)).json"
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = backupsURL.appending(path: backupName)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            trimBackups(in: backupsURL, keeping: 8)
        }

        try write(merged, to: fileURL)
        return merged
    }

    /// Lit le fichier tel qu'il est sur le disque (la fusion est faite par l'appelant).
    func readDisk(from fileURL: URL) throws -> PomodoroAppData {
        switch attemptLoad(from: fileURL) {
        case .loaded(let data):
            // Le fichier est lisible : l'appelant fusionne avant d'écrire, l'écriture redevient sûre.
            isWriteSafe = true
            return data
        case .unreadable:
            throw PomodoroStoreError(message: "Fichier Pomodoro momentanément illisible.")
        case .corrupt:
            throw PomodoroStoreError(message: "Fichier Pomodoro illisible (JSON invalide).")
        }
    }

    /// Écriture synchrone de secours (fermeture de l'app) : fusion avec le disque puis écriture atomique.
    /// N'écrit rien si le fichier présent ne peut pas être lu.
    nonisolated static func saveSynchronously(_ data: PomodoroAppData, to fileURL: URL) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        var merged = Self.normalized(data)
        if FileManager.default.fileExists(atPath: fileURL.path()) {
            guard let raw = try? Data(contentsOf: fileURL),
                  let disk = try? decoder.decode(PomodoroAppData.self, from: raw) else { return }
            merged = Self.merge(local: data, remote: disk)
        } else {
            let placeholderURL = fileURL.deletingLastPathComponent().appending(path: ".\(fileURL.lastPathComponent).icloud")
            if FileManager.default.fileExists(atPath: placeholderURL.path()) { return }
        }
        guard let payload = try? encoder.encode(merged) else { return }
        try? payload.write(to: fileURL, options: .atomic)
    }

    func reloadMerging(with current: PomodoroAppData, from fileURL: URL) throws -> PomodoroAppData {
        let disk = try readDisk(from: fileURL)
        return Self.merge(local: current, remote: disk)
    }

    func exportJSON(_ data: PomodoroAppData, to url: URL) throws {
        try write(data, to: url)
    }

    func exportCSV(_ data: PomodoroAppData, to url: URL) throws {
        let timezone = TimeZone.current.identifier
        let header = "id,startedAt,endedAt,timezone,durationMinutes,plannedMinutes,kind,completionState,categoryID,projectID,note\n"
        let rows = data.sessions.map { session in
            [
                session.id.uuidString,
                session.startedAt.ISO8601Format(),
                session.endedAt.ISO8601Format(),
                timezone,
                String(Int(session.duration / 60)),
                String(Int(session.plannedDuration / 60)),
                session.kind.rawValue,
                session.completionState.rawValue,
                session.categoryID?.uuidString ?? "",
                session.projectID?.uuidString ?? "",
                session.note.replacingOccurrences(of: "\"", with: "\"\"")
            ]
            .map { "\"\($0)\"" }
            .joined(separator: ",")
        }
        let csv = header + rows.joined(separator: "\n")
        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func resolveStorageLocation(bundleIdentifier: String) throws -> StorageLocationInfo {
        if let iCloudDirectory = iCloudDriveDirectory() {
            do {
                try FileManager.default.createDirectory(at: iCloudDirectory, withIntermediateDirectories: true)
                return StorageLocationInfo(
                    directoryURL: iCloudDirectory,
                    description: "Stockage JSON iCloud Drive"
                )
            } catch {}
        }

        let localDirectory = try localDirectory(bundleIdentifier: bundleIdentifier)
        return StorageLocationInfo(
            directoryURL: localDirectory,
            description: "Stockage JSON local"
        )
    }

    private func localDirectory(bundleIdentifier: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents
            .appending(path: directoryName, directoryHint: .isDirectory)
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    private func iCloudDriveDirectory() -> URL? {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let iCloudRoot = homeDirectory.appending(path: iCloudDriveFolder, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: iCloudRoot.path()) else { return nil }
        return iCloudRoot.appending(path: directoryName, directoryHint: .isDirectory)
    }

    private func load(from url: URL) throws -> PomodoroAppData {
        let data = try Data(contentsOf: url)
        return try decoder.decode(PomodoroAppData.self, from: data)
    }

    private func attemptLoad(from url: URL) -> LoadOutcome {
        let raw: Data
        do {
            raw = try Data(contentsOf: url)
        } catch {
            return .unreadable
        }
        do {
            return .loaded(try decoder.decode(PomodoroAppData.self, from: raw))
        } catch {
            return .corrupt
        }
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path())
    }

    /// Déplace un fichier illisible vers « <nom>.corrupt-<horodatage>.json » (jamais supprimé).
    private func moveAsideCorruptFile(_ url: URL) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let baseName = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent().appending(path: "\(baseName).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return true
        } catch {
            return false
        }
    }

    private func write(_ data: PomodoroAppData, to url: URL) throws {
        let payload = try encoder.encode(data)
        try payload.write(to: url, options: .atomic)
    }

    private func restoreLatestBackup(from backupsURL: URL, to fileURL: URL) throws -> PomodoroAppData? {
        let backups = try FileManager.default.contentsOfDirectory(at: backupsURL, includingPropertiesForKeys: [.contentModificationDateKey])
            .sorted { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

        for backup in backups {
            if let restored = try? load(from: backup) {
                try write(restored, to: fileURL)
                return restored
            }
        }
        return nil
    }

    private func trimBackups(in directoryURL: URL, keeping count: Int) {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let sorted = urls.sorted { lhs, rhs in
            let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate > rightDate
        }
        for url in sorted.dropFirst(count) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Fusion de deux versions (ce Mac / disque ou autre Mac) :
    /// union par ID, la version la plus récente (`updatedAt`) gagne, la version locale gagne à égalité,
    /// puis retrait des éléments supprimés (pierre tombale plus récente que l'élément).
    nonisolated static func merge(local: PomodoroAppData, remote: PomodoroAppData) -> PomodoroAppData {
        var tombstones = local.deletedIDs
        for (key, date) in remote.deletedIDs {
            if let existing = tombstones[key], existing >= date { continue }
            tombstones[key] = date
        }
        let cutoff = Date().addingTimeInterval(-tombstoneRetention)
        tombstones = tombstones.filter { $0.value >= cutoff }

        let liveTombstones = tombstones
        func combine<T: Identifiable>(_ lhs: [T], _ rhs: [T], updatedAt: (T) -> Date) -> [T] where T.ID == UUID {
            let union = Self.mergeByID(lhs, rhs, updatedAt: updatedAt)
            return Self.alive(union, tombstones: liveTombstones, updatedAt: updatedAt)
        }

        let categories = combine(local.categories, remote.categories) { $0.updatedAt }
        let projects = combine(local.projects, remote.projects) { $0.updatedAt }
        let goals = combine(local.goals, remote.goals) { $0.updatedAt }
        let sessions = combine(local.sessions, remote.sessions) { $0.updatedAt }
        let workBlocks = combine(local.workBlocks, remote.workBlocks) { $0.updatedAt }

        return PomodoroAppData(
            schemaVersion: max(local.schemaVersion, remote.schemaVersion),
            settings: local.settings.updatedAt >= remote.settings.updatedAt ? local.settings : remote.settings,
            globalStatistics: local.globalStatistics.generatedAt >= remote.globalStatistics.generatedAt ? local.globalStatistics : remote.globalStatistics,
            goals: goals.sorted { $0.createdAt < $1.createdAt },
            categories: categories.sorted { $0.name < $1.name },
            projects: projects.sorted { $0.createdAt < $1.createdAt },
            sessions: sessions.sorted { $0.startedAt < $1.startedAt },
            workBlocks: workBlocks.sorted { $0.startedAt < $1.startedAt },
            updatedAt: max(local.updatedAt, remote.updatedAt),
            deletedIDs: tombstones
        )
    }

    /// Données vides utilisées tant que le vrai fichier est illisible : ni catégories ni objectifs
    /// par défaut, dates anciennes — la fusion avec le fichier, une fois lisible, ne doit rien écraser.
    nonisolated static func readOnlyPlaceholder() -> PomodoroAppData {
        let epoch = Date(timeIntervalSince1970: 0)
        var placeholder = PomodoroAppData.empty(now: epoch)
        placeholder.goals = []
        placeholder.categories = []
        placeholder.settings.updatedAt = epoch
        placeholder.globalStatistics.generatedAt = epoch
        return placeholder
    }

    /// Dédoublonne les IDs et applique les pierres tombales (chargement, écriture).
    nonisolated static func normalized(_ data: PomodoroAppData) -> PomodoroAppData {
        Self.merge(local: data, remote: data)
    }

    private nonisolated static func mergeByID<T: Identifiable>(_ lhs: [T], _ rhs: [T], updatedAt: (T) -> Date) -> [T] where T.ID: Hashable {
        var values: [T.ID: T] = [:]
        // `lhs` (local) parcouru en dernier : il l'emporte à égalité de date.
        for value in rhs + lhs {
            if let existing = values[value.id], updatedAt(existing) > updatedAt(value) {
                continue
            }
            values[value.id] = value
        }
        return Array(values.values)
    }

    private nonisolated static func alive<T: Identifiable>(_ items: [T], tombstones: [String: Date], updatedAt: (T) -> Date) -> [T] where T.ID == UUID {
        guard !tombstones.isEmpty else { return items }
        return items.filter { item in
            guard let deletedAt = tombstones[item.id.uuidString] else { return true }
            // Une modification postérieure à la suppression (autre Mac) l'emporte.
            // Marge d'1 s : les dates sont écrites en ISO 8601 sans fractions de seconde.
            return updatedAt(item) > deletedAt.addingTimeInterval(1)
        }
    }
}

private struct StorageLocationInfo {
    let directoryURL: URL
    let description: String
}
