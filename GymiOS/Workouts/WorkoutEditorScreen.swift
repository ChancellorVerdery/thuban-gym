import SwiftUI
import ThubanGymCore

/// Workout editor (board WorkoutEditor): name, type, the exercises (drag to reorder, swipe to remove, tap to edit),
/// Add exercise, and the rest between sets (±15 s).
struct WorkoutEditorScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var workoutId: String

    @State private var name = ""
    @State private var editing: ExerciseEdit?
    @FocusState private var nameFocused: Bool

    var body: some View {
        if let workout = app.workout(workoutId) {
            content(workout)
        } else {
            Text("This workout was deleted.").font(.subheadline).foregroundStyle(theme.inkDimColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity).phoneScreen(theme)
        }
    }

    private func content(_ workout: Workout) -> some View {
        let exercises = app.exercises(in: workoutId)
        let sets = exercises.reduce(0) { $0 + ($1.targetSpec?.sets ?? 0) }
        return List {
            Section {
                HStack(spacing: 12) {
                    Text("Name").foregroundStyle(theme.inkDimColor).frame(width: 84, alignment: .leading)
                    TextField("Workout name", text: $name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.inkColor)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(commitName)
                }
                .frame(minHeight: 44)
                .listRowBackground(theme.panelColor)
                HStack(spacing: 12) {
                    Text("Type").foregroundStyle(theme.inkDimColor).frame(width: 84, alignment: .leading)
                    PhoneSegmented(options: WorkoutKind.allCases.map { ($0, $0.label) },
                                   selection: Binding(get: { workout.kind }, set: { kind in app.updateWorkout(workoutId) { $0.kind = kind } }),
                                   accessibilityLabel: "Workout type", height: 38)
                }
                .frame(minHeight: 52)
                .listRowBackground(theme.panelColor)
            }

            Section {
                ForEach(exercises) { exercise in
                    Button { editing = ExerciseEdit(id: exercise.id) } label: {
                        exerciseRow(exercise)
                    }
                    .listRowBackground(theme.panelColor)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { app.deleteExercise(exercise.id) } label: {
                            Label { Text("Remove") } icon: { Image(uiImage: TabIcon.image(.trash)) }
                        }
                        .tint(theme.negColor)
                    }
                }
                .onMove { from, to in
                    guard let first = from.first else { return }
                    let id = exercises[first].id
                    app.moveExercise(id, to: to > first ? to - 1 : to)
                }
                Button { editing = ExerciseEdit(id: nil) } label: {
                    HStack(spacing: 12) {
                        Icon(.plusCircle, size: 22)
                        Text("Add exercise").font(.body.weight(.semibold))
                    }
                    .foregroundStyle(theme.brassInkColor)
                    .frame(minHeight: 44)
                }
                .listRowBackground(theme.panelColor)
            } header: {
                HStack {
                    Eyebrow(sets > 0 ? "Exercises · \(sets) sets" : "Exercises")
                    Spacer()
                    Text("Drag to reorder").font(.subheadline).foregroundStyle(theme.inkFaintColor)
                }
                .textCase(nil)
                .padding(.horizontal, -16)
            } footer: {
                Text("Removing an exercise keeps its history. L / R exercises log each side; their e1RM uses the weaker side.")
                    .font(.footnote).foregroundStyle(theme.inkDimColor)
            }

            Section {
                HStack(spacing: 12) {
                    Text("Rest between sets").foregroundStyle(theme.inkColor)
                    Spacer(minLength: 4)
                    Text(PhoneFormat.rest(app.restSeconds(for: workoutId)))
                        .font(PhoneFont.mono(17, weight: .semibold)).foregroundStyle(theme.inkColor)
                        .monospacedDigit()
                    restStepper
                }
                .frame(minHeight: 52)
                .listRowBackground(theme.panelColor)
                .accessibilityElement(children: .contain)
            } footer: {
                Text(workout.restSeconds == nil ? "Uses the default rest from Settings." : "This workout's own rest timer.")
                    .font(.footnote).foregroundStyle(theme.inkDimColor)
            }
        }
        .phoneList(theme)
        .phoneScreen(theme)
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commitName(); dismiss() }.fontWeight(.semibold)
            }
        }
        .onAppear { name = workout.name }
        .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
        .onDisappear(perform: commitName)
        .sheet(item: $editing) { edit in
            ExerciseEditSheet(workoutId: workoutId, exerciseId: edit.id)
                .phoneChrome()
        }
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                    if exercise.bodyweight { PhoneChip("Bodyweight", kind: .neutral) }
                    if exercise.unilateral { PhoneChip("L / R", kind: .signal) }
                }
                Text(detail(exercise)).font(PhoneFont.mono(13)).foregroundStyle(theme.inkFaintColor)
            }
            Spacer(minLength: 4)
            Icon(.lines, size: 18).foregroundStyle(theme.inkFaintColor).accessibilityHidden(true)
        }
        .frame(minHeight: 50)
        .contentShape(Rectangle())
        .accessibilityHint("Edit the exercise. Drag to reorder")
    }

    private func detail(_ exercise: Exercise) -> String {
        var parts = [exercise.targetSpec?.display ?? (exercise.target.isEmpty ? "No target" : exercise.target)]
        if let target = app.nextTarget(exerciseId: exercise.id), target.increase, let kg = target.weightKg {
            parts.append("next \(app.weightWithUnit(kg))")
        }
        return parts.joined(separator: " · ")
    }

    private var restStepper: some View {
        HStack(spacing: 0) {
            Button { setRest(-15) } label: { Icon(.minus, size: 18).frame(width: 48, height: 38).contentShape(Rectangle()) }
                .accessibilityLabel("15 seconds less rest")
            Rectangle().fill(theme.line2Color).frame(width: 1, height: 20)
            Button { setRest(15) } label: { Icon(.plus, size: 18).frame(width: 48, height: 38).contentShape(Rectangle()) }
                .accessibilityLabel("15 seconds more rest")
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.inkColor)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func setRest(_ delta: Int) {
        let next = max(15, min(600, app.restSeconds(for: workoutId) + delta))
        app.updateWorkout(workoutId) { $0.restSeconds = next }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != app.workout(workoutId)?.name else { return }
        app.updateWorkout(workoutId) { $0.name = trimmed }
    }
}

