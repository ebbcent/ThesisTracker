import Foundation

// MARK: - Rythme d'écriture par chapitre (5.12)
//
// Un profil donne à chaque jour de la fenêtre du chapitre (du début à
// l'échéance) un poids selon sa position t ∈ [0, 1]. Le reste à écrire est
// réparti sur les jours ouvrés restants au prorata de ces poids :
// quota(jour) = reste × w(jour) / Σ w(jours restants). Le calcul repart chaque
// jour du reste réel : écrire plus ou moins un jour change les quotas suivants,
// sans arriéré cumulé.

enum PacingProfile: String, Codable, CaseIterable, Identifiable {
    case mountain
    case rampUp
    case steady
    case sprint

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mountain: return "Montagne"
        case .rampUp:   return "Montée"
        case .steady:   return "Linéaire"
        case .sprint:   return "Sprint"
        }
    }

    var symbol: String {
        switch self {
        case .mountain: return "mountain.2.fill"
        case .rampUp:   return "chart.line.uptrend.xyaxis"
        case .steady:   return "ruler"
        case .sprint:   return "bolt.fill"
        }
    }

    var summary: String {
        switch self {
        case .mountain: return "Pic d'effort aux deux tiers, puis décrue pour la relecture, les notes et l'appareil critique."
        case .rampUp:   return "Démarrage doux pendant le cadrage bibliographique, puis montée continue jusqu'à l'échéance."
        case .steady:   return "La même quantité chaque jour ouvré."
        case .sprint:   return "Charge maximale dès les premiers jours, puis allègement."
        }
    }

    /// Position du pic du profil Montagne.
    static let mountainPeak = 0.65

    /// Poids d'un jour situé en `t` (0 = début de la fenêtre, 1 = échéance).
    /// Toujours strictement positif, pour qu'un jour ouvré ait un quota.
    func weight(at t: Double) -> Double {
        let t = min(1, max(0, t))
        switch self {
        case .steady:
            return 1
        case .rampUp:
            return 0.25 + 1.5 * t
        case .sprint:
            return 0.2 + exp(-3 * t)
        case .mountain:
            let peak = PacingProfile.mountainPeak
            if t <= peak {
                return 0.3 + 0.7 * (t / peak)
            }
            return 1 - 0.75 * ((t - peak) / (1 - peak))
        }
    }
}

/// Réglages de rythme d'un chapitre. Tous les champs sont optionnels :
/// absents, le chapitre garde le calcul linéaire d'avant la 5.12.
struct ChapterPacing: Codable, Equatable {
    var profile: PacingProfile? = nil
    var startDate: String? = nil      // "yyyy-MM-dd", début de la fenêtre du profil
    var workWeekdays: [Int]? = nil    // 1 = dim … 7 = sam ; nil ou vide = calendrier général

    init(profile: PacingProfile? = nil, startDate: String? = nil, workWeekdays: [Int]? = nil) {
        self.profile = profile
        self.startDate = startDate
        self.workWeekdays = workWeekdays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        profile      = try? c.decodeIfPresent(PacingProfile.self, forKey: .profile)
        startDate    = try? c.decodeIfPresent(String.self, forKey: .startDate)
        workWeekdays = (try? c.decodeIfPresent(LossyArray<Int>.self, forKey: .workWeekdays))?.elements
    }
}

/// Nature d'une journée sans écriture. Le jour reste dans `AppData.restDays`
/// (lu par toutes les versions) ; la nature est rangée à part.
enum DayOffKind: String, Codable, CaseIterable, Identifiable {
    case archives
    case seminar
    case rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .archives: return "Archives"
        case .seminar:  return "Séminaire"
        case .rest:     return "Repos"
        }
    }

    var symbol: String {
        switch self {
        case .archives: return "archivebox.fill"
        case .seminar:  return "person.3.fill"
        case .rest:     return "moon.zzz.fill"
        }
    }
}

// MARK: - Calcul pur (testable sans DataStore)

