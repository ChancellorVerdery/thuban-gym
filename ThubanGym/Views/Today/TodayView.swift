import SwiftUI
import ThubanGymCore

/// Today section (design: Main.dc.html / TodayDark.dc.html). Left: the day's header (date · cycle day, serif
/// workout name, summary, sets logged) and the exercise cards — the focused card and the one up next expanded into
/// set tables, the rest as rows. Right: the session rail. Rest days, skipped days, free days and the first run get
/// their own quiet panels. OWNER: Engineer A (Today + Exercise sheet).
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        if app.isFirstRun {
            TodayFirstRun()
        } else {
            let plan = app.todayPlan
            let items = app.todayVisibleItems(plan)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    TodayHeader(plan: plan, items: items)
                        .padding(.horizontal, 32)
                        .padding(.top, 22)
                        .padding(.bottom, 16)
                    ScrollView {
                        VStack(spacing: 10) {
                            TodayDayPanel(plan: plan, hasItems: !items.isEmpty)
                            cards(items, finished: plan.status == .done || plan.status == .restDone)
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                TodaySessionRail(plan: plan, items: items)
            }
            .background(theme.bgColor)
        }
    }

    /// While a session runs (or before one starts): the focused card and the one up next are expanded. Once the day
    /// is finished every card is a summary row, with no focus and no "Up next", until one is tapped to edit it (or the
    /// session is resumed).
    @ViewBuilder
    private func cards(_ items: [SessionExercise], finished: Bool) -> some View {
        let focusId = finished ? app.focusedExerciseId : app.todayFocusId(items)
        let focusIndex = items.firstIndex { $0.id == focusId } ?? 0
        let upNextId = finished ? nil : items.enumerated().first { $0.offset > focusIndex && !app.todayIsFinished($0.element.exercise) }?.element.id
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            TodayExerciseCard(item: item, number: index + 1, date: app.sessionDay,
                              isFocused: item.id == focusId, isUpNext: item.id == upNextId,
                              isExpanded: item.id == focusId || item.id == upNextId)
        }
    }
}

// MARK: - Header

