import SwiftUI

// MARK: - #22 · Timeline du jour
// Affiche les sessions Pomodoro et entrées d'écriture du jour en ordre chronologique.

struct TodayTimelineView: View {
    @ObservedObject var store: DataStore
    @EnvironmentObject private var pomodoroController: PomodoroAppController

    @State private var expanded = false

    private var events: [TimelineEvent] { buildEvents() }
    private var visibleEvents: [TimelineEvent] {
        expanded || events.count <= 5 ? events : Array(events.prefix(5))
    }

    @ViewBuilder
    var body: some View {
        if !events.isEmpty {
            VStack(spacing: 10) {
                SectionHeader("Timeline du jour")
                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(visibleEvents.enumerated()), id: \.offset) { idx, event in
                            timelineRow(event, isLast: idx == visibleEvents.count - 1 && (expanded || events.count <= 5))
                        }

                        if events.count > 5 && !expanded {
                            Button {
                                withAppAnimation(Motion.panel) { expanded = true }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: AppLook.fs(10), weight: .semibold))
                                    Text("Voir \(events.count - 5) de plus")
                                        .font(.system(size: AppLook.fs(11), weight: .medium))
                                }
                                .foregroundColor(.labelMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 8)
                            }
                            .buttonStyle(.pressable)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row

    private func timelineRow(_ event: TimelineEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline spine
            VStack(spacing: 0) {
                Circle()
                    .fill(event.dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Color.cardBorder.opacity(0.5))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 2)
                }
            }
            .frame(width: 8)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: event.icon)
                        .font(.system(size: AppLook.fs(10)))
                        .foregroundColor(event.dotColor)
                    Text(event.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    if let timeLabel = event.timeLabel {
                        Text(timeLabel)
                            .font(.system(size: AppLook.fs(10), weight: .medium, design: .monospaced))
                            .foregroundColor(.labelMuted)
                    }
                }
                if let subtitle = event.subtitle {
                    Text(subtitle)
                        .font(.system(size: AppLook.fs(11)))
                        .foregroundColor(.labelMuted)
                }
            }
            .padding(.bottom, isLast ? 0 : 10)
        }
    }

    // MARK: - Event model

    private struct TimelineEvent {
        let icon: String
        let title: String
        let subtitle: String?
        let timeLabel: String?
        let dotColor: Color
        let sortKey: Double  // hour as Double for ordering, -1 = unknown (append last)
    }

    // MARK: - Build events

    private func buildEvents() -> [TimelineEvent] {
        let today = DataStore.today
        var events: [TimelineEvent] = []

        // — Writing entries —
        for project in store.data.projects {
            for chapter in project.chapters {
                if let entry = chapter.entryForDate(today), entry.totalCount > 0 {
                    let inc = chapter.increment(for: today)
                    guard inc > 0 else { continue }
                    let hour = entry.savedAtHour
                    let timeLabel = hour.map { String(format: "%02d:??", $0) }
                    let sortKey = hour.map { Double($0) } ?? 99.0
                    events.append(TimelineEvent(
                        icon: "text.cursor",
                        title: "\(store.formatCountShort(inc)) car.",
                        subtitle: chapter.name == project.name ? chapter.name : "\(project.name) · \(chapter.name)",
                        timeLabel: timeLabel,
                        dotColor: .accent,
                        sortKey: sortKey
                    ))
                }
            }
        }

        // — Pomodoro sessions —
        let cal = Calendar.current
        let todaySessions = pomodoroController.data.sessions.filter {
            cal.isDateInToday($0.startedAt) && $0.kind == .focus
        }
        let timeFmt: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f
        }()
        for session in todaySessions {
            let mins = Int(session.duration / 60)
            let completed = session.completionState == .completed
            let label = completed ? "\(mins) min" : "\(mins) min (interrompue)"
            let hour = cal.component(.hour, from: session.startedAt)
            let minute = cal.component(.minute, from: session.startedAt)
            let sortKey = Double(hour) + Double(minute) / 60.0
            events.append(TimelineEvent(
                icon: "timer",
                title: "Session focus",
                subtitle: label,
                timeLabel: timeFmt.string(from: session.startedAt),
                dotColor: completed ? .accentWarm : .labelMuted,
                sortKey: sortKey
            ))
        }

        // Sort by time; unknown times go to front (they have no precise time)
        return events.sorted { a, b in
            if a.sortKey == 99.0 && b.sortKey == 99.0 { return false }
            if a.sortKey == 99.0 { return true }
            if b.sortKey == 99.0 { return false }
            return a.sortKey < b.sortKey
        }
    }
}
