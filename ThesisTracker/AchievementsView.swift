import SwiftUI

// MARK: - Badge definition

struct BadgeDefinition {
    let threshold: Int
    let name: String
    let icon: String
    let color: Color
    let description: String
}

extension BadgeDefinition {
    static let all: [BadgeDefinition] = [
        BadgeDefinition(threshold: 3,   name: "Étincelle",    icon: "flame",         color: .accent,                                                           description: "3 jours consécutifs"),
        BadgeDefinition(threshold: 7,   name: "Régulier",     icon: "flame.fill",    color: Color.semAmber,                      description: "7 jours consécutifs"),
        BadgeDefinition(threshold: 14,  name: "Persévérant",  icon: "star.fill",     color: Color.semOrange,                      description: "14 jours consécutifs"),
        BadgeDefinition(threshold: 30,  name: "Acharné",      icon: "bolt.fill",     color: Color.semRed,                      description: "30 jours consécutifs"),
        BadgeDefinition(threshold: 60,  name: "Légende",      icon: "crown.fill",    color: Color.semViolet,                      description: "60 jours consécutifs"),
        BadgeDefinition(threshold: 100, name: "Immortel",     icon: "trophy.fill",   color: Color.semOrange,                           description: "100 jours consécutifs"),
        BadgeDefinition(threshold: 200, name: "Titan",        icon: "shield.fill",   color: Color.semPurple,                      description: "200 jours consécutifs"),
        BadgeDefinition(threshold: 365, name: "Année pleine", icon: "rosette",       color: Color.semPink,                      description: "365 jours consécutifs"),
    ]
}

// MARK: - Achievements View

struct AchievementsView: View {
    @ObservedObject var store: DataStore
    @Binding var showSidebar: Bool

