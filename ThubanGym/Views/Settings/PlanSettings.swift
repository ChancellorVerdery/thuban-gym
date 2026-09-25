import SwiftUI
import ThubanGymCore

/// Settings → Plan: plan type, default session length, default rest timer, the gym's address and opening hours.
/// OWNER: Engineer C (Progress + Settings/Import).
struct PlanSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Plan",
                               caption: "How days are planned, how long a session usually runs, and when the gym is open.")

            SettingsGroup("Plan type", caption: planCaption) {
                SegmentedPicker(
                    selection: Binding(get: { app.plan.type }, set: { app.setPlanType($0) }),
                    options: PlanType.allCases.map { SegmentOption($0, $0.label) },
                    segmentHeight: 28
                )
                .fixedSize()
                .accessibilityLabel("Plan type")
            }

            SettingsGroup("Sessions") {
                VStack(spacing: 8) {
                    SettingsRow("Default session length",
                                detail: "Used to plan a workout until it has timed sessions of its own.") {
                        SettingsStepper(value: Binding(get: { app.settings.defaultDuration },
                                                       set: { v in app.updateSettings { $0.defaultDuration = v } }),
                                        range: 15...240, step: 5, label: "Default session length") { "\($0) min" }
                    }
                    SettingsRow("Rest timer", detail: "Between sets. A workout can override it in Workouts.") {
                        SettingsStepper(value: Binding(get: { app.settings.restSeconds },
                                                       set: { v in app.updateSettings { $0.restSeconds = v } }),
                                        range: 15...600, step: 15, label: "Rest timer") { GymFormat.elapsed(TimeInterval($0)) }
                    }
                }
            }

            SettingsGroup("Gym", caption: "Opening hours keep suggested times inside the day. Leave a day empty when it has no limits.") {
                VStack(alignment: .leading, spacing: 12) {
                    GymAddressField()
                    GymHoursTable()
                }
            }
        }
    }

    private var planCaption: String {
        switch app.plan.type {
        case .cycle:
            return "A cycle rotates through \(app.plan.cycle.count) workouts. Skips and swaps never move the pointer; finishing a workout moves it past that workout."
        case .weekly:
            return "Weekly repeats the same workout on each weekday. Edit the days on Plan."
        }
    }
}

/// − value + control used by the Settings rows.
struct SettingsStepper: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var label: String
    var format: (Int) -> String

    var body: some View {
        HStack(spacing: 0) {
            button("−", enabled: value > range.lowerBound, name: "Decrease") { value = max(range.lowerBound, value - step) }
            Text(format(value))
                .font(ThubanFont.mono(13))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
                .frame(minWidth: 72)
                .frame(height: 30)
                .overlay(alignment: .leading) { Rectangle().fill(theme.line2Color).frame(width: ThubanMetrics.hairline) }
                .overlay(alignment: .trailing) { Rectangle().fill(theme.line2Color).frame(width: ThubanMetrics.hairline) }
            button("+", enabled: value < range.upperBound, name: "Increase") { value = min(range.upperBound, value + step) }
        }
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(enabled ? theme.inkColor : theme.inkFaintColor)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(name)
    }
}

/// The gym's address; a local draft committed on submit / focus loss (one write, not one per keystroke).
private struct GymAddressField: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Address").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            TextField("Address", text: $draft, prompt: Text("Where you train").foregroundStyle(theme.inkFaintColor))
                .labelsHidden()
                .focused($focused)
                .onSubmit(commit)
                .thubanField(height: 34)
                .frame(maxWidth: 480)
                .accessibilityLabel("Gym address")
        }
        .onAppear { draft = app.settings.address }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onChange(of: app.settings.address) { _, new in if !focused { draft = new } }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value != app.settings.address { app.updateSettings { $0.address = value } }
    }
}

/// Opening hours per weekday: open / close `HH:mm` fields; empty = no limits that day.
private struct GymHoursTable: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                header("Day").frame(width: 130, alignment: .leading)
                header("Opens").frame(width: 96, alignment: .leading)
                header("Closes").frame(width: 96, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            ForEach(Weekday.allCases) { day in
                GymHoursRow(day: day)
            }
        }
        .thubanPanel(padding: 0)
        .frame(maxWidth: 600)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.inkFaintColor)
    }
}

private struct GymHoursRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var day: Weekday
    @State private var open = ""
    @State private var close = ""
    @FocusState private var focus: Field?

    enum Field { case open, close }

    var body: some View {
        HStack(spacing: 12) {
            Text(day.name)
                .font(ThubanFont.body(14, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 130, alignment: .leading)
            timeField($open, field: .open, label: "\(day.name) opens")
            timeField($close, field: .close, label: "\(day.name) closes")
            Spacer(minLength: 0)
            Text(summary)
                .font(ThubanFont.small)
                .foregroundStyle(isInvalid ? theme.negTextColor : theme.inkFaintColor)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .thubanHairline(.top, color: theme.lineColor)
        .onAppear(perform: load)
        .onChange(of: app.settings.hours(for: day)) { _, _ in if focus == nil { load() } }
        .onChange(of: focus) { _, new in if new == nil { commit() } }
    }

    private func timeField(_ text: Binding<String>, field: Field, label: String) -> some View {
        TextField(label, text: text, prompt: Text("–").foregroundStyle(theme.inkFaintColor))
            .labelsHidden()
            .focused($focus, equals: field)
            .onSubmit(commit)
            .thubanField(invalid: !text.wrappedValue.isEmpty && ClockTime.minutes(text.wrappedValue) == nil, mono: true, height: 28)
            .frame(width: 96)
            .accessibilityLabel(label)
    }

    private var isInvalid: Bool {
        (!open.isEmpty && ClockTime.minutes(open) == nil) || (!close.isEmpty && ClockTime.minutes(close) == nil)
    }

    private var summary: String {
        if isInvalid { return "Use 24-hour HH:mm" }
        guard let o = ClockTime.minutes(open), let c = ClockTime.minutes(close) else { return open.isEmpty && close.isEmpty ? "No limits" : "" }
        return GymFormat.clockRange(start: ClockTime.string(minutes: o), end: ClockTime.string(minutes: c))
    }

    private func load() {
        let hours = app.settings.hours(for: day)
        open = hours.open
        close = hours.close
    }

    private func commit() {
        guard !isInvalid else { return }
        func normalized(_ text: String) -> String { ClockTime.minutes(text).map(ClockTime.string(minutes:)) ?? "" }
        let value = OpeningHours(open: normalized(open), close: normalized(close))
        if value != app.settings.hours(for: day) {
            app.updateSettings { $0.hours[day.rawValue] = value }
        }
        open = value.open
        close = value.close
    }
}
