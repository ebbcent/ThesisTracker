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
        BadgeDefinition(threshold: 3,   name: "Étincelle",    icon: "flame",        color: .accent,                                                           description: "3 jours consécutifs"),
        BadgeDefinition(threshold: 7,   name: "Régulier",     icon: "flame.fill",   color: Color(red: 0.961, green: 0.620, blue: 0.043),                      description: "7 jours consécutifs"),
        BadgeDefinition(threshold: 14,  name: "Persévérant",  icon: "star.fill",    color: Color(red: 0.961, green: 0.455, blue: 0.114),                      description: "14 jours consécutifs"),
        BadgeDefinition(threshold: 30,  name: "Acharné",      icon: "bolt.fill",    color: Color(red: 0.929, green: 0.329, blue: 0.329),                      description: "30 jours consécutifs"),
        BadgeDefinition(threshold: 60,  name: "Légende",      icon: "crown.fill",   color: Color(red: 0.749, green: 0.318, blue: 0.918),                      description: "60 jours consécutifs"),
        BadgeDefinition(threshold: 100, name: "Immortel",     icon: "trophy.fill",  color: Color(red: 1.0, green: 0.55, blue: 0.1),                           description: "100 jours consécutifs"),
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
                        Button { withAnimation { showSidebar = true } } label: {
                            Image(systemName: "sidebar.left").font(.system(size: 14))
                                .foregroundColor(.labelMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accomplissements")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Progression et badges")
                            .font(.system(size: 12)).foregroundColor(.labelMuted)
                    }
                    Spacer()
                }

                // Key stats row
                HStack(spacing: 12) {
                    AchievementStatCard(
                        icon: "flame.fill", iconColor: Color(red: 0.961, green: 0.455, blue: 0.114),
                        value: "\(store.currentStreak)", unit: "jours", label: "Streak actuel"
                    )
                    AchievementStatCard(
                        icon: "trophy.fill", iconColor: Color(red: 1.0, green: 0.84, blue: 0.0),
                        value: "\(store.longestStreak)", unit: "jours", label: "Meilleur streak"
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
                    sectionHeader("BADGES DE STREAK", icon: "flame.fill", color: Color(red: 0.961, green: 0.455, blue: 0.114))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 14)], spacing: 14) {
                        ForEach(BadgeDefinition.all, id: \.threshold) { badge in
                            BadgeCard(badge: badge, isUnlocked: unlockedBadges.contains(badge.threshold))
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
        .background(Color.appBg)
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
        let totalChapters = store.data.projects.flatMap { $0.chapters }.count
        let completedChapters = store.data.projects.flatMap { $0.chapters }.filter { $0.isCompleted }.count
        let totalProjects = store.data.projects.count

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
            id: "marathon", icon: "figure.run", color: Color(red: 0.929, green: 0.329, blue: 0.329),
            name: "Marathon", description: "Écrire 10\u{202F}000 \(store.data.useWordCount ? "mots" : "car.") en une journée",
            isUnlocked: hasWrittenInOneDay(threshold: 10_000)
        ))
        list.append(GeneralAchievement(
            id: "centurion", icon: "100.circle.fill", color: Color(red: 0.749, green: 0.318, blue: 0.918),
            name: "Centurion", description: "100 jours d'écriture au total",
            isUnlocked: totalDaysWritten >= 100
        ))
        return list
    }

    private func hasWrittenInOneDay(threshold: Int) -> Bool {
        let totals = store.dailyTotals()
        return totals.values.contains { $0 >= threshold }
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
                            .font(.system(size: 11)).foregroundColor(.labelMuted)
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
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundColor(color)
            Text(text).font(.system(size: 10, weight: .bold)).foregroundColor(.labelMuted).kerning(1.0)
        }
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
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
            if isUnlocked {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
                    Text("Débloqué").font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(badge.color)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
                RoundedRectangle(cornerRadius: 10)
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
                    .font(.system(size: 10)).foregroundColor(.labelMuted).lineLimit(1)
            }
            Spacer()
            if achievement.isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14)).foregroundColor(achievement.color)
            }
        }
        .padding(12)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
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
                RoundedRectangle(cornerRadius: 10)
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
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
                    .lineLimit(1)
                Text(weekLabel)
                    .font(.system(size: 9))
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentGreen.opacity(0.25), lineWidth: 1)
        )
    }

    private var kindColor: Color {
        switch challenge.kind {
        case .words:       return .accent
        case .daysWritten: return Color(red: 0.580, green: 0.400, blue: 0.900)
        case .streak:      return Color(red: 0.961, green: 0.455, blue: 0.114)
        case .sessions:    return Color(red: 0.220, green: 0.600, blue: 0.900)
        }
    }

    private var kindLabel: String {
        switch challenge.kind {
        case .words:       return "Volume d'écriture"
        case .daysWritten: return "Régularité"
        case .streak:      return "Streak"
        case .sessions:    return "Sessions Pomodoro"
        }
    }

    private var challengeDescription: String {
        let unit = store.data.useWordCount ? "mots" : "car."
        switch challenge.kind {
        case .words:       return "\(challenge.target.formatted()) \(unit)"
        case .daysWritten: return "\(challenge.target) jour\(challenge.target > 1 ? "s" : "") écrits"
        case .streak:      return "Streak de \(challenge.target) jours"
        case .sessions:    return "\(challenge.target) sessions"
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
                    Text(value).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(unit).font(.system(size: 11)).foregroundColor(.labelMuted)
                }
                Text(label).font(.system(size: 10)).foregroundColor(.labelMuted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cardBorder, lineWidth: 1))
    }
}