    private var unlockedBadges: Set<Int> { Set(store.unlockedBadgeThresholds) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Top header
                HStack {
                    if !showSidebar {
                        Button { withAppAnimation { showSidebar = true } } label: {
                            Image(systemName: "sidebar.left").font(.system(size: 14))
                                .foregroundColor(.labelMuted)
                        }
                        .buttonStyle(.pressable)
                        .help("Afficher la barre latérale")
                        .accessibilityLabel("Afficher la barre latérale")
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accomplissements")
                            .font(.system(size: 22, weight: .bold, design: AppLook.fontDesign))
                        Text("Progression et badges")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                    }
                    Spacer()
                }

                // Key stats row
                HStack(spacing: 12) {
                    AchievementStatCard(
                        icon: "flame.fill", iconColor: Color.semOrange,
                        value: "\(store.currentStreak)", unit: "jours", label: "Série actuelle"
                    )
                    AchievementStatCard(
                        icon: "trophy.fill", iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                        value: "\(store.longestStreak)", unit: "jours", label: "Meilleure série"
                    )
                    AchievementStatCard(
                        icon: "pencil.and.list.clipboard", iconColor: .accent,
                        value: "\(totalDaysWritten)", unit: "jours", label: "Total jours écrits"
                    )
                    AchievementStatCard(
                        icon: "text.word.spacing", iconColor: .accentGreen,
                        value: store.formatCountShort(totalWordsWritten), unit: store.data.useWordCount ? "mots" : "car.", label: "Total écrit"
                    )
                }

                // Streak progress toward next badge
                if let next = nextBadge {
                    nextBadgeProgress(badge: next)
                }

                // Badge grid
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("BADGES DE STREAK", icon: "flame.fill", color: Color.semOrange)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                        ForEach(BadgeDefinition.all, id: \.threshold) { badge in
                            BadgeCard(badge: badge, isUnlocked: unlockedBadges.contains(badge.threshold))
                        }
                    }
                }

                // Volume badges (V5)
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("BADGES DE VOLUME", icon: "text.word.spacing", color: Color.semViolet)
                    let totalWritten = store.totalCharsEverWritten
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                        ForEach(VolumeBadgeDefinition.all, id: \.threshold) { badge in
                            VolumeBadgeCard(
                                badge: badge,
                                totalWritten: totalWritten,
                                isUnlocked: totalWritten >= badge.threshold
                            )
                        }
                    }
                    // Prochain badge de volume
                    if let next = VolumeBadgeDefinition.all.first(where: { totalWritten < $0.threshold }) {
                        let progress = min(1.0, Double(totalWritten) / Double(next.threshold))
                        let remaining = next.threshold - totalWritten
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    ZStack {
                                        Circle().fill(next.color.opacity(0.15)).frame(width: 36, height: 36)
                                        Image(systemName: next.icon).font(.system(size: 15)).foregroundColor(next.color)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Prochain badge volume : \(next.name)")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("Plus que \(store.formatCountShort(remaining)) à écrire — \(next.description)")
                                            .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                                    }
                                    Spacer()
                                    Text("\(Int(progress * 100))%")
                                        .font(.system(size: 14, weight: .bold)).foregroundColor(next.color)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3).fill(next.color.opacity(0.12)).frame(height: 6)
                                        RoundedRectangle(cornerRadius: 3).fill(next.color)
                                            .frame(width: geo.size.width * progress, height: 6)
                                            .appAnimation(Motion.progress, value: progress)
                                    }
                                }.frame(height: 6)
                            }
                        }
                    }
                }

                // Completed weekly challenges
                let completedChallenges = store.data.weeklyChallenges
                    .filter { $0.isCompleted }
                    .sorted { $0.weekKey > $1.weekKey }
                if !completedChallenges.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader("DÉFIS ACCOMPLIS", icon: "target", color: .accentGreen)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(completedChallenges) { challenge in
                                    CompletedChallengeCard(challenge: challenge, store: store)
                                        .frame(width: 210)
                                }
                            }
                        }
                    }
                }

                // General achievements
                VStack(alignment: .leading, spacing: 12) {
                    sectionHeader("ACCOMPLISSEMENTS", icon: "star.fill", color: .accentGold)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(generalAchievements) { achievement in
                                GeneralAchievementCard(achievement: achievement)
                                    .frame(width: 210)
                            }
                        }
                    }
                }

            }
            .padding(28)
        }
        .background(AppBackdrop())
    }

    // MARK: - Computed stats

    private var totalDaysWritten: Int {
        var days = Set<String>()
        for project in store.data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries where chapter.increment(for: entry.date) > 0 {
                    days.insert(entry.date)
                }
            }
        }
        return days.count
    }

    private var totalWordsWritten: Int {
        var total = 0
        for project in store.data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    total += max(0, chapter.increment(for: entry.date))
                }
            }
        }
        return total
    }

    private var nextBadge: BadgeDefinition? {
        BadgeDefinition.all.first { !unlockedBadges.contains($0.threshold) }
    }

    private var generalAchievements: [GeneralAchievement] {
        var list: [GeneralAchievement] = []
        let allChapters = store.data.projects.flatMap { $0.chapters }
        let totalChapters = allChapters.count
        let completedChapters = allChapters.filter { $0.isCompleted }.count
        let totalProjects = store.data.projects.count
        let chaptersWithDeadline = allChapters.filter { $0.deadline != nil }.count
        let unit = store.data.useWordCount ? "mots" : "car."

        list.append(GeneralAchievement(
            id: "first_word", icon: "pencil.tip", color: .accent,
            name: "Premier mot", description: "Commencer à écrire",
            isUnlocked: totalDaysWritten > 0
        ))
        list.append(GeneralAchievement(
            id: "first_project", icon: "books.vertical.fill", color: .accentWarm,
            name: "Premier projet", description: "Créer un projet",
            isUnlocked: totalProjects >= 1
        ))
        list.append(GeneralAchievement(
            id: "first_chapter_done", icon: "checkmark.seal.fill", color: .accentGreen,
            name: "Chapitre bouclé", description: "Terminer un chapitre",
            isUnlocked: completedChapters >= 1
        ))
        list.append(GeneralAchievement(
            id: "ten_chapters", icon: "list.number", color: .accent,
            name: "Prolifique", description: "10 chapitres créés",
            isUnlocked: totalChapters >= 10
        ))
        list.append(GeneralAchievement(
            id: "marathon", icon: "figure.run", color: Color.semRed,
            name: "Marathon", description: "Écrire 10\u{202F}000 \(unit) en une journée",
            isUnlocked: hasWrittenInOneDay(threshold: 10_000)
        ))
        list.append(GeneralAchievement(
            id: "centurion", icon: "crown.fill", color: Color.semViolet,
            name: "Centurion", description: "100 jours d'écriture au total",
            isUnlocked: totalDaysWritten >= 100
        ))

        // — Nouveaux accomplissements —

        list.append(GeneralAchievement(
            id: "early_bird", icon: "sunrise.fill", color: Color.semAmber,
            name: "Lève-tôt", description: "Écrire avant 8 h du matin",
            isUnlocked: hasEntrySavedAt(hourPredicate: { $0 < 8 })
        ))
        list.append(GeneralAchievement(
            id: "night_owl", icon: "moon.stars.fill", color: Color.semPurple,
            name: "Couche-tard", description: "Écrire après 23 h",
            isUnlocked: hasEntrySavedAt(hourPredicate: { $0 >= 23 })
        ))
        list.append(GeneralAchievement(
            id: "weekend_warrior", icon: "sun.horizon.fill", color: Color.semSky,
            name: "Week-end warrior", description: "Écrire 4 jours de week-end",
            isUnlocked: weekendDaysWritten >= 4
        ))
        list.append(GeneralAchievement(
            id: "sprinter", icon: "hare.fill", color: Color.semOrange,
            name: "Sprinter", description: "5\u{202F}000 \(unit) en une journée",
            isUnlocked: hasWrittenInOneDay(threshold: 5_000)
        ))
        list.append(GeneralAchievement(
            id: "versatile", icon: "rectangle.3.group.fill", color: Color.semSky,
            name: "Polyvalent", description: "Avancer 3 chapitres le même jour",
            isUnlocked: maxChaptersWrittenSameDay >= 3
        ))
        list.append(GeneralAchievement(
            id: "architect", icon: "ruler.fill", color: Color.semPurple,
            name: "Architecte", description: "10 chapitres avec échéance",
            isUnlocked: chaptersWithDeadline >= 10
        ))
        list.append(GeneralAchievement(
            id: "finisher", icon: "flag.checkered", color: .accentGreen,
            name: "Finisseur", description: "5 chapitres terminés",
            isUnlocked: completedChapters >= 5
        ))
        list.append(GeneralAchievement(
            id: "monthly_regular", icon: "calendar.badge.checkmark", color: Color.semViolet,
            name: "Mois régulier", description: "Écrire 20 jours dans un mois",
            isUnlocked: bestMonthDaysWritten >= 20
        ))
        list.append(GeneralAchievement(
            id: "year_productive", icon: "calendar.circle.fill", color: Color.semPink,
            name: "Année productive", description: "200 jours d'écriture au total",
            isUnlocked: totalDaysWritten >= 200
        ))
        list.append(GeneralAchievement(
            id: "project_completed", icon: "trophy.circle.fill", color: Color.semOrange,
            name: "Projet bouclé", description: "Terminer tous les chapitres d'un projet",
            isUnlocked: hasCompletedAllChaptersInAProject
        ))
        return list
    }

    private func hasWrittenInOneDay(threshold: Int) -> Bool {
        let totals = store.dailyTotals()
        return totals.values.contains { $0 >= threshold }
    }

    private func hasEntrySavedAt(hourPredicate: (Int) -> Bool) -> Bool {
        for project in store.data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries {
                    if let h = entry.savedAtHour, hourPredicate(h) { return true }
                }
            }
        }
        return false
    }

    /// Nombre total de jours de week-end (samedi/dimanche) durant lesquels l'utilisateur a écrit.
    private var weekendDaysWritten: Int {
        let cal = DataStore.gregorianCal
        var count = 0
        for (dateStr, val) in store.dailyTotals() where val > 0 {
            guard let date = DataStore.parseDate(dateStr) else { continue }
            let weekday = cal.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 { count += 1 } // 1 = dimanche, 7 = samedi
        }
        return count
    }

    /// Nombre maximum de chapitres distincts dans lesquels l'utilisateur a écrit le même jour.
    private var maxChaptersWrittenSameDay: Int {
        var perDay: [String: Set<UUID>] = [:]
        for project in store.data.projects {
            for chapter in project.chapters {
                for entry in chapter.entries where chapter.increment(for: entry.date) > 0 {
                    perDay[entry.date, default: []].insert(chapter.id)
                }
            }
        }
        return perDay.values.map { $0.count }.max() ?? 0
    }

    /// Meilleur mois calendaire en nombre de jours écrits.
    private var bestMonthDaysWritten: Int {
        var perMonth: [String: Int] = [:]
        for (dateStr, val) in store.dailyTotals() where val > 0 {
            let month = String(dateStr.prefix(7)) // "yyyy-MM"
            perMonth[month, default: 0] += 1
        }
        return perMonth.values.max() ?? 0
    }

    private var hasCompletedAllChaptersInAProject: Bool {
        store.data.projects.contains { project in
            !project.chapters.isEmpty && project.chapters.allSatisfy { $0.isCompleted }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func nextBadgeProgress(badge: BadgeDefinition) -> some View {
        let progress = min(1.0, Double(store.currentStreak) / Double(badge.threshold))
        let remaining = badge.threshold - store.currentStreak

        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(badge.color.opacity(0.15)).frame(width: 36, height: 36)
                        Image(systemName: badge.icon).font(.system(size: 16)).foregroundColor(badge.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prochain badge : \(badge.name)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Plus que \(remaining) jour\(remaining > 1 ? "s" : "") consécutif\(remaining > 1 ? "s" : "") — \(badge.description)")
                            .font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                    }
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(badge.color)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(badge.color.opacity(0.12)).frame(height: 6)
                        RoundedRectangle(cornerRadius: 3).fill(badge.color)
                            .frame(width: geo.size.width * progress, height: 6)
                            .appAnimation(Motion.progress, value: progress)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: AppLook.fs(10), weight: .bold)).foregroundColor(color)
            Text(text).font(.system(size: AppLook.fs(10), weight: .bold)).foregroundColor(.labelMuted).kerning(1.0)
        }
    }
}

