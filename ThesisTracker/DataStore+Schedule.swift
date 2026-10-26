import Foundation

// MARK: - Calendrier d'écriture, quotas et série selon le calendrier (5.9)

extension DataStore {

    /// Calendrier actif : au moins un jour de la semaine coché.
    var usesWritingCalendar: Bool {
        !(data.writingSchedule?.workWeekdays ?? []).isEmpty
    }

    var usesScheduledStreak: Bool {
        data.writingSchedule?.streakRule == .scheduled
    }

    func updateWritingSchedule(_ change: (inout WritingSchedule) -> Void) {
        var schedule = data.writingSchedule ?? WritingSchedule()
        change(&schedule)
        data.writingSchedule = schedule
        dataVersion += 1
        save()
    }

    // MARK: Jours prévus

    /// Jour d'écriture prévu : jour de semaine coché (tous si aucun) et pas un jour de repos.
    func isPlannedWritingDay(_ date: Date) -> Bool {
        isPlannedWritingDay(date, dateString: DataStore.dateString(from: date))
    }

    private func isPlannedWritingDay(_ date: Date, dateString: String) -> Bool {
        if data.restDays.contains(dateString) { return false }
        guard let days = data.writingSchedule?.workWeekdays, !days.isEmpty else { return true }
        return days.contains(DataStore.gregorianCal.component(.weekday, from: date))
    }

    /// Aujourd'hui n'est pas un jour d'écriture prévu (calendrier actif seulement).
    var isTodayPlannedOff: Bool {
        usesWritingCalendar && !isPlannedWritingDay(Date())
    }

    var isYesterdayPlannedOff: Bool {
        guard usesWritingCalendar,
              let yesterday = DataStore.gregorianCal.date(byAdding: .day, value: -1, to: Date()) else { return false }
        return !isPlannedWritingDay(yesterday)
    }

