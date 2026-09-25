import SwiftUI
import ThubanGymCore

/// Plan's section-bar actions: "Skip a day" · "Swap a day", each a popover with a day, (for a swap) a workout, and
/// an optional note. Neither ever moves the cycle pointer. OWNER: Engineer B.
struct PlanToolbar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var skipping = false
    @State private var swapping = false

    var body: some View {
        ToolbarButton("Skip a day", icon: .skip) { skipping = true }
            .popover(isPresented: $skipping, arrowEdge: .bottom) {
                PlanOverrideForm(mode: .skip) { skipping = false }
                    .environment(app)
                    .environment(\.thubanTheme, theme)
            }
        ToolbarButton("Swap a day", icon: .swap) { swapping = true }
            .popover(isPresented: $swapping, arrowEdge: .bottom) {
                PlanOverrideForm(mode: .swap) { swapping = false }
                    .environment(app)
                    .environment(\.thubanTheme, theme)
            }
    }
}

/// The popover form behind "Skip a day" / "Swap a day".
struct PlanOverrideForm: View {
    enum Mode { case skip, swap }

    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var mode: Mode
    var dismiss: () -> Void

    @State private var date: DayKey?
    @State private var workoutId: String?
    @State private var note = ""

    var body: some View {
        let days = app.planDays(from: app.today, count: 21)
        let selected = date ?? defaultDay(days)
        VStack(alignment: .leading, spacing: 14) {
            Text(mode == .skip ? "Skip a day" : "Swap a day")
                .font(ThubanFont.display(20))
                .foregroundStyle(theme.inkColor)

            VStack(alignment: .leading, spacing: 6) {
                PlanControlCaption("Day")
                Menu {
                    ForEach(days) { day in
                        Button("\(day.date.planShort) · \(dayLabel(day))") { date = day.date }
                    }
                } label: {
                    Text(selected.map { "\($0.planShort) · \(dayLabel(app.planDay($0)))" } ?? "Choose a day")
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Day")
            }

            if mode == .swap {
                VStack(alignment: .leading, spacing: 6) {
                    PlanControlCaption("Do instead")
                    Menu {
                        ForEach(app.workouts) { workout in
                            Button(workout.name) { workoutId = workout.id }
                        }
                    } label: {
                        Text(app.workout(workoutId)?.name ?? "Choose a workout")
                    }
                    .menuStyle(.button)
                    .fixedSize()
                    .accessibilityLabel("Workout")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                PlanControlCaption("Note (optional)")
                TextField(mode == .skip ? "Career fair, 10–3" : "TA office hours until 6", text: $note)
                    .planField(height: 32)
                    .onSubmit { commit(selected) }
            }

            Text(consequence(selected))
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: dismiss).buttonStyle(GhostButtonStyle(height: 32))
                    .keyboardShortcut(.cancelAction)
                Button(mode == .skip ? "Skip day" : "Swap day") { commit(selected) }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || (mode == .swap && workoutId == nil))
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(theme.panelColor)
    }

    /// The first day from today that is not already skipped (skip) / the first day (swap).
    private func defaultDay(_ days: [PlanDay]) -> DayKey? {
        if mode == .skip { return days.first { $0.status != .skipped && $0.status != .done }?.date }
        return days.first { $0.status != .done }?.date
    }

    private func dayLabel(_ day: PlanDay) -> String {
        switch day.status {
        case .skipped: return "skipped"
        case .done, .restDone: return "done"
        default: return day.workout?.name ?? "nothing planned"
        }
    }

    private func consequence(_ date: DayKey?) -> String {
        guard let date else { return "" }
        let day = app.planDay(date)
        switch mode {
        case .skip:
            if app.isCycle, let workout = day.workout, !workout.isRest {
                return "\(workout.name) moves to the next day. The cycle pointer does not move."
            }
            return "The day is marked skipped. The plan itself does not change."
        case .swap:
            guard let new = app.workout(workoutId) else { return "Pick what to do that day instead." }
            if let planned = day.workout, planned.id != new.id, app.isCycle, !planned.isRest {
                return "\(new.name) instead of \(planned.name). \(planned.name) moves to the next day."
            }
            return "\(new.name) on \(date.planShort). The plan itself does not change."
        }
    }

    private func commit(_ date: DayKey?) {
        guard let date else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .skip: app.skip(date: date, note: trimmed.isEmpty ? nil : trimmed)
        case .swap:
            guard let workoutId else { return }
            app.swap(date: date, to: workoutId, note: trimmed.isEmpty ? nil : trimmed)
        }
        dismiss()
    }
}
