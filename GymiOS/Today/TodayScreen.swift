import SwiftUI
import ThubanGymCore

/// Today (board Main): eyebrow + serif workout name, the cycle chips, "Start Pull", last time, and the exercise
/// list (tap a row to log it). The "…" menu swaps / skips / adds an exercise; the sliders open Settings.
struct TodayScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var sheet: TodaySheet?

    var body: some View {
        let plan = app.todayPlan
        let items = app.todayVisibleItems(plan)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if app.isFirstRun {
                    TodayFirstRun()
                } else {
                    TodayHeader(plan: plan, items: items)
                    TodayCycleChips(plan: plan)
                        .padding(.top, 16)
                    TodayAction(plan: plan, items: items, sheet: $sheet)
                        .padding(.top, 16)
                    if !items.isEmpty {
                        SectionHeading("Exercises") {
                            Text(app.activeSession != nil || plan.status == .done ? "Today" : "Last time")
                                .font(.footnote).foregroundStyle(theme.inkFaintColor)
                        }
                        .padding(.top, 22)
                        TodayExerciseList(items: items)
                    }
                    if let note = app.todayPlanNote() {
                        HStack(alignment: .top, spacing: 10) {
                            Icon(.calendar, size: 16).foregroundStyle(theme.inkFaintColor).padding(.top, 1)
                            Text(note).font(.footnote).foregroundStyle(theme.inkDimColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 24)
        }
        .phoneScreen(theme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                TodayMenu(plan: plan, sheet: $sheet)
                IconButton(.sliders, label: "Settings") { app.showSettings = true }
            }
        }
        .sheet(item: $sheet) { which in
            TodaySheetView(which: which)
                .phoneChrome()
        }
    }
}

enum TodaySheet: String, Identifiable {
    case swap, addExercise, skip
    var id: String { rawValue }
}

// MARK: - Header

