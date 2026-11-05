import Foundation

// MARK: - Rythme par chapitre, journées sans écriture, pages de thèse (5.12)

extension DataStore {

    // MARK: Jours ouvrés d'un chapitre

    /// Jour ouvré pour ce chapitre : jours cochés du chapitre s'il en a, sinon
    /// le calendrier général (5.9). Une journée sans écriture n'est jamais ouvrée.
    func isWorkingDay(_ date: Date, for chapter: Chapter) -> Bool {
        if data.restDays.contains(DataStore.dateString(from: date)) { return false }
        if let days = chapter.pacing?.workWeekdays, !days.isEmpty {
            return days.contains(DataStore.gregorianCal.component(.weekday, from: date))
        }
        return isPlannedWritingDay(date)
    }

    // MARK: Plan de rythme

    /// Plan du chapitre selon son profil (ou `profile` pour un aperçu).
    /// Nil sans échéance, sans objectif, ou chapitre terminé.
    func pacingPlan(for chapter: Chapter, profile: PacingProfile? = nil, now: Date = Date()) -> PacingPlan? {
        guard !chapter.isCompleted, chapter.goal > 0,
              let deadline = effectiveDeadlineDate(for: chapter.deadline) else { return nil }
        let cal = DataStore.gregorianCal
        guard cal.startOfDay(for: deadline) >= cal.startOfDay(for: now) else { return nil }
        let todayString = DataStore.dateString(from: now)
        // Reste au début de la journée : le quota du jour ne bouge pas pendant
        // qu'on écrit ; le recalcul se fait le lendemain sur le reste réel.
        let remaining = max(0, chapter.goal - chapter.previousTotal(before: todayString))
        let windowStart = pacingWindowStart(for: chapter, now: now)
        return PacingEngine.plan(
            profile: profile ?? chapter.pacing?.profile ?? .steady,
            windowStart: windowStart,
            deadline: deadline,
            today: now,
            remaining: remaining,
            countDeadlineDay: data.writingSchedule?.countDeadlineDay ?? true,
            calendar: cal,
            isWorkingDay: { self.isWorkingDay($0, for: chapter) },
            written: { chapter.increment(for: $0) }
        )
    }

    /// Début de la fenêtre : date enregistrée au choix du profil, sinon
    /// première saisie du chapitre, sinon aujourd'hui.
    func pacingWindowStart(for chapter: Chapter, now: Date = Date()) -> Date {
        if let s = chapter.pacing?.startDate, let d = DataStore.parseDate(s) { return d }
        if let first = chapter.entries.map(\.date).min(), let d = DataStore.parseDate(first) { return d }
        return now
    }

    /// Quota du jour selon le profil choisi. Nil si le chapitre n'a pas de profil :
    /// les calculs d'avant la 5.12 s'appliquent alors.
    func pacedDailyQuota(for chapter: Chapter, now: Date = Date()) -> Int? {
        guard chapter.pacing?.profile != nil else { return nil }
        return pacingPlan(for: chapter, now: now)?.todayQuota
    }

    func updatePacing(chapterId: UUID, in projectId: UUID, _ change: (inout ChapterPacing) -> Void) {
        guard let pi = data.projects.firstIndex(where: { $0.id == projectId }),
              let ci = data.projects[pi].chapters.firstIndex(where: { $0.id == chapterId }) else { return }
        var pacing = data.projects[pi].chapters[ci].pacing ?? ChapterPacing()
        change(&pacing)
        if pacing.profile != nil, pacing.startDate == nil {
            let chapter = data.projects[pi].chapters[ci]
            pacing.startDate = chapter.entries.map(\.date).min() ?? DataStore.today
        }
        if let days = pacing.workWeekdays, days.isEmpty { pacing.workWeekdays = nil }
        data.projects[pi].chapters[ci].pacing = (pacing == ChapterPacing()) ? nil : pacing
        dataVersion += 1
        save()
    }

    // MARK: Journées sans écriture (archives, séminaire, repos)

    /// Nature d'une journée sans écriture ; un jour de repos d'avant la 5.12 est « Repos ».
    func dayOffKind(for date: String) -> DayOffKind? {
        guard data.restDays.contains(date) else { return nil }
        return data.dayOffKinds?[date] ?? .rest
    }

    /// Marque (`kind` non nil) ou retire une journée sans écriture.
    func setDayOff(_ date: String, kind: DayOffKind?) {
        var kinds = data.dayOffKinds ?? [:]
        if let kind {
            if !data.restDays.contains(date) { data.restDays.append(date) }
            kinds[date] = kind
        } else {
            data.restDays.removeAll { $0 == date }
            kinds[date] = nil
        }
        data.dayOffKinds = kinds.isEmpty ? nil : kinds
        dataVersion += 1
        save()
    }

    /// Bouton 1 clic : même nature → retire ; sinon marque avec cette nature.
    func toggleDayOff(_ date: String, kind: DayOffKind) {
        setDayOff(date, kind: dayOffKind(for: date) == kind ? nil : kind)
    }

    var daysOffSorted: [(date: String, kind: DayOffKind)] {
        data.restDays.sorted().map { ($0, dayOffKind(for: $0) ?? .rest) }
    }

    /// Jour sans écriture prévu, où rien n'a été écrit : neutre pour la série
    /// et exclu des moyennes de vitesse.
    func isUnwrittenDayOff(_ date: String) -> Bool {
        data.restDays.contains(date) && (dailyTotals()[date] ?? 0) == 0
    }

    // MARK: Pages de thèse

    static let defaultCharsPerPage = 1_500

    /// « 12,4 » ; `digits` = chiffres après la virgule.
    static func pagesNumber(_ chars: Int, charsPerPage: Int, digits: Int = 1) -> String {
        let value = pages(chars: chars, charsPerPage: charsPerPage)
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = max(0, digits)
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// « 12,4 p. »
    static func formatPages(_ chars: Int, charsPerPage: Int, digits: Int = 1) -> String {
        pagesNumber(chars, charsPerPage: charsPerPage, digits: digits) + " p."
    }

    /// Nil quand l'affichage en pages est désactivé.
    func formatPages(_ chars: Int, digits: Int = 1) -> String? {
        guard let cpp = charsPerPage else { return nil }
        return DataStore.formatPages(chars, charsPerPage: cpp, digits: digits)
    }

    func pagesNumber(_ chars: Int, digits: Int = 1) -> String? {
        guard let cpp = charsPerPage else { return nil }
        return DataStore.pagesNumber(chars, charsPerPage: cpp, digits: digits)
    }

    /// Texte déjà écrit dans les chapitres comptés dans la thèse.
    var thesisWrittenChars: Int {
        data.projects.flatMap(\.chapters).reduce(0) { sum, ch in
            guard ch.countsInThesisTotal else { return sum }
            return sum + (ch.entries.max(by: { $0.date < $1.date })?.totalCount ?? 0)
        }
    }

    /// « calibrage 1 500 car./p »
    var pageCalibrationLabel: String? {
        guard let cpp = charsPerPage else { return nil }
        return "calibrage \(DataStore.formatNumber(cpp)) car./p"
    }
}
