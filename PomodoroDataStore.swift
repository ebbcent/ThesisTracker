import Foundation

struct PomodoroStoreBootstrap {
    let data: PomodoroAppData
    let fileURL: URL
    let locationDescription: String
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

    func bootstrap(bundleIdentifier: String) throws -> PomodoroStoreBootstrap {
        let storageLocation = try resolveStorageLocation(bundleIdentifier: bundleIdentifier)
        let container = storageLocation.directoryURL
        let dataURL = container.appending(path: fileName)
        let backupsURL = container.appending(path: backupDirectoryName, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        if !FileManager.default.fileExists(atPath: dataURL.path()) {
            let empty = PomodoroAppData.empty()
            try write(empty, to: dataURL)
            return PomodoroStoreBootstrap(data: empty, fileURL: dataURL, locationDescription: storageLocation.description)
        }

        do {
            let data = try load(from: dataURL)
            return PomodoroStoreBootstrap(data: data, fileURL: dataURL, locationDescription: storageLocation.description)
        } catch {
            if let restored = try restoreLatestBackup(from: backupsURL, to: dataURL) {
                return PomodoroStoreBootstrap(data: restored, fileURL: dataURL, locationDescription: storageLocation.description)
            }
            let empty = PomodoroAppData.empty()
            try write(empty, to: dataURL)
            return PomodoroStoreBootstrap(data: empty, fileURL: dataURL, locationDescription: storageLocation.description)
        }
    }

    func save(_ data: PomodoroAppData, to fileURL: URL) throws -> PomodoroAppData {
        let directoryURL = fileURL.deletingLastPathComponent()
        let backupsURL = directoryURL.appending(path: backupDirectoryName, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backupsURL, withIntermediateDirectories: true)

        let merged: PomodoroAppData
        if let disk = try? load(from: fileURL) {
            merged = merge(local: data, remote: disk)
        } else {
            merged = data
        }

        if FileManager.default.fileExists(atPath: fileURL.path()) {
            let backupName = "pomodoro-\(ISO8601DateFormatter().string(from: .now)).json"
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = backupsURL.appending(path: backupName)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            trimBackups(in: backupsURL, keeping: 8)
        }

        try write(merged, to: fileURL)
        return merged
    }

    func reloadMerging(with current: PomodoroAppData, from fileURL: URL) throws -> PomodoroAppData {
        let disk = try load(from: fileURL)
        return merge(local: current, remote: disk)
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

    private func merge(local: PomodoroAppData, remote: PomodoroAppData) -> PomodoroAppData {
        let categories = mergeByID(local.categories, remote.categories) { $0.updatedAt }
        let projects = mergeByID(local.projects, remote.projects) { $0.updatedAt }
        let goals = mergeByID(local.goals, remote.goals) { $0.updatedAt }
        let sessions = mergeByID(local.sessions, remote.sessions) { $0.updatedAt }
        let workBlocks = mergeByID(local.workBlocks, remote.workBlocks) { $0.updatedAt }

        return PomodoroAppData(
            schemaVersion: max(local.schemaVersion, remote.schemaVersion),
            settings: local.settings.updatedAt >= remote.settings.updatedAt ? local.settings : remote.settings,
            globalStatistics: local.globalStatistics.generatedAt >= remote.globalStatistics.generatedAt ? local.globalStatistics : remote.globalStatistics,
            goals: goals.sorted { $0.createdAt < $1.createdAt },
            categories: categories.sorted { $0.name < $1.name },
            projects: projects.sorted { $0.createdAt < $1.createdAt },
            sessions: sessions.sorted { $0.startedAt < $1.startedAt },
            workBlocks: workBlocks.sorted { $0.startedAt < $1.startedAt },
            updatedAt: max(local.updatedAt, remote.updatedAt)
        )
    }

    private func mergeByID<T: Identifiable>(_ lhs: [T], _ rhs: [T], updatedAt: (T) -> Date) -> [T] where T.ID: Hashable {
        var values: [T.ID: T] = [:]
        for value in lhs + rhs {
            if let existing = values[value.id], updatedAt(existing) > updatedAt(value) {
                continue
            }
            values[value.id] = value
        }
        return Array(values.values)
    }
}

private struct StorageLocationInfo {
    let directoryURL: URL
    let description: String
}