// MARK: - Volume badge definition (V5)

struct VolumeBadgeDefinition {
    let threshold: Int
    let name: String
    let icon: String
    let color: Color
    let description: String

    static let all: [VolumeBadgeDefinition] = [
        VolumeBadgeDefinition(threshold:     10_000, name: "Première plume",  icon: "pencil.tip",                color: Color(red: 0.400, green: 0.750, blue: 0.500), description: "10 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:     50_000, name: "Scripteur",       icon: "pencil.and.list.clipboard", color: Color.semSky, description: "50 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:    100_000, name: "Centurion",       icon: "seal.fill",                 color: Color.semAmber, description: "100 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:    250_000, name: "Prolifique",      icon: "sparkles",                  color: Color.semRed, description: "250 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:    500_000, name: "Demi-million",    icon: "crown.fill",                color: Color.semViolet, description: "500 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:  1_000_000, name: "Millionnaire",    icon: "trophy.fill",               color: Color.semYellow, description: "1 000 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:  2_000_000, name: "Plume d'or",      icon: "medal.fill",                color: Color.semOrange, description: "2 000 000 caractères écrits"),
        VolumeBadgeDefinition(threshold:  5_000_000, name: "Mythique",        icon: "laurel.leading",            color: Color.semPurple, description: "5 000 000 caractères écrits"),
    ]
}

