import SwiftUI
import ThubanGymCore

/// The editor for one workout: header (editable serif name, history line, Day type), the exercise table, and the
/// side cards. Recreated per workout (`.id`), so its drafts never leak between workouts.
struct WorkoutEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var workout: Workout
    var focusName: Bool
    var onNameFocused: () -> Void

    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool
    @State private var focusedExerciseId: String?
    @State private var autofocusExerciseId: String?
    @State private var pendingDelete: Exercise?
    @State private var copying = false
    @State private var dropTarget: String?

    var body: some View {
        let exercises = app.exercises(in: workout.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if workout.kind == .rest && exercises.isEmpty {
                    restNote
                } else {
                    table(exercises)
                }
                sideCards(exercises)
            }
            .padding(.horizontal, 32)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.bgColor)
        .onAppear {
            nameDraft = workout.name
            if focusName {
                nameFocused = true
                onNameFocused()
            }
        }
        .onDisappear { if nameFocused { commitName() } }
        .onChange(of: workout.name) { _, new in if !nameFocused { nameDraft = new } }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "exercise")?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { exercise in
            Button("Delete \(exercise.name)", role: .destructive) {
                if focusedExerciseId == exercise.id { focusedExerciseId = nil }
                app.deleteExercise(exercise.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its logged sets stay in your history but no longer count toward the strength score.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(eyebrow)
                TextField("Workout name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(ThubanFont.display(32))
                    .foregroundStyle(theme.inkColor)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .accessibilityLabel("Workout name")
                    .padding(.vertical, 2)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(nameFocused ? theme.accentColor : .clear).frame(height: 1)
                    }
                Text(historyLine)
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                PlanControlCaption("Day type")
                SegmentedPicker(
                    selection: Binding(get: { workout.kind }, set: { kind in app.updateWorkout(workout.id) { $0.kind = kind } }),
                    options: WorkoutKind.allCases.map { SegmentOption($0, $0.label) },
                    segmentHeight: 28
                )
                .accessibilityLabel("Day type")
            }
        }
    }

    private var eyebrow: String {
        let slots = app.cycleSlots(of: workout.id)
        if !slots.isEmpty {
            return slots.count == 1 ? "Workout · position \(slots[0]) in cycle"
                : "Workout · positions \(slots.map(String.init).joined(separator: ", ")) in cycle"
        }
        let days = Weekday.allCases.filter { app.plan.weeklyWorkoutId($0) == workout.id }.map(\.short)
        if !days.isEmpty { return "Workout · weekly, \(days.joined(separator: ", "))" }
        return "Workout · not in the plan"
    }

    /// "55 sessions since Feb 4 · average 59 min · last done Sun Sep 20"
    private var historyLine: String {
        let done = app.completions(of: workout.id)
        guard let first = done.first, let last = done.last else {
            return workout.kind == .rest ? "Rest day · completes itself at midnight in a cycle" : "Not done yet"
        }
        var parts = ["\(AppModel.plural(done.count, "session")) since \(GymFormat.monthDay(first.date))"]
        if app.hasTimedSessions(workout.id) { parts.append("average \(GymFormat.minutes(app.workoutDuration(workout.id)))") }
        parts.append("last done \(last.date == app.today ? "today" : last.date.planShort)")
        return parts.joined(separator: " · ")
    }

    private func commitName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            nameDraft = workout.name
            return
        }
        if trimmed != workout.name { app.updateWorkout(workout.id) { $0.name = trimmed } }
        nameDraft = trimmed
    }

    // MARK: Table

    private func table(_ exercises: [Exercise]) -> some View {
        PlanCard {
            WorkoutTableColumns {
                Color.clear
            } name: {
                Text("Exercise")
            } target: {
                Text("Target")
            } unilateral: {
                Text("L / R")
            } bodyweight: {
                Text("Bodyweight")
            } score: {
                Text("Current e1RM").frame(maxWidth: .infinity, alignment: .trailing)
            } remove: {
                Color.clear
            }
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.8)
            .textCase(.uppercase)
            .foregroundStyle(theme.inkFaintColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .thubanHairline(.bottom, color: theme.lineColor)

            if exercises.isEmpty {
                Text(workout.kind == .flex
                     ? "A flex day logs anything. Add exercises here to suggest some."
                     : "No exercises yet. Add the first one below.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .thubanHairline(.bottom, color: theme.lineColor)
            }

            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                WorkoutExerciseRow(exercise: exercise, index: index, count: exercises.count,
                                   isFocused: focusedExerciseId == exercise.id,
                                   isDropTarget: dropTarget == exercise.id,
                                   autofocus: autofocusExerciseId == exercise.id,
                                   onFocus: { focusedExerciseId = exercise.id },
                                   onAutofocused: { autofocusExerciseId = nil },
                                   onDelete: { pendingDelete = exercise })
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first.flatMap(WorkoutDrag.exerciseId), app.exercise(id)?.workoutId == workout.id else { return false }
                        app.moveExercise(id, to: index)
                        return true
                    } isTargeted: { targeted in
                        if targeted { dropTarget = exercise.id } else if dropTarget == exercise.id { dropTarget = nil }
                    }
            }

            HStack(spacing: 8) {
                Button {
                    let added = app.addExercise(to: workout.id, name: "New exercise", target: "3×10")
                    focusedExerciseId = added.id
                    autofocusExerciseId = added.id
                } label: {
                    HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add exercise") }
                }
                .buttonStyle(PrimaryButtonStyle(height: 32))

                Button { copying = true } label: {
                    HStack(spacing: 7) { Icon(.file, size: 15); Text("Copy from another workout") }
                }
                .buttonStyle(GhostButtonStyle(height: 32, horizontalPadding: 14))
                .disabled(!app.workouts.contains { $0.id != workout.id && !app.exercises(in: $0.id).isEmpty })
                .popover(isPresented: $copying, arrowEdge: .bottom) {
                    WorkoutCopyPicker(target: workout) { copying = false }
                        .environment(app)
                        .environment(\.thubanTheme, theme)
                }

                Spacer(minLength: 8)
                Text(footerSummary(exercises))
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    /// "17 sets · about 55–65 min"
    private func footerSummary(_ exercises: [Exercise]) -> String {
        let sets = app.plannedSets(in: workout.id)
        guard sets > 0 else { return AppModel.plural(exercises.count, "exercise") }
        let minutes = app.workoutDuration(workout.id)
        let low = max(5, Int((Double(minutes) / 5).rounded()) * 5 - 5), high = low + 10
        return "\(AppModel.plural(sets, "set")) · about \(low)–\(high) min"
    }

    private var restNote: some View {
        PlanCard {
            HStack(alignment: .top, spacing: 12) {
                Icon(.moon, size: 20).foregroundStyle(theme.inkDimColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A rest day has nothing to log.")
                        .font(ThubanFont.body(15, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                    Text("In a cycle it completes itself at midnight when its day passes, and the pointer moves on. Switch the day type to Training or Flex to give it exercises.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
        }
    }

    // MARK: Side cards

    private func sideCards(_ exercises: [Exercise]) -> some View {
        HStack(alignment: .top, spacing: 18) {
            if workout.kind != .rest || !exercises.isEmpty {
                WorkoutExerciseNoteCard(exercise: noteExercise(exercises))
                WorkoutRestTimerCard(workout: workout)
            }
            WorkoutUsedInCard(workout: workout)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The focused row's exercise; else the first unilateral / bodyweight one (the most interesting rule); else the first.
    private func noteExercise(_ exercises: [Exercise]) -> Exercise? {
        if let id = focusedExerciseId, let focused = exercises.first(where: { $0.id == id }) { return focused }
        return exercises.first { $0.unilateral } ?? exercises.first { $0.bodyweight } ?? exercises.first
    }
}

/// The table's column grid: 26 | name (flex) | 150 | 96 | 96 | 120 | 32, 14 pt gaps (the artboard's grid).
struct WorkoutTableColumns<Handle: View, Name: View, Target: View, Uni: View, BW: View, Score: View, Remove: View>: View {
    @ViewBuilder var handle: () -> Handle
    @ViewBuilder var name: () -> Name
    @ViewBuilder var target: () -> Target
    @ViewBuilder var unilateral: () -> Uni
    @ViewBuilder var bodyweight: () -> BW
    @ViewBuilder var score: () -> Score
    @ViewBuilder var remove: () -> Remove

    var body: some View {
        HStack(spacing: 14) {
            handle().frame(width: 26)
            name().frame(maxWidth: .infinity, alignment: .leading)
            target().frame(width: 150, alignment: .leading)
            unilateral().frame(width: 96, alignment: .leading)
            bodyweight().frame(width: 96, alignment: .leading)
            score().frame(width: 120, alignment: .trailing)
            remove().frame(width: 32)
        }
    }
}

/// "Copy from another workout": pick a workout, its exercises are appended (new ids; logs are not copied).
struct WorkoutCopyPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var target: Workout
    var dismiss: () -> Void

    var body: some View {
        let sources = app.workouts.filter { $0.id != target.id && !app.exercises(in: $0.id).isEmpty }
        PlanWorkoutPicker(title: "Copy exercises from", workouts: sources) { source in
            app.copyExercises(from: source.id, to: target.id)
            dismiss()
        }
    }
}