/// "THURSDAY, SEPTEMBER 24 · CYCLE DAY 2 OF 4" / serif "Pull" / "5 exercises + 1 extra · 20 sets · last Pull Sun
/// Sep 20, 61 min" ……… "6 of 20 sets logged".
struct TodayHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    var items: [SessionExercise]

    var body: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(eyebrow)
                Text(title)
                    .font(ThubanFont.display(34))
                    .kerning(-0.34)
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(1)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            let progress = app.todayProgress(items)
            // A skipped day has no target to count against unless something was logged on it anyway.
            if !items.isEmpty, plan.status != .skipped || progress.logged > 0 {
                HStack(spacing: 0) {
                    Text(String(progress.logged))
                        .font(ThubanFont.mono(13.5, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                    Text(" of \(progress.planned) sets logged")
                        .font(.system(size: 13.5))
                        .foregroundStyle(theme.inkDimColor)
                }
                .padding(.bottom, 2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var eyebrow: String {
        var parts = [GymFormat.longDay(app.sessionDay)]
        switch plan.status {
        case .skipped:
            parts.append("Skipped")
        case .swapped:
            parts.append(plan.plannedWorkout.map { "Swapped for \($0.name)" } ?? "Swapped")
        case .done, .restDone:
            parts.append("Done")
        default:
            if let position = app.cyclePosition(on: app.sessionDay) {
                parts.append("Cycle day \(position.index + 1) of \(position.count)")
            } else if plan.status == .inProgress, let planned = plan.plannedWorkout, planned.id != plan.workout?.id {
                parts.append("Swapped for \(planned.name)")
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
            let planned = plan.workout.map { "\($0.name) was planned" } ?? "Skipped"
            return [planned, plan.override?.note].compactMap { $0 }.joined(separator: " · ")
        }
        guard let workout = plan.workout else {
            return items.isEmpty ? "Your plan has nothing for today." : "\(items.count) exercise\(items.count == 1 ? "" : "s") pulled in"
        }
        if workout.isRest {
            let planned = PlanEngine.plannedSetCount(items)
            return items.isEmpty ? "Recovery day" : "Recovery day · \(items.count) extra\(items.count == 1 ? "" : "s") · \(planned) sets"
        }
        let own = items.filter { !$0.isExtra }.count
        let extras = items.count - own
        var parts: [String] = []
        var count = "\(own) exercise\(own == 1 ? "" : "s")"
        if extras > 0 { count += " + \(extras) extra\(extras == 1 ? "" : "s")" }
        parts.append(count)
        let planned = PlanEngine.plannedSetCount(items)
        if planned > 0 { parts.append("\(planned) sets") }
        if let last = app.todayLastCompletion(of: workout.id) {
            var text = "last \(workout.name) \(GymFormat.shortDay(last.date))"
            if let minutes = last.durationMinutes { text += ", \(GymFormat.minutes(minutes))" }
            parts.append(text)
        } else if !workout.isRest {
            parts.append("first \(workout.name)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Day states

/// A quiet card above (or instead of) the exercise list for days without a normal session: rest, skipped,
/// nothing planned, an empty flex day.
struct TodayDayPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    var hasItems: Bool
    @State private var picking = false
    @State private var adding = false

    var body: some View {
        switch plan.status {
        case .skipped:
            panel(icon: .skip, title: "Skipped today",
                  message: skippedMessage) {
                Button("Undo skip") { app.clearOverride(date: app.today) }
                    .buttonStyle(SecondaryButtonStyle(height: 32))
                trainAnyway
            }
        case .rest, .restDone:
            panel(icon: .moon, title: plan.status == .restDone ? "Rest day, done" : "Rest day",
                  message: restMessage) {
                trainAnyway
                addExercise
            }
        case .empty:
            if !hasItems {
                panel(icon: .today, title: "Nothing planned today",
                      message: app.plan.cycle.isEmpty && app.plan.weekly.isEmpty
                        ? "Set up a weekly plan or a cycle, or start any workout now."
                        : "Your plan has a free day. Start any workout, or pull in a few exercises.") {
                    trainAnyway
                    addExercise
                    Button("Open plan") { app.section = .plan }
                        .buttonStyle(GhostButtonStyle(height: 32, tinted: true, horizontalPadding: 12))
                }
            }
        default:
            if !hasItems, let workout = plan.workout {
                panel(icon: .workouts, title: workout.kind == .flex ? "Log anything" : "No exercises yet",
                      message: workout.kind == .flex
                        ? "\(workout.name) is a flex day: pull in exercises from any workout."
                        : "\(workout.name) has no exercises. Add some in Workouts, or pull some in for today.") {
                    addExercise
                    Button("Edit \(workout.name)") {
                        app.selectedWorkoutId = workout.id
                        app.section = .workouts
                    }
                    .buttonStyle(GhostButtonStyle(height: 32, tinted: true, horizontalPadding: 12))
                }
            }
        }
    }

    private var skippedMessage: String {
        guard let planned = plan.workout else { return "Nothing counts against you today." }
        if let next = app.nextDate(of: planned.id, after: app.today) {
            return "\(planned.name) was planned. It moves to \(GymFormat.shortDay(next)); the cycle does not advance."
        }
        return "\(planned.name) was planned. The cycle does not advance on a skipped day."
    }

    private var restMessage: String {
        if plan.status == .restDone { return "Recovery counts. Tomorrow picks up the cycle." }
        return app.isCycle ? "It is marked done by itself at midnight and the cycle moves on." : "Nothing to log today."
    }

    private var trainAnyway: some View {
        Button { picking = true } label: {
            HStack(spacing: 7) { Icon(.play, size: 15); Text("Train anyway") }
        }
        .buttonStyle(PrimaryButtonStyle(height: 32))
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            TodayWorkoutPicker(title: "Train today", subtitle: "Starts the session now. The plan records a swap.") { id in
                picking = false
                app.startSession(workoutId: id)
            }
        }
    }

    private var addExercise: some View {
        Button { adding = true } label: {
            HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add exercise") }
        }
        .buttonStyle(SecondaryButtonStyle(height: 32))
        .popover(isPresented: $adding, arrowEdge: .bottom) {
            TodayAddExercisePicker { adding = false }
        }
    }

    private func panel<Actions: View>(icon: IconName, title: String, message: String, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Icon(icon, size: 22)
                .foregroundStyle(theme.brassInkColor)
                .frame(width: 40, height: 40)
                .background(theme.accentTintColor, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) { actions() }.padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}

// MARK: - First run

/// Nothing local and never imported: offer the Atlas import (Settings → Import) or starting from scratch.
struct TodayFirstRun: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            AppArtView(size: 56, theme: theme)
                .padding(.bottom, 6)
            Text("Welcome to Thuban Gym")
                .font(ThubanFont.display(30))
                .foregroundStyle(theme.inkColor)
            Text("Bring over your workouts, plan and history from Atlas, or start from an empty log. Everything stays on this Mac.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkDimColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            HStack(spacing: 10) {
                ImportFromAtlasButton()
                Button { app.section = .workouts } label: {
                    HStack(spacing: 7) { Icon(.plus, size: 15); Text("Create a workout") }
                }
                .buttonStyle(.thubanSecondary)
            }
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
    }
}
