import SwiftUI
import ThubanGymCore

/// Today's actions on the right of the section bar: Skip today · Swap workout | Add exercise. Skip and swap are
/// one-day overrides — they never move the cycle pointer. OWNER: Engineer A.
struct TodayToolbar: View {
    @Environment(AppModel.self) private var app
    @State private var swapping = false
    @State private var adding = false

    var body: some View {
        let plan = app.todayPlan
        let running = app.activeSession != nil
        let done = plan.status == .done || plan.status == .restDone
        Group {
            if plan.status == .skipped {
                ToolbarButton("Undo skip", icon: .skip) { app.clearOverride(date: app.today) }
                    .help("Put today's planned workout back")
            } else {
                ToolbarButton("Skip today", icon: .skip) { app.skip() }
                    .disabled(running || done || plan.workout == nil)
                    .help(running ? "Finish or discard the running session first" : "Skip today; the cycle waits for tomorrow")
            }
            ToolbarButton("Swap workout", icon: .swap) { swapping = true }
                .disabled(running || done || app.workouts.isEmpty)
                .help(running ? "Finish or discard the running session first" : "Do a different workout today")
                .popover(isPresented: $swapping, arrowEdge: .bottom) {
                    TodayWorkoutPicker(title: "Swap today's workout",
                                       subtitle: "The cycle position stays where it is.",
                                       currentId: plan.status == .skipped ? nil : plan.workout?.id,
                                       plannedId: plan.override == nil ? plan.workout?.id : plan.plannedWorkout?.id) { id in
                        swapping = false
                        let plannedId = plan.override == nil ? plan.workout?.id : plan.plannedWorkout?.id
                        if id == plannedId { app.clearOverride(date: app.today) } else { app.swap(to: id) }
                        app.focusedExerciseId = nil
                    }
                }
            ToolbarDivider()
            ToolbarButton("Add exercise", icon: .plus, kind: .secondary) { adding = true }
                .disabled(app.data.exercises.isEmpty)
                .help("Pull an exercise from another workout into today")
                .popover(isPresented: $adding, arrowEdge: .bottom) {
                    TodayAddExercisePicker { adding = false }
                }
        }
    }
}

// MARK: - Workout picker (Swap / Train anyway)

/// A popover list of workouts: name, kind / exercise count, and a mark on the current and planned ones.
struct TodayWorkoutPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var title: String
    var subtitle: String
    var currentId: String?
    var plannedId: String?
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(ThubanFont.display(17)).foregroundStyle(theme.inkColor)
                Text(subtitle).font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Hairline()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(app.workouts) { workout in
                        row(workout)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 300)
        .background(theme.panelColor)
    }

    private func row(_ workout: Workout) -> some View {
        let count = app.exercises(in: workout.id).count
        let detail: String = workout.kind == .training ? "\(count) exercise\(count == 1 ? "" : "s")" : workout.kind.label
        return TodayPickerRow(action: { onPick(workout.id) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkColor)
                    Text(detail).font(.system(size: 12)).foregroundStyle(theme.inkFaintColor)
                }
                Spacer(minLength: 8)
                if workout.id == currentId {
                    Chip("Today", kind: .accent)
                } else if workout.id == plannedId {
                    Chip("Planned", kind: .neutral)
                }
            }
        }
        .accessibilityLabel("\(workout.name), \(detail)")
    }
}

/// A full-width hover row inside a popover list.
struct TodayPickerRow<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var action: () -> Void
    @ViewBuilder var content: () -> Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Add exercise (extras)

/// Search every workout's exercises and pull one into today (`addExtra`). Exercises already in today's session
/// are left out.
struct TodayAddExercisePicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var onDone: () -> Void
    @State private var query = ""

    var body: some View {
        let inSession = Set(app.sessionExercises(on: app.sessionDay).map(\.id))
        let groups = app.todayExtraCandidates(excluding: inSession).compactMap { group -> (workout: Workout, exercises: [Exercise])? in
            let q = query.trimmingCharacters(in: .whitespaces).lowercased()
            let list = q.isEmpty ? group.exercises : group.exercises.filter { $0.name.lowercased().contains(q) || group.workout.name.lowercased().contains(q) }
            return list.isEmpty ? nil : (group.workout, list)
        }
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add to today").font(ThubanFont.display(17)).foregroundStyle(theme.inkColor)
                    Text("Pull an exercise from another workout into this session only.")
                        .font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor)
                }
                SearchField(text: $query, placeholder: "Search exercises")
            }
            .padding(14)
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if groups.isEmpty {
                        Text(query.isEmpty ? "Every exercise is already in today's session." : "No exercise matches “\(query)”.")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.inkDimColor)
                            .padding(12)
                    }
                    ForEach(groups, id: \.workout.id) { group in
                        Eyebrow(group.workout.name)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 2)
                        ForEach(group.exercises) { exercise in
                            TodayPickerRow(action: { add(exercise) }) {
                                HStack(spacing: 8) {
                                    Text(exercise.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.inkColor)
                                    if exercise.unilateral { Chip("L / R", kind: .signal) }
                                    Spacer(minLength: 8)
                                    if let spec = exercise.targetSpec { TodayMonoChip(text: spec.display) }
                                }
                            }
                            .accessibilityLabel("Add \(exercise.name) from \(group.workout.name)")
                        }
                    }
                }
                .padding(6)
            }
            .frame(height: 380)
        }
        .frame(width: 340)
        .background(theme.panelColor)
    }

    private func add(_ exercise: Exercise) {
        app.addExtra(exerciseId: exercise.id)
        app.focusedExerciseId = exercise.id
        onDone()
    }
}
