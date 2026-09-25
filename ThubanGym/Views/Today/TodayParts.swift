import Observation
import SwiftUI
import ThubanGymCore

// Small building blocks shared by Today's cards, rail and toolbar (and the Exercise sheet). OWNER: Engineer A.

// MARK: - Rest timer

/// The rest timer between sets. App-wide (not per view) so it keeps running when you switch sections; it starts
/// itself whenever a set is checked off on Today. Not persisted: a relaunch starts idle.
@MainActor
@Observable
final class TodayRestClock {
    static let shared = TodayRestClock()

    private(set) var startedAt: Date?
    private(set) var duration: Int = 120

    func start(seconds: Int, at now: Date = Date()) {
        duration = max(5, seconds)
        startedAt = now
    }

    func stop() { startedAt = nil }

    var isRunning: Bool { startedAt != nil }

    /// Seconds left (0 once it has run out); the full duration when idle.
    func remaining(at now: Date) -> TimeInterval {
        guard let startedAt else { return TimeInterval(duration) }
        return max(0, TimeInterval(duration) - now.timeIntervalSince(startedAt))
    }

    /// 0…1 of the rest taken.
    func fraction(at now: Date) -> Double {
        guard startedAt != nil, duration > 0 else { return 0 }
        return 1 - remaining(at: now) / TimeInterval(duration)
    }
}

// MARK: - Glyphs the shared Icon set does not have

/// The design's "Finish session" stop square (rx 2, 1.75 stroke on a 24 grid).
struct TodayStopGlyph: View {
    var size: CGFloat = 15
    var body: some View {
        let scale = size / 24
        RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
            .stroke(.foreground, lineWidth: 1.75 * scale)
            .frame(width: 12 * scale, height: 12 * scale)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The design's rest-timer clock (circle r 8.5 + hands).
struct TodayClockGlyph: View {
    var size: CGFloat = 14
    var body: some View {
        Canvas { context, canvas in
            let s = canvas.width / 24
            var path = Path(ellipseIn: CGRect(x: (12 - 8.5) * s, y: (12 - 8.5) * s, width: 17 * s, height: 17 * s))
            path.move(to: CGPoint(x: 12 * s, y: 7.5 * s))
            path.addLine(to: CGPoint(x: 12 * s, y: 12 * s))
            path.addLine(to: CGPoint(x: 15 * s, y: 14 * s))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.75 * s, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Chips

/// Monospaced target chip ("4 × 6–8"): `panel2` fill, `inkDim` text.
struct TodayMonoChip: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var text: String

    var body: some View {
        Text(text)
            .font(ThubanFont.mono(12 * textScale, weight: .semibold))
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .fixedSize()
    }
}

// MARK: - Card badge

/// The 26 pt round marker at the left of each exercise card: a green check once done, a filled accent number on
/// the focused card, an outlined number otherwise.
struct TodayCardBadge: View {
    enum Style { case done, focused, idle }
    @Environment(\.thubanTheme) private var theme
    var number: Int
    var style: Style

    var body: some View {
        ZStack {
            switch style {
            case .done:
                Circle().fill(theme.posSoftColor)
                Icon(.check, size: 14).foregroundStyle(theme.posTextColor)
            case .focused:
                Circle().fill(theme.accentColor)
                Text(String(number)).font(ThubanFont.mono(12.5, weight: .bold)).foregroundStyle(theme.onAccentColor)
            case .idle:
                Circle().strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline)
                Text(String(number)).font(ThubanFont.mono(12.5, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

// MARK: - Check button

/// 32 pt square check-off button: outlined when open, green (pos) once the set is logged.
struct TodayCheckButton: View {
    @Environment(\.thubanTheme) private var theme
    var isDone: Bool
    var label: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Icon(.check, size: 16)
                .foregroundStyle(isDone ? theme.posTextColor : (hovering ? theme.inkDimColor : theme.inkFaintColor))
                .frame(width: 32, height: 32)
                .background(isDone ? theme.posSoftColor : (hovering ? theme.panel2Color : theme.panelColor),
                            in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isDone ? theme.posColor : theme.line2Color, lineWidth: ThubanMetrics.hairline))
                .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isDone ? [.isSelected] : [])
        .help(label)
    }
}

// MARK: - Number field

/// The set table's input: 32 pt, `line2` border, mono 14 right-aligned, optional faint unit suffix inside.
/// Keeps a local draft and reports it on Return or when focus leaves (one write per edit, not per keystroke).
struct TodayNumberField: View {
    @Environment(\.thubanTheme) private var theme
    var value: String
    var placeholder: String = ""
    var suffix: String?
    var width: CGFloat
    var accessibilityLabel: String
    /// The row is not logged yet: the value is a suggestion, shown dimmer until typed over.
    var isSuggestion: Bool = false
    /// Report every keystroke (for local drafts, so a click on the check button right after typing sees the value).
    /// Off for logged sets, which write to the document once per edit.
    var live: Bool = false
    var onCommit: (String) -> Void
    var onSubmit: (() -> Void)?

    @State private var draft: String = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(ThubanFont.mono(14))
                .foregroundStyle(isSuggestion && !editing ? theme.inkDimColor : theme.inkColor)
                .focused($focused)
                .onSubmit {
                    commit()
                    onSubmit?()
                }
                .accessibilityLabel(accessibilityLabel)
            if let suffix, !draft.isEmpty {
                Text(suffix).font(.system(size: 12)).foregroundStyle(theme.inkFaintColor)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, suffix == nil || draft.isEmpty ? 10 : 9)
        .frame(width: width, height: 32)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
            .strokeBorder(focused ? theme.accentColor : theme.line2Color, lineWidth: ThubanMetrics.hairline))
        .onAppear { draft = value }
        .onChange(of: value) { _, newValue in if !focused { draft = newValue } }
        .onChange(of: draft) { _, text in
            if live, focused, text.trimmingCharacters(in: .whitespaces) != value { onCommit(text.trimmingCharacters(in: .whitespaces)) }
        }
        .onChange(of: focused) { _, isFocused in
            editing = isFocused
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if trimmed != value { onCommit(trimmed) }
    }
}

// MARK: - Parsing typed numbers

enum TodayInput {
    /// "140", "62.5", "62,5" → 140 / 62.5; "", "BW", "0" → nil (bodyweight).
    static func weight(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    /// Whole reps (≥ 0); nil for text that is not a number.
    static func reps(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        guard let value = Int(cleaned) ?? Double(cleaned).map({ Int($0.rounded()) }) else { return nil }
        return max(0, value)
    }
}