// MARK: - Volume badge card (V5)

private struct VolumeBadgeCard: View {
    let badge: VolumeBadgeDefinition
    let totalWritten: Int
    let isUnlocked: Bool

    var body: some View {
        let progress = min(1.0, Double(totalWritten) / Double(badge.threshold))
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? badge.color.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 56, height: 56)
                if isUnlocked {
                    Circle().stroke(badge.color.opacity(0.35), lineWidth: 2).frame(width: 56, height: 56)
                } else {
                    Circle()
                        .trim(from: 0, to: CGFloat(progress))
                        .stroke(badge.color.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 56, height: 56)
                }
                Image(systemName: isUnlocked ? badge.icon : "lock.fill")
                    .font(.system(size: isUnlocked ? 22 : 18))
                    .foregroundColor(isUnlocked ? badge.color : .labelMuted.opacity(0.35))
            }
            VStack(spacing: 3) {
                Text(badge.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isUnlocked ? .primary : .labelMuted)
                Text(badge.description)
                    .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
            }
            if isUnlocked {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: AppLook.fs(10)))
                    Text("Débloqué").font(.system(size: AppLook.fs(10), weight: .medium))
                }
                .foregroundColor(badge.color)
            } else {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: AppLook.fs(10), weight: .semibold))
                    .foregroundColor(.labelMuted)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(12, 18)))
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(12, 18))
                .stroke(isUnlocked ? badge.color.opacity(0.25) : Color.cardBorder, lineWidth: 1)
        )
        .opacity(isUnlocked ? 1 : 0.55)
        .grayscale(isUnlocked ? 0 : 0.5)
    }
}

// MARK: - Badge card

private struct BadgeCard: View {
    let badge: BadgeDefinition
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isUnlocked ? badge.color.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 56, height: 56)
                if isUnlocked {
                    Circle().stroke(badge.color.opacity(0.35), lineWidth: 2).frame(width: 56, height: 56)
                }
                Image(systemName: isUnlocked ? badge.icon : "lock.fill")
                    .font(.system(size: isUnlocked ? 24 : 18))
                    .foregroundColor(isUnlocked ? badge.color : .labelMuted.opacity(0.35))
            }
            VStack(spacing: 3) {
                Text(badge.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isUnlocked ? .primary : .labelMuted)
                Text(badge.description)
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
            }
            if isUnlocked {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: AppLook.fs(10)))
                    Text("Débloqué").font(.system(size: AppLook.fs(10), weight: .medium))
                }
                .foregroundColor(badge.color)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(12, 18)))
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(12, 18))
                .stroke(isUnlocked ? badge.color.opacity(0.25) : Color.cardBorder, lineWidth: 1)
        )
        .opacity(isUnlocked ? 1 : 0.55)
        .grayscale(isUnlocked ? 0 : 0.6)
    }
}