    /// Nombre de jours d'écriture prévus entre deux dates, bornes incluses.
    func plannedWritingDays(from start: Date, through end: Date) -> Int {
        let cal = DataStore.gregorianCal
        var day = cal.startOfDay(for: start)
        let last = cal.startOfDay(for: end)
        var count = 0
        while day <= last {
            if isPlannedWritingDay(day) { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    /// Jours d'écriture restants avant une échéance, aujourd'hui compris.
    /// Le jour de l'échéance compte, sauf si l'option est décochée.
    func writingDaysRemaining(until deadline: Date, from now: Date = Date()) -> Int {
        let cal = DataStore.gregorianCal
        let deadlineDay = cal.startOfDay(for: deadline)
        let countDeadlineDay = data.writingSchedule?.countDeadlineDay ?? true
        let lastDay: Date? = countDeadlineDay ? deadlineDay : cal.date(byAdding: .day, value: -1, to: deadlineDay)
        guard let last = lastDay, cal.startOfDay(for: now) <= last else { return 0 }
        return plannedWritingDays(from: now, through: last)
    }

    /// Quota par jour d'écriture pour écrire `remaining` avant `deadline`.
    func scheduledDailyQuota(remaining: Int, deadline: Date, from now: Date = Date()) -> Int {
        guard remaining > 0 else { return 0 }
        let days = max(1, writingDaysRemaining(until: deadline, from: now))
        return Int(ceil(Double(remaining) / Double(days)))
    }

    /// Objectif hebdomadaire restant réparti sur les jours d'écriture restants
    /// de la semaine ISO, aujourd'hui compris.
    func scheduledAdaptedDailyGoal(now: Date = Date()) -> Int {
        var cal = DataStore.gregorianCal
        cal.firstWeekday = 2
        guard let interval = cal.dateInterval(of: .weekOfYear, for: now),
              let sunday = cal.date(byAdding: .day, value: -1, to: interval.end) else { return data.dailyGoal }
        let remaining = max(0, data.weeklyGoal - weeklyProgress)
        guard remaining > 0 else { return 0 }
        let days = max(1, plannedWritingDays(from: now, through: sunday))
        return Int(ceil(Double(remaining) / Double(days)))
    }

    /// Aperçu pour une échéance : jours restants et quota par jour. Avec le
    /// calendrier, jours d'écriture ; sans, jours jusqu'à la veille de l'échéance
    /// (même calcul que `deadlineDailyGoal`).
    func quotaPreview(remaining: Int, deadline: Date, from now: Date = Date()) -> (days: Int, perDay: Int) {
        let days: Int
        if usesWritingCalendar {
            days = writingDaysRemaining(until: deadline, from: now)
        } else {
            let cal = DataStore.gregorianCal
            days = max(0, cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: deadline)).day ?? 0)
        }
        guard remaining > 0 else { return (days, 0) }
        return (days, Int(ceil(Double(remaining) / Double(max(1, days)))))
    }

    // MARK: Série selon le calendrier

    /// Jour qui ne casse ni n'allonge la série : non prévu, repos ou en pause.
    func isNeutralStreakDay(_ date: Date) -> Bool {
        isNeutralStreakDay(date, dateString: DataStore.dateString(from: date))
    }

    private func isNeutralStreakDay(_ date: Date, dateString: String) -> Bool {
        if !isPlannedWritingDay(date, dateString: dateString) { return true }
        return (data.writingSchedule?.streakPauses ?? []).contains { $0.contains(dateString) }
    }

    var isStreakPaused: Bool {
        (data.writingSchedule?.streakPauses ?? []).contains { $0.end == nil }
    }

    func setStreakPaused(_ paused: Bool) {
        let today = DataStore.today
        updateWritingSchedule { schedule in
            var pauses = schedule.streakPauses ?? []
            if paused {
                guard !pauses.contains(where: { $0.end == nil }) else { return }
                pauses.append(StreakPause(start: today))
            } else if let index = pauses.firstIndex(where: { $0.end == nil }) {
                pauses[index].end = today
            }
            schedule.streakPauses = pauses
        }
    }

    /// Série en cours et record, en parcourant les jours depuis le premier jour écrit.
    /// Jour écrit : +1. Jour neutre ou journée en cours : rien. Jour prévu manqué :
    /// la série repart à zéro, sauf avec le jour de grâce si le précédent jour
    /// prévu a été tenu (deux manqués d'affilée la cassent).
    func scheduledStreaks(today now: Date = Date()) -> (current: Int, longest: Int) {
        let active = activeWritingDays
        guard let first = active.min(), let start = DataStore.parseDate(first) else { return (0, 0) }
        let cal = DataStore.gregorianCal
        let grace = data.writingSchedule?.graceDay ?? false
        let todayStart = cal.startOfDay(for: now)
        var day = cal.startOfDay(for: start)
        var current = 0, longest = 0
        var pendingMiss = false
        while day <= todayStart {
            let dateString = DataStore.dateString(from: day)
            if active.contains(dateString) {
                current += 1
                pendingMiss = false
                longest = max(longest, current)
            } else if day == todayStart || isNeutralStreakDay(day, dateString: dateString) {
                // journée pas finie, ou jour neutre
            } else if grace && !pendingMiss {
                pendingMiss = true
            } else {
                current = 0
                pendingMiss = false
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return (current, longest)
    }

    // MARK: Réglages venus des UserDefaults (un seul Mac) vers data.json

    /// Recopie une fois dans data.json les réglages qui n'existaient que sur ce
    /// Mac. Les UserDefaults restent écrits : un retour à la 5.8 les retrouve.
    func migrateLocalGoalSettingsIfNeeded(defaults: UserDefaults = .standard) {
        var schedule = data.writingSchedule ?? WritingSchedule()
        var changed = false
        if schedule.weekdayGoals == nil,
           let raw = defaults.data(forKey: "weekdayGoals"),
           let dict = try? DataStore.sharedDecoder.decode([String: Int].self, from: raw),
           !dict.isEmpty {
            schedule.weekdayGoals = dict
            changed = true
        }
        let localBuffer = defaults.integer(forKey: "deadlineBuffer")
        if schedule.deadlineBufferDays == nil, localBuffer > 0 {
            schedule.deadlineBufferDays = localBuffer
            changed = true
        }
        guard changed else { return }
        data.writingSchedule = schedule
        dataVersion += 1
        save()
    }
}
