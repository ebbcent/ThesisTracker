import Foundation
import SwiftUI

// MARK: - 5.26 Créneaux d'écriture depuis un calendrier (adresse .ics)
//
// On colle l'adresse d'un calendrier (lien « webcal:// » ou « https:// » d'un fichier .ics).
// L'app le relit toutes les heures et garde, comme créneaux d'écriture, les événements dont
// le titre contient le mot-clé (« écriture » par défaut, sans tenir compte des accents ni de la casse).
// L'adresse reste sur ce Mac (UserDefaults) : elle n'est pas écrite dans data.json.
// Lecture seule : rien n'est jamais modifié dans le calendrier.

struct CalendarWritingEvent: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
}

// MARK: Lecture du format iCalendar

enum ICSParser {

    private struct RawEvent {
        var uid = ""
        var summary = ""
        var start: Date?
        var end: Date?
        var allDay = false
        var timeZone: TimeZone = .current
        var rrule: [String: String] = [:]
        var exdates: [Date] = []
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Événements dont le titre contient `keyword`, entre `windowStart` et `windowEnd`.
    static func events(from text: String, matching keyword: String,
                       from windowStart: Date, to windowEnd: Date) -> [CalendarWritingEvent] {
        let needle = fold(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
        var out: [CalendarWritingEvent] = []
        for raw in rawEvents(from: text) {
            guard let start = raw.start else { continue }
            if !needle.isEmpty, !fold(raw.summary).contains(needle) { continue }
            let duration: TimeInterval = {
                if let end = raw.end, end > start { return end.timeIntervalSince(start) }
                return raw.allDay ? 86_400 : 3_600
            }()
            for occurrence in occurrences(of: raw, start: start, windowEnd: windowEnd) {
                let end = occurrence.addingTimeInterval(duration)
                guard end >= windowStart, occurrence <= windowEnd else { continue }
                let stamp = Int(occurrence.timeIntervalSince1970)
                out.append(CalendarWritingEvent(id: "\(raw.uid)-\(stamp)", title: raw.summary, start: occurrence, end: end))
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }.sorted { $0.start < $1.start }
    }

    // MARK: Lignes et propriétés

    private static func rawEvents(from text: String) -> [RawEvent] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        // Lignes repliées : une ligne qui commence par une espace ou une tabulation continue la précédente.
        var lines: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if let first = line.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += String(line.dropFirst())
            } else {
                lines.append(line)
            }
        }
        var events: [RawEvent] = []
        var current: RawEvent? = nil
        for line in lines {
            if line == "BEGIN:VEVENT" { current = RawEvent(); continue }
            if line == "END:VEVENT" {
                if let event = current { events.append(event) }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let head = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let headParts = head.components(separatedBy: ";")
            let name = headParts[0].uppercased()
            var params: [String: String] = [:]
            for part in headParts.dropFirst() {
                let pair = part.components(separatedBy: "=")
                if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
            }
            switch name {
            case "UID":
                current?.uid = value
            case "SUMMARY":
                current?.summary = value
                    .replacingOccurrences(of: "\\,", with: ",")
                    .replacingOccurrences(of: "\\;", with: ";")
                    .replacingOccurrences(of: "\\n", with: " ")
                    .replacingOccurrences(of: "\\N", with: " ")
            case "DTSTART":
                let parsed = date(value, params: params)
                current?.start = parsed?.date
                current?.allDay = parsed?.allDay ?? false
                current?.timeZone = parsed?.timeZone ?? .current
            case "DTEND":
                current?.end = date(value, params: params)?.date
            case "RRULE":
                var rule: [String: String] = [:]
                for part in value.components(separatedBy: ";") {
                    let pair = part.components(separatedBy: "=")
                    if pair.count == 2 { rule[pair[0].uppercased()] = pair[1].uppercased() }
                }
                current?.rrule = rule
            case "EXDATE":
                for item in value.components(separatedBy: ",") {
                    if let parsed = date(item, params: params) { current?.exdates.append(parsed.date) }
                }
            default:
                break
            }
        }
        return events
    }