// MARK: - General achievement

struct GeneralAchievement: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let name: String
    let description: String
    let isUnlocked: Bool
}

private struct GeneralAchievementCard: View {
    let achievement: GeneralAchievement

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                    .fill(achievement.isUnlocked ? achievement.color.opacity(0.15) : Color.primary.opacity(0.05))
                    .frame(width: 40, height: 40)
                Image(systemName: achievement.isUnlocked ? achievement.icon : "lock.fill")
                    .font(.system(size: achievement.isUnlocked ? 18 : 14))
                    .foregroundColor(achievement.isUnlocked ? achievement.color : .labelMuted.opacity(0.35))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(achievement.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(achievement.isUnlocked ? .primary : .labelMuted)
                    .lineLimit(1)
                Text(achievement.description)
                    .font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted).lineLimit(1)
            }
            Spacer()
            if achievement.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14)).foregroundColor(achievement.color)
            }
        }
        .padding(12)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                .stroke(achievement.isUnlocked ? achievement.color.opacity(0.2) : Color.cardBorder, lineWidth: 1)
        )
        .opacity(achievement.isUnlocked ? 1 : 0.55)
        .grayscale(achievement.isUnlocked ? 0 : 0.5)
    }
}

// MARK: - Completed challenge card

private struct CompletedChallengeCard: View {
    let challenge: WeeklyChallenge
    let store: DataStore

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                    .fill(kindColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: challenge.kind.icon)
                    .font(.system(size: 18))
                    .foregroundColor(kindColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(challengeDescription)
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
                Text(weekLabel)
                    .font(.system(size: AppLook.fs(10)))
                    .foregroundColor(.labelMuted.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.accentGreen)
        }
        .padding(12)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
        .overlay(
            RoundedRectangle(cornerRadius: AppLook.r(10, 14))
                .stroke(Color.accentGreen.opacity(0.25), lineWidth: 1)
        )
    }

    private var kindColor: Color {
        switch challenge.kind {
        case .words:             return .accent
        case .daysWritten:       return Color.semViolet
        case .streak:            return Color.semOrange
        case .sessions:          return Color.semSky
        case .chapterCompletion: return .accentGreen
        case .chaptersAdvanced:  return Color.semSky
        }
    }

    private var kindLabel: String {
        switch challenge.kind {
        case .words:             return "Volume d'écriture"
        case .daysWritten:       return "Régularité"
        case .streak:            return "Série"
        case .sessions:          return "Sessions Pomodoro"
        case .chapterCompletion: return "Chapitres terminés"
        case .chaptersAdvanced:  return "Chapitres avancés"
        }
    }

    private var challengeDescription: String {
        let unit = store.data.useWordCount ? "mots" : "car."
        switch challenge.kind {
        case .words:             return "\(challenge.target.formatted()) \(unit)"
        case .daysWritten:       return "\(challenge.target) jour\(challenge.target > 1 ? "s" : "") écrits"
        case .streak:            return "Série de \(challenge.target) jours"
        case .sessions:          return "\(challenge.target) sessions"
        case .chapterCompletion: return "\(challenge.target) chapitre\(challenge.target > 1 ? "s" : "") terminé\(challenge.target > 1 ? "s" : "")"
        case .chaptersAdvanced:  return "\(challenge.target) chapitre\(challenge.target > 1 ? "s" : "") fait\(challenge.target > 1 ? "s" : "") avancer"
        }
    }

    private var weekLabel: String {
        // Parse "2026-W12" → "Semaine 12 · 2026"
        let parts = challenge.weekKey.split(separator: "-W")
        if parts.count == 2, let year = parts.first, let week = parts.last {
            return "Semaine \(week) · \(year)"
        }
        return challenge.weekKey
    }
}

// MARK: - Stat card

private struct AchievementStatCard: View {
    let icon: String
    let iconColor: Color
    let value: String
    let unit: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14)).foregroundColor(iconColor)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value).font(.system(size: 20, weight: .bold, design: AppLook.fontDesign))
                    Text(unit).font(.system(size: AppLook.fs(11))).foregroundColor(.labelMuted)
                }
                Text(label).font(.system(size: AppLook.fs(10))).foregroundColor(.labelMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: AppLook.r(10, 14)))
        .overlay(RoundedRectangle(cornerRadius: AppLook.r(10, 14)).stroke(Color.cardBorder, lineWidth: 1))
    }
}

