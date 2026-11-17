import Foundation

/// Commandes immuables : leur UUID est réutilisé à chaque nouvel essai.
struct HubWritingCommand: Codable {
    let id: UUID
    let type: String
    let project: UUID
    let chapter: UUID
    var date: String?
    var total: Int?
    var baseTotal: Int?
    var debut: String?
    var fin: String?
    var seconds: Double?
    var planned: Double?
    var completed: Bool?
    var intention: String?

    func validate(now: Date = .now) -> String? {
        if type == "wp-total" {
            guard let date, let total, let baseTotal, (0...10_000_000).contains(total),
                  (0...10_000_000).contains(baseTotal) else { return "Compteur invalide." }
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Europe/Paris"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
            guard let d = f.date(from: date), f.string(from: d) == date,
                  date <= f.string(from: now) else { return "Date invalide ou future." }
        } else if type == "wp-session" {
            guard let debut, let fin, let start = Self.iso(debut), let end = Self.iso(fin),
                  let seconds, let planned, seconds.isFinite, planned.isFinite,
                  seconds >= 60, seconds <= 14_400, planned >= 60, planned <= 14_400,
                  end >= start, end <= now.addingTimeInterval(300),
                  seconds <= end.timeIntervalSince(start) + 2,
                  seconds <= planned + 2, completed != nil, (intention?.count ?? 0) <= 500
            else { return "Session invalide." }
        } else { return "Commande inconnue." }
        return nil
    }
    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Le Mac reste le seul auteur des fichiers métier. L'agent dépose seulement des commandes.
@MainActor
final class HubWritingBridge {
    static let shared = HubWritingBridge()
    private var timer: Timer?
    private var busy = false
    func start(store: DataStore, pomodoro: PomodoroAppController) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self, weak store, weak pomodoro] _ in
            Task { @MainActor in
                guard let self, let store, let pomodoro else { return }
                await self.poll(store: store, pomodoro: pomodoro)
            }
        }
        Task { await poll(store: store, pomodoro: pomodoro) }
    }
    private func poll(store: DataStore, pomodoro: PomodoroAppController) async {
        guard !busy, let root = store.hubDirectory else { return }
        busy = true; defer { busy = false }
        do {
            let fm = FileManager.default, input = root.appendingPathComponent("entrees"), output = root.appendingPathComponent("retours")
            try fm.createDirectory(at: input, withIntermediateDirectories: true)
            try fm.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["version": 1, "t": ISO8601DateFormatter().string(from: .now)])
                .write(to: root.appendingPathComponent("pret.json"), options: .atomic)
            let files = try fm.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent) != nil && !fm.fileExists(atPath: output.appendingPathComponent($0.lastPathComponent.lowercased()).path) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files.prefix(20) {
                guard UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else { continue }
                let bytes = try Data(contentsOf: file)
                guard bytes.count <= 16_384, let c = try? JSONDecoder().decode(HubWritingCommand.self, from: bytes),
                      c.id.uuidString.lowercased() == file.deletingPathExtension().lastPathComponent.lowercased() else { continue }
                let receipt = output.appendingPathComponent(c.id.uuidString.lowercased() + ".json")
                if fm.fileExists(atPath: receipt.path) { continue }
                var failure = c.validate()
                var confirmed = false
                if failure == nil {
                    guard let project = store.data.projects.first(where: { $0.id == c.project && !$0.isArchived }),
                          project.chapters.contains(where: { $0.id == c.chapter && !$0.isArchived }) else {
                        try writeReceipt(c, failure: "Projet ou chapitre absent ou archivé.", to: receipt); continue
                    }
                    if c.type == "wp-total" {
                        failure = store.applyHubTotal(c)
                        confirmed = store.hubTotalIsOnDisk(c.id)
                    } else {
                        failure = await pomodoro.applyHubSession(c)
                        confirmed = failure == nil
                    }
                }
                if failure?.hasPrefix("attente:") == true { continue }
                if failure != nil || confirmed { try writeReceipt(c, failure: failure, to: receipt) }
            }
        } catch { /* iCloud indisponible : aucune perte, réessai au prochain passage. */ }
    }
    private func writeReceipt(_ c: HubWritingCommand, failure: String?, to url: URL) throws {
        try JSONSerialization.data(withJSONObject: ["id": c.id.uuidString.lowercased(), "etat": failure == nil ? "fait" : "refus",
            "message": failure ?? "Enregistré dans Writing Process", "t": ISO8601DateFormatter().string(from: .now)])
            .write(to: url, options: .atomic)
    }
}