    private static func date(_ value: String, params: [String: String]) -> (date: Date, allDay: Bool, timeZone: TimeZone)? {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let utc = raw.hasSuffix("Z")
        let body = utc ? String(raw.dropLast()) : raw
        let zone: TimeZone = {
            if utc { return TimeZone(identifier: "UTC") ?? .current }
            if let id = params["TZID"], let tz = TimeZone(identifier: id) { return tz }
            return .current
        }()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        if body.count == 8 {
            formatter.dateFormat = "yyyyMMdd"
            guard let d = formatter.date(from: body) else { return nil }
            return (d, true, zone)
        }
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        if let d = formatter.date(from: body) { return (d, false, zone) }
        formatter.dateFormat = "yyyyMMdd'T'HHmm"
        if let d = formatter.date(from: body) { return (d, false, zone) }
        return nil
    }

    // MARK: Répétitions (quotidiennes et hebdomadaires)

    private static let weekdayCodes: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    private static func occurrences(of event: RawEvent, start: Date, windowEnd: Date) -> [Date] {
        let freq = event.rrule["FREQ"] ?? ""
        guard freq == "DAILY" || freq == "WEEKLY" else { return [start] }   // autre répétition : première date seulement

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = event.timeZone
        cal.firstWeekday = 2
        let interval = max(1, Int(event.rrule["INTERVAL"] ?? "1") ?? 1)
        let count = Int(event.rrule["COUNT"] ?? "")
        let until: Date? = event.rrule["UNTIL"].flatMap { date($0, params: [:])?.date }
        let startWeekday = cal.component(.weekday, from: start)
        let days: Set<Int> = {
            let listed = (event.rrule["BYDAY"] ?? "").components(separatedBy: ",")
                .compactMap { weekdayCodes[String($0.suffix(2))] }
            return listed.isEmpty ? [startWeekday] : Set(listed)
        }()
        let startDay = cal.startOfDay(for: start)
        let startWeek = cal.dateInterval(of: .weekOfYear, for: start)?.start ?? startDay

        var out: [Date] = []
        var produced = 0
        for offset in 0..<3_700 {
            guard let occurrence = cal.date(byAdding: .day, value: offset, to: start) else { break }
            if occurrence > windowEnd { break }
            if let until, occurrence > until.addingTimeInterval(86_399) { break }
            let matches: Bool
            if freq == "DAILY" {
                matches = offset % interval == 0
            } else {
                let week = cal.dateInterval(of: .weekOfYear, for: occurrence)?.start ?? occurrence
                let weeks = Int((week.timeIntervalSince(startWeek) / 604_800).rounded())
                matches = weeks % interval == 0 && days.contains(cal.component(.weekday, from: occurrence))
            }
            guard matches else { continue }
            produced += 1
            if let count, produced > count { break }
            if event.exdates.contains(where: { abs($0.timeIntervalSince(occurrence)) < 60 }) { continue }
            out.append(occurrence)
        }
        return out
    }
}

// MARK: - Service : relecture toutes les heures

final class WritingCalendarService: ObservableObject {
    static let shared = WritingCalendarService()

    static let urlKey = "writingCalendarURL"
    static let keywordKey = "writingCalendarKeyword"
    private static let cacheKey = "writingCalendarEvents"
    static let defaultKeyword = "écriture"

    @Published private(set) var events: [CalendarWritingEvent] = []
    @Published private(set) var lastSync: Date? = nil
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isSyncing = false

    private var timer: Timer?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode([CalendarWritingEvent].self, from: data) {
            events = cached
        }
    }

    var address: String { UserDefaults.standard.string(forKey: Self.urlKey) ?? "" }
    var keyword: String {
        let stored = UserDefaults.standard.string(forKey: Self.keywordKey) ?? ""
        return stored.trimmingCharacters(in: .whitespaces).isEmpty ? Self.defaultKeyword : stored
    }

    /// Créneaux à venir ou en cours, du plus proche au plus lointain.
    var upcoming: [CalendarWritingEvent] {
        let now = Date()
        return events.filter { $0.end > now }.sorted { $0.start < $1.start }
    }

