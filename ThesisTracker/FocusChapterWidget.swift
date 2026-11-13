import SwiftUI

// MARK: - Feature #12 + #13 : Chapitre en focus + temps restant estimé

struct FocusChapterWidget: View {
    @ObservedObject var store: DataStore
    @State private var animatedRatio: Double = 0

    private var project: Project? { store.activeProject }
    private var chapter: Chapter? { store.activeChapter }

    private var latest: Int {
        guard let c = chapter, let p = project else { return 0 }
        return store.latestTotal(for: c.id, in: p.id)
    }
    private var goal: Int { chapter?.goal ?? 0 }
    private var ratio: Double {
        guard goal > 0 else { return 0 }
        if chapter?.isCompleted == true { return 1.0 }
        return min(1.0, Double(latest) / Double(goal))
    }
    private var pct: Int { Int(ratio * 100) }

    private var eta: Date? {
        guard let c = chapter, let p = project else { return nil }
        return store.estimatedCompletionDate(for: c.id, in: p.id)
    }
    private var daysToETA: Int? {
        guard let d = eta else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: d).day
    }

    private var ringColor: Color {
        if ratio >= 1.0 { return .accentGreen }
        if ratio >= 0.75 { return Color(hex: "#F5C518") }
        return Color.accent
    }

    var body: some View {
        GlassCard {
            if let chapter {
                VStack(spacing: 12) {
                    // Header
                    HStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(ringColor.opacity(0.12))
                                .frame(width: 28, height: 28)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(ringColor)
                        }
                        Text("Chapitre en focus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        if let st = chapter.status, !chapter.isCompleted {
                            Text(st.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(hex: st.color))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: st.color).opacity(0.12))
                                .clipShape(Capsule())
                        }
                        if chapter.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.accentGreen)
                        }
                    }

                    // Chapter name
                    Text(chapter.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Ring + stats
                    HStack(spacing: 16) {
                        gaugeRing
                        VStack(alignment: .leading, spacing: 6) {
                            if goal > 0 {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(DataStore.formatNumber(latest))
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                    Text("/ \(DataStore.formatNumber(goal))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.labelMuted)
                                }
                            } else {
                                Text(DataStore.formatNumber(latest))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                            }

                            if let days = daysToETA {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10))
                                        .foregroundColor(.labelMuted)
                                    Text(days <= 0 ? "Fin prévue aujourd'hui"
                                         : days == 1 ? "Fin prévue demain"
                                         : "Fin dans \(days) j")
                                        .font(.system(size: 11))
                                        .foregroundColor(.labelMuted)
                                }
                            }

                            if let nextStep = chapter.nextStep, !nextStep.isEmpty {
                                HStack(alignment: .top, spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accent)
                                        .padding(.top, 1)
                                    Text(nextStep)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // ETA date label
                    if let eta, goal > 0, ratio < 1.0 {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.6))
                            Text("Fin estimée le \(etaFormatted(eta))")
                                .font(.system(size: 10))
                                .foregroundColor(.labelMuted.opacity(0.7))
                            Spacer()
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text").foregroundColor(.labelMuted)
                    Text("Sélectionne un chapitre actif").font(.system(size: 12)).foregroundColor(.labelMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            withAppAnimation(Motion.progress.delay(0.1)) { animatedRatio = ratio }
        }
        .onChange(of: ratio) { _, v in
            withAppAnimation(.easeOut(duration: 0.5)) { animatedRatio = v }
        }
    }

    private static let etaFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
    private func etaFormatted(_ date: Date) -> String {
        Self.etaFormatter.string(from: date)
    }

    private var gaugeRing: some View {
        ZStack {
            Circle().stroke(Color.cardBorder, lineWidth: 6).frame(width: 58, height: 58)
            Circle()
                .trim(from: 0, to: animatedRatio)
                .stroke(LinearGradient(colors: [ringColor.opacity(0.7), ringColor],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(pct)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("%")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
            }
        }
    }
}
