import SwiftUI
import AppKit

// MARK: - DarkPopoverModifier
// Les popovers macOS créent leur propre NSPanel, qui n'hérite pas du
// `.preferredColorScheme(.dark)` appliqué à la fenêtre principale quand
// « Forcer le mode sombre » est activé. On aligne donc l'apparence du panel
// sur celle de l'app : .darkAqua uniquement si le mode sombre est forcé,
// sinon `nil` (hérite de l'apparence système / de l'app, clair ou sombre).

private struct PopoverAppearanceSync: NSViewRepresentable {
    let forceDark: Bool

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        apply(to: v)
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {
        apply(to: v)
    }
    private func apply(to v: NSView) {
        let dark = forceDark
        Task { @MainActor in
            v.window?.appearance = dark ? NSAppearance(named: .darkAqua) : nil
        }
    }
}

private struct PopoverAppearanceModifier: ViewModifier {
    @AppStorage("forceDarkMode") private var forceDarkMode: Bool = false

    func body(content: Content) -> some View {
        content.background(PopoverAppearanceSync(forceDark: forceDarkMode))
    }
}

extension View {
    /// Aligne l'apparence du popover sur celle de l'app (nom historique conservé).
    func darkPopoverAppearance() -> some View {
        self.modifier(PopoverAppearanceModifier())
    }
}

// MARK: - Color from hex (V3.2)

extension Color {
    /// Cached: parses the hex string once, reuses the Color for subsequent calls.
    /// Status colors and accents are read on every render of every chapter row /
    /// status pill — without the cache, each access re-parses the hex.
    private static let hexCache = NSCache<NSString, NSColor>()

    init(hex: String) {
        let key = hex as NSString
        if let cached = Self.hexCache.object(forKey: key) {
            self = Color(nsColor: cached)
            return
        }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r = CGFloat(Double((int >> 16) & 0xFF) / 255)
        let g = CGFloat(Double((int >> 8) & 0xFF) / 255)
        let b = CGFloat(Double(int & 0xFF) / 255)
        let nsColor = NSColor(red: r, green: g, blue: b, alpha: 1)
        Self.hexCache.setObject(nsColor, forKey: key)
        self = Color(nsColor: nsColor)
    }
}

// MARK: - Progress Ring (#18)