struct ExerciseEdit: Identifiable {
    var id: String?
    var identity: String { id ?? "new" }
}

extension ExerciseEdit: Hashable {}

/// Add or edit one exercise: name, target ("3×8", "4×6–8"), L / R, bodyweight.
struct ExerciseEditSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var workoutId: String
    var exerciseId: String?

    @State private var name = ""
    @State private var target = "3×10"
    @State private var unilateral = false
    @State private var bodyweight = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Name", text: $name).listRowBackground(theme.panelColor)
                    HStack {
                        Text("Target").foregroundStyle(theme.inkDimColor)
                        TextField("3×10", text: $target)
                            .multilineTextAlignment(.trailing)
                            .font(PhoneFont.mono(17))
                            .keyboardType(.numbersAndPunctuation)
                    }
                    .listRowBackground(theme.panelColor)
                } footer: {
                    Text(TargetSpec(target).map { "\($0.sets) sets of \($0.repsLow == $0.repsHigh ? "\($0.repsLow)" : "\($0.repsLow) to \($0.repsHigh)") reps." }
                         ?? "Write sets × reps, like 3×8 or 4×6–8.")
                        .font(.footnote).foregroundStyle(theme.inkDimColor)
                }
                Section {
                    Toggle("Left and right (L / R)", isOn: $unilateral).listRowBackground(theme.panelColor)
                    Toggle("Bodyweight", isOn: $bodyweight).listRowBackground(theme.panelColor)
                } footer: {
                    Text("Bodyweight exercises are scored by reps; add weight in the logger for a weighted set.")
                        .font(.footnote).foregroundStyle(theme.inkDimColor)
                }
                .tint(theme.accentColor)
                if let exerciseId {
                    Section {
                        Button("Delete exercise", role: .destructive) {
                            app.deleteExercise(exerciseId)
                            dismiss()
                        }
                        .foregroundStyle(theme.negTextColor)
                        .listRowBackground(theme.panelColor)
                    } footer: {
                        Text("Its logged history stays in Progress.").font(.footnote).foregroundStyle(theme.inkDimColor)
                    }
                }
            }
            .phoneList(theme)
            .phoneScreen(theme)
            .navigationTitle(exerciseId == nil ? "Add exercise" : "Edit exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(exerciseId == nil ? "Add" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationBackground(theme.bgColor)
        .onAppear {
            guard let exercise = app.exercise(exerciseId) else { return }
            name = exercise.name
            target = exercise.target
            unilateral = exercise.unilateral
            bodyweight = exercise.bodyweight
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let spec = TargetSpec(target).map { $0.repsLow == $0.repsHigh ? "\($0.sets)×\($0.repsLow)" : "\($0.sets)×\($0.repsLow)–\($0.repsHigh)" } ?? target
        if let exerciseId {
            app.updateExercise(exerciseId) {
                $0.name = trimmed
                $0.target = spec
                $0.unilateral = unilateral
                $0.bodyweight = bodyweight
            }
        } else {
            app.addExercise(to: workoutId, name: trimmed, target: spec, unilateral: unilateral, bodyweight: bodyweight)
        }
        dismiss()
    }
}