struct TodayHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    var items: [SessionExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(eyebrow)
            Text(title)
                .font(PhoneFont.serif(34, relativeTo: .largeTitle))
                .kerning(-0.3)
                .foregroundStyle(theme.inkColor)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var eyebrow: String {
        var parts = [PhoneFormat.weekdayMonthDay(app.sessionDay)]
        switch plan.status {
        case .skipped: parts.append("Skipped")
        case .swapped: parts.append(plan.plannedWorkout.map { "Swapped for \($0.name)" } ?? "Swapped")
        case .done, .restDone: parts.append("Done")
        default:
            if let position = app.cyclePosition(on: app.sessionDay) {
                parts.append("Cycle day \(position.index + 1) of \(position.count)")
            } else if plan.source == .weekly {
                parts.append("Weekly plan")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var title: String {
        switch plan.status {
        case .skipped: return "Day off"
        case .empty: return items.isEmpty ? "Nothing planned" : "Free session"
        default: return plan.workout?.name ?? "Nothing planned"
        }
    }

    private var subtitle: String {
        if plan.status == .skipped {
            return [plan.workout.map { "\($0.name) was planned" } ?? "Skipped", plan.override?.note].compactMap { $0 }.joined(separator: " · ")
        }
        guard let workout = plan.workout else {
            return items.isEmpty ? "Your plan has nothing for today." : PhoneFormat.count(items.count, "exercise") + " pulled in"
        }
        if workout.isRest {
            return plan.status == .restDone ? "Rest day recorded." : "Recovery day. It is marked done by itself at midnight."
        }
        let own = items.filter { !$0.isExtra }.count
        let extras = items.count - own
        var count = PhoneFormat.count(own, "exercise")
        if extras > 0 { count += " + \(extras) extra\(extras == 1 ? "" : "s")" }
        var parts = [count]
        let planned = PlanEngine.plannedSetCount(items)
        if planned > 0 { parts.append("\(planned) sets") }
        parts.append("about \(GymFormat.minutes(app.workoutDuration(workout.id)))")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Cycle chips

/// Push · Pull · Legs · Rest: done (pos, check), today (accent tint + border), upcoming (panel + hairline).
struct TodayCycleChips: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    var compact = false

    enum SlotState { case done, current, upcoming }

    var body: some View {
        let cycle = app.plan.cycle
        if app.isCycle, !cycle.isEmpty {
            let pointer = app.plan.normalizedPosition
            let todayDone = plan.status == .done || plan.status == .restDone
            let current = plan.cycleIndex ?? (todayDone ? (pointer - 1 + cycle.count) % max(1, cycle.count) : pointer)
            HStack(spacing: 6) {
                ForEach(Array(cycle.enumerated()), id: \.offset) { index, id in
                    let state: SlotState = index < current ? .done : (index == current ? (todayDone ? .done : .current) : .upcoming)
                    chip(app.workout(id)?.name ?? "?", state: state, label: "Cycle day \(index + 1), \(app.workout(id)?.name ?? "")")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Cycle")
        } else if !app.isCycle {
            HStack(spacing: 6) {
                ForEach(app.planDays(from: app.weekStart, count: 7)) { day in
                    let state: SlotState = day.isToday ? .current : ((day.status == .done || day.status == .restDone) ? .done : .upcoming)
                    chip(String(day.date.weekday.short.prefix(1)), state: state,
                         label: "\(day.date.weekday.name), \(day.workout?.name ?? "nothing planned")")
                }
            }
        }
    }

    private func chip(_ name: String, state: SlotState, label: String) -> some View {
        let fill: Color, ink: Color, border: Color
        switch state {
        case .done: (fill, ink, border) = (theme.posSoftColor, theme.posTextColor, .clear)
        case .current: (fill, ink, border) = (theme.accentTintColor, theme.brassInkColor, theme.accentColor)
        case .upcoming: (fill, ink, border) = (theme.panelColor, theme.inkDimColor, theme.line2Color)
        }
        return HStack(spacing: 4) {
            if state == .done { Icon(.check, size: 13, lineWidth: 2.2) }
            Text(name).lineLimit(1).minimumScaleFactor(0.7)
        }
        .font(PhoneFont.sans(compact ? 13 : 14, relativeTo: .subheadline, weight: .semibold))
        .foregroundStyle(ink)
        .padding(.horizontal, compact ? 8 : 4)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 30 : 34)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label + (state == .done ? ", done" : state == .current ? ", today" : ""))
    }
}

// MARK: - Primary action

struct TodayAction: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    var items: [SessionExercise]
    @Binding var sheet: TodaySheet?

    var body: some View {
        VStack(spacing: 8) {
            if let session = app.activeSession, let workout = app.workout(session.workoutId) {
                Button { app.openSession() } label: {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        HStack(spacing: 10) {
                            Icon(.play, size: 20)
                            Text("Resume \(workout.name)")
                            Text("·").foregroundStyle(theme.onAccentColor.opacity(0.6))
                            Text(GymFormat.elapsed(app.sessionElapsed(now: context.date))).monospacedDigit()
                        }
                    }
                }
                .buttonStyle(PhonePrimaryStyle())
                caption(sessionCaption)
            } else {
                switch plan.status {
                case .done:
                    Button { app.openSession() } label: {
                        HStack(spacing: 10) { Icon(.check, size: 20); Text("Review today's sets") }
                    }
                    .buttonStyle(PhoneSecondaryStyle(height: PhoneMetrics.primaryHeight))
                    caption(doneCaption)
                case .rest:
                    if let workout = plan.workout {
                        Button { app.complete(workoutId: workout.id) } label: {
                            HStack(spacing: 10) { Icon(.check, size: 20); Text("Mark rest done") }
                        }
                        .buttonStyle(PhoneSecondaryStyle(height: PhoneMetrics.primaryHeight))
                    }
                    trainAnyway
                case .restDone:
                    trainAnyway
                case .skipped:
                    Button("Undo skip") { app.clearOverride(date: app.today) }
                        .buttonStyle(PhoneSecondaryStyle(height: PhoneMetrics.primaryHeight))
                    trainAnyway
                case .empty, .missed:
                    trainAnyway
                default:
                    if let workout = plan.workout {
                        Button { app.beginSession(workoutId: workout.id) } label: {
                            HStack(spacing: 10) { Icon(.play, size: 20); Text("Start \(workout.name)") }
                        }
                        .buttonStyle(PhonePrimaryStyle())
                        if let last = lastCaption(workout) { caption(last) }
                    }
                }
            }
        }
    }

    private var trainAnyway: some View {
        Button("Train anyway…") { sheet = .swap }
            .buttonStyle(PhoneTextStyle())
            .frame(maxWidth: .infinity)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(theme.inkFaintColor)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// "Last Pull Sun Sep 20 · 61 min · 10,345 lb".
    private func lastCaption(_ workout: Workout) -> String? {
        guard let last = app.todayLastCompletion(of: workout.id) else { return "First \(workout.name)" }
        var parts = ["Last \(workout.name) \(GymFormat.shortDay(last.date))"]
        if let minutes = last.durationMinutes { parts.append(GymFormat.minutes(minutes)) }
        if let volume = app.todayLastVolume(of: workout.id) { parts.append(PhoneFormat.volume(volume.volume, unit: app.unit)) }
        return parts.joined(separator: " · ")
    }

    private var sessionCaption: String {
        let progress = app.sessionProgress
        let start = app.activeSession.map { GymFormat.clock(ClockTime.string(from: $0.startedAt)) } ?? ""
        return "\(progress.logged) of \(progress.planned) sets" + (start.isEmpty ? "" : " · started \(start)")
    }

    private var doneCaption: String {
        guard let done = plan.completions.last(where: { !(app.workout($0.workoutId)?.isRest ?? false) }) else { return "Done" }
        let range = GymFormat.clockRange(start: done.start, end: done.end)
        let minutes = done.durationMinutes.map(GymFormat.minutes)
        return (["Done", range, minutes].compactMap { $0?.isEmpty == false ? $0 : nil }).joined(separator: " · ")
    }
}

// MARK: - Exercise list

struct TodayExerciseList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var items: [SessionExercise]

    var body: some View {
        Card {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider(inset: 54) }
                Button { app.openSession(exerciseId: item.id) } label: {
                    TodayExerciseRow(item: item, number: index + 1)
                }
                .buttonStyle(RowPressStyle())
                .contextMenu {
                    Button("History") { app.presentExercise(item.id) }
                    if item.isExtra {
                        Button("Remove from today", role: .destructive) { app.removeExtra(exerciseId: item.id) }
                    }
                }
            }
        }
    }
}