    /// Adresse acceptée : http(s), ou webcal:// (converti en https://).
    static func url(from address: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("webcal://") { text = "https://" + text.dropFirst("webcal://".count) }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    /// Au lancement : première lecture, puis une relecture par heure.
    func start() {
        refresh()
        timer?.invalidate()
        let t = Timer(timeInterval: 3_600, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        let address = self.address
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
            events = []
            lastError = nil
            UserDefaults.standard.removeObject(forKey: Self.cacheKey)
            return
        }
        guard let url = Self.url(from: address) else {
            lastError = "Adresse non reconnue (attendu : https://… ou webcal://…)."
            return
        }
        let keyword = self.keyword
        isSyncing = true
        Task {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    await self.finish(events: nil, error: "Le serveur a répondu \(http.statusCode).")
                    return
                }
                guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
                      text.contains("BEGIN:VCALENDAR") else {
                    await self.finish(events: nil, error: "Cette adresse ne renvoie pas un calendrier (.ics).")
                    return
                }
                let now = Date()
                let found = ICSParser.events(from: text, matching: keyword,
                                             from: now.addingTimeInterval(-86_400),
                                             to: now.addingTimeInterval(60 * 86_400))
                await self.finish(events: found, error: nil)
            } catch {
                await self.finish(events: nil, error: "Lecture impossible : \(error.localizedDescription)")
            }
        }
    }

    @MainActor private func finish(events found: [CalendarWritingEvent]?, error: String?) {
        isSyncing = false
        lastError = error
        guard let found else { return }   // en cas d'échec, on garde les créneaux de la dernière lecture
        events = found
        lastSync = Date()
        if let data = try? JSONEncoder().encode(found) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }
}

// MARK: - Réglages

struct WritingCalendarSettingsRow: View {
    @ObservedObject private var service = WritingCalendarService.shared
    @AppStorage(WritingCalendarService.urlKey) private var address: String = ""
    @AppStorage(WritingCalendarService.keywordKey) private var keyword: String = ""

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM · HH:mm"
        return f
    }()
    private static let hourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.accent.opacity(0.12)).frame(width: 34, height: 34)
                    Image(systemName: "calendar.badge.clock").font(.system(size: 13)).foregroundColor(.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Créneaux depuis un calendrier")
                        .font(.system(size: 13, weight: .medium))
                    Text("Colle l'adresse d'un calendrier (.ics, webcal:// ou https://). L'app le relit toutes les heures et garde comme créneaux les événements dont le titre contient le mot-clé. Lecture seule ; l'adresse reste sur ce Mac.")
                        .font(.system(size: 11)).foregroundColor(.labelMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            TextField("webcal://… ou https://…/calendrier.ics", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .onSubmit { service.refresh() }
            HStack(spacing: 10) {
                Text("Mot-clé").font(.system(size: 12)).foregroundColor(.labelMuted)
                TextField(WritingCalendarService.defaultKeyword, text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 150)
                    .onSubmit { service.refresh() }
                Spacer()
                Button(service.isSyncing ? "Lecture…" : "Relire maintenant") { service.refresh() }
                    .buttonStyle(AccentPillButtonStyle())
                    .disabled(service.isSyncing)
            }
            if let error = service.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.semRed)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !address.isEmpty {
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
            }
            ForEach(service.upcoming.prefix(5)) { event in
                HStack(spacing: 8) {
                    Text(Self.dayFormatter.string(from: event.start) + "–" + Self.hourFormatter.string(from: event.end))
                        .font(.system(size: 12, design: .monospaced))
                    Text(event.title)
                        .font(.system(size: 12))
                        .foregroundColor(.labelMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(14)
        .onChange(of: address) { _, _ in service.refresh() }
    }

    private var statusLine: String {
        let count = service.upcoming.count
        let found = count == 0 ? "aucun créneau à venir" : "\(count) créneau\(count > 1 ? "x" : "") à venir"
        guard let sync = service.lastSync else { return found }
        return "Lu à \(Self.hourFormatter.string(from: sync)) · \(found)"
    }
}
