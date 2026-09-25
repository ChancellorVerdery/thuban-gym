import SwiftUI
import UniformTypeIdentifiers
import ThubanGymCore

/// "CYCLE ORDER": the cycle's slots in order. Drag (or use the context menu / accessibility actions) to reorder; the pointer stays
/// on its slot. "Add workout" appends a slot; each row can be made "next up" or removed. The footer explains the
/// pointer rule with the user's own workouts.
struct PlanCycleEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var addingWorkout = false
    @State private var dropTarget: Int?

    var body: some View {
        let cycle = app.plan.cycle
        let pointer = app.plan.normalizedPosition
        PlanCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("Cycle order")
                    Text(subtitle(cycle: cycle, pointer: pointer))
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                }
                Spacer(minLength: 8)
                Button { addingWorkout = true } label: {
                    HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add workout") }
                }
                .buttonStyle(SecondaryButtonStyle(height: 30))
                .popover(isPresented: $addingWorkout, arrowEdge: .bottom) {
                    PlanWorkoutPicker(title: "Add to the cycle", workouts: app.workouts) { workout in
                        app.insertCycleSlot(workout.id)
                        addingWorkout = false
                    }
                    .environment(\.thubanTheme, theme)
                }
                .disabled(app.workouts.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if cycle.isEmpty {
                Text("No workouts in the cycle yet. Add one to start; the first slot becomes next up.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .thubanHairline(.top, color: theme.lineColor)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(cycle.enumerated()), id: \.offset) { index, workoutId in
                            PlanCycleRow(index: index, workoutId: workoutId, isPointer: index == pointer,
                                         isDropTarget: dropTarget == index, count: cycle.count)
                                .draggable(PlanSlotDrag.payload(index)) {
                                    Text(app.workout(workoutId)?.name ?? "Workout")
                                        .font(ThubanFont.body(14, weight: .semibold))
                                        .padding(.horizontal, 12).frame(height: 32)
                                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8))
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let from = items.first.flatMap(PlanSlotDrag.index) else { return false }
                                    app.moveCycleSlot(from: from, to: index)
                                    return true
                                } isTargeted: { targeted in
                                    if targeted { dropTarget = index } else if dropTarget == index { dropTarget = nil }
                                }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                Spacer(minLength: 0)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkDimColor)
                Text(pointerRule(cycle: cycle, pointer: pointer))
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgColor)
            .thubanHairline(.top, color: theme.lineColor)
        }
    }

    private func subtitle(cycle: [String], pointer: Int) -> String {
        guard !cycle.isEmpty, let current = app.workout(cycle[pointer]) else { return "Workouts repeat in this order." }
        return "Drag to reorder. The pointer stays on \(current.name)."
    }

    /// "Did Legs on a Pull day? The pointer jumps to Rest, after the workout you actually did."
    private func pointerRule(cycle: [String], pointer: Int) -> String {
        let generic = "Finishing a workout moves the pointer past it. Skips, swaps and extras never move it."
        guard cycle.count >= 3, let current = app.workout(cycle[pointer]) else { return generic }
        let n = cycle.count
        // The first training slot after the pointer whose workout differs from the current one.
        guard let offset = (1..<n).first(where: { step in
            let w = app.workout(cycle[(pointer + step) % n])
            return w.map { !$0.isRest && $0.id != current.id } ?? false
        }), let other = app.workout(cycle[(pointer + offset) % n]),
              let after = app.workout(cycle[(pointer + offset + 1) % n]) else { return generic }
        return "Did \(other.name) on a \(current.name) day? The pointer jumps to \(after.name), after the workout you actually did."
    }
}

/// Drag payload for a cycle slot ("plan-slot:2").
enum PlanSlotDrag {
    static let prefix = "plan-slot:"
    static func payload(_ index: Int) -> String { prefix + String(index) }
    static func index(_ payload: String) -> Int? {
        guard payload.hasPrefix(prefix) else { return nil }
        return Int(payload.dropFirst(prefix.count))
    }
}