struct TodayExerciseRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: SessionExercise
    var number: Int

    var body: some View {
        let exercise = item.exercise
        let finished = SessionLogic.isFinished(app.data, exercise: exercise, on: app.sessionDay)
        let todaySession = app.session(exerciseId: exercise.id, on: app.sessionDay)
        let last = app.previousSession(exerciseId: exercise.id, before: app.sessionDay)
        HStack(spacing: 12) {
            badge(finished: finished)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                        .lineLimit(2)
                    if exercise.unilateral { PhoneChip("L / R", kind: .signal) }
                    if item.isExtra { PhoneChip("Extra", kind: .warn) }
                }
                Text(detail(today: todaySession, last: last))
                    .font(PhoneFont.mono(13))
                    .foregroundStyle(theme.inkFaintColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            trailing
            RowChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the set logger")
    }

    @ViewBuilder private func badge(finished: Bool) -> some View {
        if finished {
            Icon(.check, size: 14, lineWidth: 2.2)
                .foregroundStyle(theme.posTextColor)
                .frame(width: 26, height: 26)
                .background(theme.posSoftColor, in: Circle())
        } else {
            Text(item.isExtra ? "+" : "\(number)")
                .font(PhoneFont.mono(13, weight: .semibold))
                .foregroundStyle(item.isExtra ? theme.brassInkColor : theme.inkDimColor)
                .frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: item.isExtra ? [2, 2] : [])))
        }
    }

    private func detail(today: ExerciseSession?, last: ExerciseSession?) -> String {
        let target = item.exercise.targetSpec?.display ?? item.exercise.target
        if let today { return [target, PhoneFormat.session(today, unit: app.unit)].filter { !$0.isEmpty }.joined(separator: " · ") }
        guard let last else { return target.isEmpty ? "No target" : target }
        return [target, PhoneFormat.session(last, unit: app.unit)].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder private var trailing: some View {
        if item.exercise.bodyweight {
            Text("Bodyweight").font(.footnote).foregroundStyle(theme.inkDimColor)
        } else if let target = app.nextTarget(exerciseId: item.id), target.increase, target.weightKg != nil,
                  app.session(exerciseId: item.id, on: app.sessionDay) == nil {
            Text("Try \(app.weight(target.weightKg))").font(.footnote.weight(.semibold)).foregroundStyle(theme.signalTextColor)
        }
    }
}

/// Row highlight on press (panel2), no system blue.
struct RowPressStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? theme.panel2Color : Color.clear)
    }
}

// MARK: - First run

struct TodayFirstRun: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(PhoneFormat.weekdayMonthDay(app.today))
            Text("Welcome").font(PhoneFont.serif(34, relativeTo: .largeTitle)).foregroundStyle(theme.inkColor)
            Text("Bring your log over from the Mac: in Thuban Gym on the Mac choose Settings ▸ Data ▸ Export, AirDrop gym.json or save it to Files, then import it here.")
                .font(.subheadline).foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
            Button { app.showSettings = true } label: {
                HStack(spacing: 10) { Icon(.download, size: 20); Text("Import gym.json…") }
            }
            .buttonStyle(PhonePrimaryStyle())
            .padding(.top, 8)
            Button("Or start fresh: add a workout") { app.tab = .workouts }
                .buttonStyle(PhoneTextStyle())
                .frame(maxWidth: .infinity)
        }
    }
}

extension AppModel {
    /// Opens the exercise history on the current tab's stack.
    func presentExercise(_ id: String) {
        switch tab {
        case .today: todayPath.append(.exercise(id))
        case .plan: planPath.append(.exercise(id))
        case .workouts: workoutsPath.append(.exercise(id))
        case .progress: progressPath.append(.exercise(id))
        }
    }
}