struct ProgressRingView: View {
    let ratio: Double          // 0.0 → 1.0
    var color: Color = .accent
    var lineWidth: CGFloat = 3
    var size: CGFloat = 36
    var label: String? = nil   // Texte optionnel au centre (ex: "42%")

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)
                .frame(width: size, height: size)
            Circle()
                .trim(from: 0, to: CGFloat(min(ratio, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: ratio)
            if let label {
                Text(label)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Type Scale (#16 — hiérarchie typographique)

extension Font {
    /// Métriques hero (streak, total) — SF Pro Rounded Bold 40pt
    static var appDisplayXL: Font { .system(size: 40, weight: .bold, design: .rounded) }
    /// Grands chiffres clés — SF Pro Rounded Bold 28pt
    static var appDisplay: Font { .system(size: 28, weight: .bold, design: .rounded) }
    /// Valeurs de stat proéminentes — SF Pro Rounded Semibold 22pt
    static var appMetric: Font { .system(size: 22, weight: .semibold, design: .rounded) }
    /// Valeurs secondaires — SF Pro Rounded Semibold 17pt
    static var appMetricSm: Font { .system(size: 17, weight: .semibold, design: .rounded) }
    /// Titres de section — SF Pro Semibold 17pt
    static var appTitle: Font { .system(size: 17, weight: .semibold) }
    /// Sous-titres — SF Pro Semibold 15pt
    static var appTitleSm: Font { .system(size: 15, weight: .semibold) }
    /// Texte standard — SF Pro Regular 13pt
    static var appBody: Font { .system(size: 13, weight: .regular) }
    /// Texte accentué — SF Pro Medium 13pt
    static var appBodyMedium: Font { .system(size: 13, weight: .medium) }
    /// Labels secondaires — SF Pro Medium 11pt
    static var appLabel: Font { .system(size: 11, weight: .medium) }
    /// Texte tertiaire — SF Pro Regular 10pt
    static var appCaption: Font { .system(size: 10) }
}

// MARK: - CompactDatePicker
// Remplace le DatePicker natif pour une sélection de date uniquement.
// Affiche : ← [label date] → avec popover calendrier custom.

struct CompactDatePicker: View {
    @Binding var date: Date
    var maxDate: Date = Date()
    var minDate: Date? = nil

    @State private var isOpen = false
    @State private var displayedMonth: Date
    @State private var rawInput: String = ""

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()
    private var cal: Calendar { Self.cal }

    // Static formatters: avoid allocating a new DateFormatter on every body
    // re-evaluation (these are expensive to construct).
    private static let dayMonthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM yyyy"; return f
    }()
    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"; return f
    }()
    private static let parseFormatter: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_FR")
        return f
    }()

    init(date: Binding<Date>, maxDate: Date = Date(), minDate: Date? = nil) {
        _date = date
        self.maxDate = maxDate
        self.minDate = minDate
        let monthStart = Self.cal.date(
            from: Self.cal.dateComponents([.year, .month], from: date.wrappedValue)
        ) ?? Date()
        _displayedMonth = State(initialValue: monthStart)
    }

    var body: some View {
        HStack(spacing: 0) {
            // ← jour précédent
            Button { adjustDate(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canGoPrev ? .labelMuted : .labelMuted.opacity(0.25))
                    .frame(width: 28, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!canGoPrev)
            .help("Jour précédent")
            .accessibilityLabel("Jour précédent")

            Divider().frame(height: 16)

            // Label → ouvre popover
            Button { isOpen = true } label: {
                Text(formattedDate)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(minWidth: 116)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isOpen, arrowEdge: .bottom) {
                popoverContent
                    .background(Color.cardBg)
                    .darkPopoverAppearance()
            }

            Divider().frame(height: 16)

            // → jour suivant
            Button { adjustDate(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(canGoNext ? .labelMuted : .labelMuted.opacity(0.25))
                    .frame(width: 28, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!canGoNext)
            .help("Jour suivant")
            .accessibilityLabel("Jour suivant")
        }
        .background(Color.glassFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.glassBorder, lineWidth: 1)
        )
    }

    // MARK: - Popover

    private var popoverContent: some View {
        VStack(spacing: 10) {
            // Raccourcis rapides
            HStack(spacing: 6) {
                shortcutBtn("Auj.", offset: 0)
                shortcutBtn("Hier", offset: -1)
                shortcutBtn("-7j",  offset: -7)
                shortcutBtn("-30j", offset: -30)
            }

            Divider().overlay(Color.white.opacity(0.07))

            // Navigation mois
            HStack(spacing: 0) {
                Button { changeMonth(by: -1) } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .frame(width: 26, height: 26)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Mois précédent")
                .accessibilityLabel("Mois précédent")

                Spacer()
                Text(monthLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()

                Button { changeMonth(by: 1) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(canGoNextMonth ? .labelMuted : .labelMuted.opacity(0.25))
                        .frame(width: 26, height: 26)
                        .background(Color.glassFill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!canGoNextMonth)
                .help("Mois suivant")
                .accessibilityLabel("Mois suivant")
            }

            // En-têtes jours
            HStack(spacing: 0) {
                ForEach(["L","M","M","J","V","S","D"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.labelMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            // Grille
            VStack(spacing: 3) {
                ForEach(monthGrid.indices, id: \.self) { weekIdx in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { dayIdx in
                            if let cellDate = monthGrid[weekIdx][dayIdx] {
                                dayCell(cellDate)
                            } else {
                                Color.clear.frame(width: 28, height: 26)
                            }
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.07))

            // Saisie clavier
            HStack(spacing: 8) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
                TextField("jj/mm ou jj/mm/aaaa", text: $rawInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { parseRawInput() }
                    .onAppear { rawInput = "" }
                if !rawInput.isEmpty {
                    Button { parseRawInput() } label: {
                        Image(systemName: "return")
                            .font(.system(size: 10))
                            .foregroundColor(.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Valider la date saisie")
                    .accessibilityLabel("Valider la date saisie")
                }
            }
        }
        .padding(12)
        .frame(width: 228)
    }

    // MARK: - Day cell

    private func dayCell(_ cellDate: Date) -> some View {
        let isSelected = cal.isDate(date, inSameDayAs: cellDate)
        let isToday    = cal.isDateInToday(cellDate)
        let isFuture   = cellDate > cal.startOfDay(for: maxDate)
        let isBefore   = minDate.map { cellDate < cal.startOfDay(for: $0) } ?? false
        let disabled   = isFuture || isBefore

        return Button {
            if !disabled { selectDate(cellDate) }
        } label: {
            Text("\(cal.component(.day, from: cellDate))")
                .font(.system(size: 11, weight: isSelected || isToday ? .bold : .regular))
                .foregroundColor(
                    disabled  ? .labelMuted.opacity(0.25)
                    : isSelected ? .white
                    : isToday    ? .accent
                    : .primary
                )
                .frame(width: 28, height: 26)
                .background(
                    isSelected ? Color.accent
                    : isToday  ? Color.accent.opacity(0.12)
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Shortcut button

    private func shortcutBtn(_ label: String, offset: Int) -> some View {
        let target = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date()))!
        let isSelected = cal.isDate(date, inSameDayAs: target)
        let available  = target <= maxDate && (minDate == nil || target >= minDate!)

        return Button {
            if available { selectDate(target) }
        } label: {
            Text(label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : (available ? .labelMuted : .labelMuted.opacity(0.3)))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(isSelected ? Color.accent.opacity(0.85) : Color.white.opacity(0.06))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accent : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    // MARK: - Helpers

    private var formattedDate: String {
        if cal.isDateInToday(date)     { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        return Self.dayMonthYearFormatter.string(from: date)
    }

    private var canGoPrev: Bool {
        guard let prev = cal.date(byAdding: .day, value: -1, to: date) else { return false }
        if let min = minDate { return prev >= cal.startOfDay(for: min) }
        return true
    }

    private var canGoNext: Bool {
        guard let next = cal.date(byAdding: .day, value: 1, to: date) else { return false }
        return next <= cal.startOfDay(for: maxDate)
    }

    private var canGoNextMonth: Bool {
        guard let next = cal.date(byAdding: .month, value: 1, to: displayedMonth) else { return false }
        let maxMonth = cal.date(from: cal.dateComponents([.year, .month], from: maxDate))!
        return next <= maxMonth
    }

    private func adjustDate(by days: Int) {
        guard let raw = cal.date(byAdding: .day, value: days, to: date) else { return }
        let clamped = min(cal.startOfDay(for: maxDate),
                          max(minDate.map { cal.startOfDay(for: $0) } ?? .distantPast,
                              cal.startOfDay(for: raw)))
        date = clamped
        displayedMonth = cal.date(from: cal.dateComponents([.year, .month], from: clamped)) ?? clamped
    }

    private func selectDate(_ d: Date) {
        date = cal.startOfDay(for: d)
        displayedMonth = cal.date(from: cal.dateComponents([.year, .month], from: d)) ?? d
        isOpen = false
    }

    private func changeMonth(by value: Int) {
        guard let next = cal.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        let maxMonth = cal.date(from: cal.dateComponents([.year, .month], from: maxDate))!
        displayedMonth = min(next, maxMonth)
    }

    private var monthLabel: String {
        let s = Self.monthYearFormatter.string(from: displayedMonth)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var monthGrid: [[Date?]] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: displayedMonth)),
              let monthEnd   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else { return [] }
        let wd = cal.component(.weekday, from: monthStart)
        let daysFromMon = (wd + 5) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -daysFromMon, to: monthStart) else { return [] }
        var weeks: [[Date?]] = []
        var weekStart = gridStart
        while weekStart <= monthEnd {
            var week: [Date?] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: weekStart) else { week.append(nil); continue }
                week.append(cal.isDate(day, equalTo: monthStart, toGranularity: .month) ? day : nil)
            }
            weeks.append(week)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = next
        }
        return weeks
    }

    private func parseRawInput() {
        let formats = ["dd/MM/yyyy", "dd/MM/yy", "dd/MM"]
        let fmt = Self.parseFormatter
        for format in formats {
            fmt.dateFormat = format
            if var parsed = fmt.date(from: rawInput) {
                if format == "dd/MM" {
                    let dc = cal.dateComponents([.day, .month], from: parsed)
                    var yc = DateComponents()
                    yc.day = dc.day; yc.month = dc.month
                    yc.year = cal.component(.year, from: Date())
                    parsed = cal.date(from: yc) ?? parsed
                }
                let clamped = cal.startOfDay(for: parsed)
                if clamped <= maxDate && (minDate == nil || clamped >= minDate!) {
                    selectDate(clamped); rawInput = ""; return
                }
            }
        }
    }
}

// MARK: - CompactDropdownPicker
// Remplace le Picker natif (menu déroulant macOS) par un bouton élégant
// qui ouvre un popover avec la liste des options.

struct CompactDropdownPicker: View {
    let icon: String
    let iconColor: Color
    let placeholder: String
    let items: [(id: UUID, name: String)]
    let selectedId: UUID?
    let onSelect: (UUID) -> Void

    @State private var isOpen = false

    private var selectedName: String {
        items.first(where: { $0.id == selectedId })?.name ?? placeholder
    }

    var body: some View {
        Button { isOpen = true } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                Text(selectedName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(selectedId == nil ? .labelMuted : .primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.labelMuted)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.glassFill)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isOpen, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(items, id: \.id) { item in
                    Button {
                        onSelect(item.id)
                        isOpen = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon)
                                .font(.system(size: 11))
                                .foregroundColor(item.id == selectedId ? iconColor : .labelMuted)
                                .frame(width: 16)
                            Text(item.name)
                                .font(.system(size: 13, weight: item.id == selectedId ? .semibold : .regular))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            if item.id == selectedId {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(iconColor)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(item.id == selectedId ? iconColor.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(minWidth: 200, maxWidth: 280)
            .background(Color.cardBg)
            .darkPopoverAppearance()
        }
    }
}