/// One slot: handle, number, name + summary, then Next up / Done … / the projected date. Hover shows "Make next"
/// and remove.
struct PlanCycleRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var index: Int
    var workoutId: String
    var isPointer: Bool
    var isDropTarget: Bool
    var count: Int
    @State private var hovering = false

    var body: some View {
        let workout = app.workout(workoutId)
        HStack(spacing: 12) {
            Icon(.dragHandle, size: 16)
                .foregroundStyle(theme.inkFaintColor)
                .frame(width: 22, height: 30)
                .accessibilityHidden(true)
            Text(String(index + 1))
                .font(ThubanFont.mono(13))
                .foregroundStyle(theme.inkFaintColor)
                .frame(width: 16, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(workout?.name ?? "Missing workout")
                    .font(.system(size: 15 * textScale, weight: .semibold))
                    .foregroundStyle(workout == nil ? theme.inkFaintColor : theme.inkColor)
                Text(workout.map { app.workoutSummary($0) } ?? "Deleted; remove this slot")
                    .font(.system(size: 12.5 * textScale))
                    .foregroundStyle(theme.inkDimColor)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if hovering {
                if !isPointer {
                    PlanRowButton(title: "Make next", accessibility: "Make \(workout?.name ?? "this slot") next up", tinted: true) {
                        app.setCyclePosition(index)
                    }
                }
                IconButton(.close, label: "Remove \(workout?.name ?? "slot") from the cycle", size: 28, iconSize: 14) {
                    app.removeCycleSlot(at: index)
                }
            }
            trailing(workout)
        }
        .padding(.leading, 10)
        .padding(.trailing, 16)
        .frame(height: 60)
        .background(isPointer ? theme.accentTintColor : (hovering ? theme.panel2Color.opacity(0.5) : .clear))
        .overlay(alignment: .leading) {
            Rectangle().fill(isPointer ? theme.accentColor : .clear).frame(width: 3)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(isDropTarget ? theme.accentColor : theme.lineColor).frame(height: isDropTarget ? 2 : ThubanMetrics.hairline)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if !isPointer { Button("Make next up") { app.setCyclePosition(index) } }
            Button("Move up") { app.moveCycleSlot(from: index, to: index - 1) }.disabled(index == 0)
            Button("Move down") { app.moveCycleSlot(from: index, to: index + 1) }.disabled(index == count - 1)
            Divider()
            Button("Remove from cycle") { app.removeCycleSlot(at: index) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slot \(index + 1), \(workout?.name ?? "missing workout")\(isPointer ? ", next up" : "")")
        .accessibilityAction(named: "Move up") { app.moveCycleSlot(from: index, to: index - 1) }
        .accessibilityAction(named: "Move down") { app.moveCycleSlot(from: index, to: index + 1) }
        .accessibilityAction(named: "Make next up") { app.setCyclePosition(index) }
        .accessibilityAction(named: "Remove from cycle") { app.removeCycleSlot(at: index) }
    }

    @ViewBuilder
    private func trailing(_ workout: Workout?) -> some View {
        if let workout {
            if isPointer {
                Text(nextUpText(workout))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.onAccentColor)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(theme.accentColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            } else if workout.isRest {
                Chip("Rest")
            } else if index < app.plan.normalizedPosition, let done = app.lastDone(workout.id, within: 14) {
                Text("Done \(doneLabel(done))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.posTextColor)
            } else if let next = app.nextDate(of: workout.id, after: app.today.adding(days: -1)) {
                Text(next == app.today ? "Today" : next.planShort)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            }
        }
    }

    private func nextUpText(_ workout: Workout) -> String {
        if app.activeSession?.workoutId == workout.id { return "Next up · in progress" }
        if app.todayPlan.workout?.id == workout.id, app.todayPlan.status == .planned { return "Next up · today" }
        return "Next up"
    }

    private func doneLabel(_ date: DayKey) -> String {
        if date == app.today { return "today" }
        return date.days(to: app.today) < 7 ? date.weekday.short : GymFormat.monthDay(date)
    }
}

/// A popover list of workouts to pick one ("Add to the cycle", the weekly day picker, Swap a day).
struct PlanWorkoutPicker: View {
    @Environment(\.thubanTheme) private var theme
    var title: String
    var workouts: [Workout]
    var allowsNone = false
    var selectedId: String?
    var onPick: (Workout?) -> Void

    init(title: String, workouts: [Workout], allowsNone: Bool = false, selectedId: String? = nil, onPick: @escaping (Workout?) -> Void) {
        self.title = title
        self.workouts = workouts
        self.allowsNone = allowsNone
        self.selectedId = selectedId
        self.onPick = onPick
    }

    /// Non-optional convenience.
    init(title: String, workouts: [Workout], onPick: @escaping (Workout) -> Void) {
        self.init(title: title, workouts: workouts, allowsNone: false, selectedId: nil) { if let w = $0 { onPick(w) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(title).padding(.horizontal, 10).padding(.bottom, 6)
            ForEach(workouts) { workout in
                row(workout.name, kind: workout.kind, selected: workout.id == selectedId) { onPick(workout) }
            }
            if allowsNone {
                Hairline().padding(.vertical, 4)
                row("Nothing (rest)", kind: nil, selected: selectedId == nil) { onPick(nil) }
            }
        }
        .padding(10)
        .frame(width: 240)
        .background(theme.panelColor)
    }

    private func row(_ name: String, kind: WorkoutKind?, selected: Bool, action: @escaping () -> Void) -> some View {
        PlanPickerRow(name: name, kind: kind, selected: selected, action: action)
    }
}

private struct PlanPickerRow: View {
    @Environment(\.thubanTheme) private var theme
    var name: String
    var kind: WorkoutKind?
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(name).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                Spacer(minLength: 4)
                if kind == .rest { Chip("Rest") }
                if kind == .flex { Chip("Flex", kind: .signal) }
                if selected { Icon(.check, size: 14).foregroundStyle(theme.brassInkColor) }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