struct PacingDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let dateString: String
    let t: Double            // position dans la fenêtre du chapitre
    let isWorkingDay: Bool   // jour ouvré et pas une journée sans écriture
    let isPast: Bool
    let isToday: Bool
    let quota: Int           // 0 pour un jour passé ou non ouvré
    let written: Int         // texte ajouté ce jour-là (jours passés et aujourd'hui)
}

struct PacingPlan: Equatable {
    let profile: PacingProfile
    let days: [PacingDay]
    let remaining: Int        // reste à écrire au début de la journée
    let todayQuota: Int
    let workingDaysLeft: Int  // aujourd'hui compris

    /// Quota du profil pour un jour situé en `t`, à l'échelle des quotas actuels
    /// (sert à tracer la courbe continue, y compris sur les jours passés).
    func scaledWeight(at t: Double) -> Double {
        let futureWeights = days.filter { !$0.isPast && $0.isWorkingDay }.map { profile.weight(at: $0.t) }
        let total = futureWeights.reduce(0, +)
        guard total > 0 else { return 0 }
        return Double(remaining) * profile.weight(at: t) / total
    }
}

enum PacingEngine {

    /// Répartit `remaining` selon `weights`. Les arrondis sont reportés sur les
    /// jours suivants : la somme vaut exactement `remaining`.
    static func distribute(remaining: Int, weights: [Double]) -> [Int] {
        let total = weights.reduce(0, +)
        guard remaining > 0, total > 0 else { return weights.map { _ in 0 } }
        var result: [Int] = []
        var assigned = 0
        var cumulative = 0.0
        for w in weights {
            cumulative += w
            let target = Int((Double(remaining) * cumulative / total).rounded())
            result.append(max(0, target - assigned))
            assigned = max(assigned, target)
        }
        return result
    }

    /// Plan d'un chapitre entre `windowStart` et `deadline`.
    /// - `remaining` : reste à écrire au début d'aujourd'hui.
    /// - `isWorkingDay` : jour ouvré du chapitre, journées sans écriture exclues.
    /// - `written` : texte ajouté un jour donné.
    /// - `countDeadlineDay` : le jour de l'échéance reçoit un quota.
    static func plan(profile: PacingProfile,
                     windowStart: Date,
                     deadline: Date,
                     today: Date,
                     remaining: Int,
                     countDeadlineDay: Bool = true,
                     calendar: Calendar,
                     isWorkingDay: (Date) -> Bool,
                     written: (String) -> Int = { _ in 0 }) -> PacingPlan {
        let start = calendar.startOfDay(for: min(windowStart, today))
        let end = calendar.startOfDay(for: deadline)
        let todayStart = calendar.startOfDay(for: today)
        let span = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)

        struct Raw { let date: Date; let string: String; let t: Double; let working: Bool }
        var raws: [Raw] = []
        var day = start
        while day <= end {
            let offset = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            let isDeadline = day == end
            let working = isWorkingDay(day) && (countDeadlineDay || !isDeadline)
            raws.append(Raw(date: day, string: dateString(day, calendar: calendar),
                            t: Double(offset) / Double(span), working: working))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let future = raws.filter { $0.date >= todayStart && $0.working }
        let quotas = distribute(remaining: max(0, remaining), weights: future.map { profile.weight(at: $0.t) })
        var quotaByDate: [Date: Int] = [:]
        for (raw, quota) in zip(future, quotas) { quotaByDate[raw.date] = quota }

        let days = raws.map { raw in
            PacingDay(date: raw.date, dateString: raw.string, t: raw.t,
                      isWorkingDay: raw.working,
                      isPast: raw.date < todayStart,
                      isToday: raw.date == todayStart,
                      quota: quotaByDate[raw.date] ?? 0,
                      written: raw.date <= todayStart ? written(raw.string) : 0)
        }
        return PacingPlan(profile: profile, days: days, remaining: max(0, remaining),
                          todayQuota: quotaByDate[todayStart] ?? 0,
                          workingDaysLeft: future.count)
    }

    private static func dateString(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
