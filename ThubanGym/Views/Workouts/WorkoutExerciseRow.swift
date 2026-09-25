import SwiftUI
import ThubanGymCore

/// One exercise in the table: handle, name (quiet field), target sets × reps, L / R and Bodyweight switches, the
/// current e1RM, remove. Text fields keep local drafts and commit on Return / focus loss (one write, not one per key).
struct WorkoutExerciseRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var exercise: Exercise
    var index: Int
    var count: Int
    var isFocused: Bool
    var isDropTarget: Bool
    var autofocus: Bool
    var onFocus: () -> Void
    var onAutofocused: () -> Void
    var onDelete: () -> Void

    private enum Field: Hashable { case name, sets, reps }
    @FocusState private var focus: Field?
    @State private var name = ""
    @State private var sets = ""
    @State private var reps = ""

    var body: some View {
        WorkoutTableColumns {
            Icon(.dragHandle, size: 16)
                .foregroundStyle(theme.inkFaintColor)
                .frame(width: 26, height: 40)
                .contentShape(Rectangle())
                .draggable(WorkoutDrag.exercisePayload(exercise.id)) {
                    Text(exercise.name).font(ThubanFont.body(14, weight: .semibold))
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8))
                }
                .help("Drag to reorder")
                .accessibilityHidden(true)
        } name: {
            TextField("Exercise name", text: $name)
                .focused($focus, equals: .name)
                .planField(height: 34, quiet: true, focused: focus == .name, size: 15 * textScale, weight: .semibold)
                .onSubmit(commitName)
                .accessibilityLabel("Exercise name")
                .accessibilityValue(name)
        } target: {
            HStack(spacing: 6) {
                TextField("3", text: $sets)
                    .focused($focus, equals: .sets)
                    .planField(height: 32, mono: true, focused: focus == .sets, alignment: .trailing)
                    .frame(width: 44)
                    .onSubmit(commitTarget)
                    .accessibilityLabel("\(exercise.name) sets")
                Text("×").foregroundStyle(theme.inkFaintColor)
                TextField("8", text: $reps)
                    .focused($focus, equals: .reps)
                    .planField(height: 32, mono: true, focused: focus == .reps, alignment: .trailing)
                    .frame(width: 64)
                    .onSubmit(commitTarget)
                    .accessibilityLabel("\(exercise.name) reps")
            }
        } unilateral: {
            PlanSwitch(isOn: Binding(get: { exercise.unilateral },
                                     set: { value in app.updateExercise(exercise.id) { $0.unilateral = value } }),
                       label: "\(exercise.name) unilateral, log left and right")
        } bodyweight: {
            PlanSwitch(isOn: Binding(get: { exercise.bodyweight },
                                     set: { value in app.updateExercise(exercise.id) { $0.bodyweight = value } }),
                       label: "\(exercise.name) bodyweight, score by reps")
        } score: {
            Text(app.currentScoreText(exercise) ?? "—")
                .font(ThubanFont.mono(14))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help("Best estimated one-rep max in the latest session (Epley)")
        } remove: {
            IconButton(.trash, label: "Remove \(exercise.name)", size: 30, iconSize: 16, action: onDelete)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(isFocused ? theme.bgColor : .clear)
        .overlay(alignment: .top) {
            if isDropTarget { Rectangle().fill(theme.accentColor).frame(height: 2) }
        }
        .thubanHairline(.bottom, color: theme.lineColor)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded(onFocus))
        .contextMenu {
            Button("Show history") { app.presentedExerciseId = exercise.id }
            Button("Move up") { app.moveExercise(exercise.id, to: index - 1) }.disabled(index == 0)
            Button("Move down") { app.moveExercise(exercise.id, to: index + 1) }.disabled(index == count - 1)
            Divider()
            Button("Delete…", action: onDelete)
        }
        .accessibilityAction(named: "Move up") { app.moveExercise(exercise.id, to: index - 1) }
        .accessibilityAction(named: "Move down") { app.moveExercise(exercise.id, to: index + 1) }
        .onAppear {
            loadDrafts()
            if autofocus {
                focus = .name
                onAutofocused()
            }
        }
        .onDisappear {
            if focus == .name { commitName() }
            if focus == .sets || focus == .reps { commitTarget() }
        }
        .onChange(of: exercise) { _, _ in if focus == nil { loadDrafts() } }
        .onChange(of: focus) { old, new in
            if new != nil { onFocus() }
            if old == .name, new != .name { commitName() }
            if (old == .sets || old == .reps), new != .sets, new != .reps { commitTarget() }
        }
    }

    // MARK: Drafts

    private func loadDrafts() {
        name = exercise.name
        if let spec = exercise.targetSpec {
            sets = String(spec.sets)
            reps = spec.repsLow == spec.repsHigh ? String(spec.repsLow) : "\(spec.repsLow)–\(spec.repsHigh)"
        } else {
            sets = ""
            reps = exercise.target
        }
    }

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = exercise.name
            return
        }
        if trimmed != exercise.name { app.updateExercise(exercise.id) { $0.name = trimmed } }
    }

    /// "4" × "6-8" → "4×6–8". Unparseable input is kept as typed (free text, like Atlas allows).
    private func commitTarget() {
        let s = sets.trimmingCharacters(in: .whitespaces)
        let r = reps.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "-", with: "–")
            .replacingOccurrences(of: " ", with: "")
        let target: String
        if s.isEmpty && r.isEmpty {
            target = ""
        } else if s.isEmpty {
            target = r
        } else if r.isEmpty {
            loadDrafts() // "4 ×" with no reps: keep the old target
            return
        } else {
            target = "\(s)×\(r)"
        }
        if target != exercise.target { app.updateExercise(exercise.id) { $0.target = target } }
        loadDrafts()
    }
}

// MARK: - Side cards

/// The focused exercise, and how it is scored.
struct WorkoutExerciseNoteCard: View {
    @Environment(\.thubanTheme) private var theme
    var exercise: Exercise?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(exercise?.name ?? "Exercises")
            Text(text)
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkColor)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thubanPanel(padding: 0)
    }

    private var text: String {
        guard let exercise else { return "Add exercises with a target like 3 × 8. Progress is scored by each session's best set." }
        switch (exercise.unilateral, exercise.bodyweight) {
        case (true, true):
            return "Unilateral bodyweight: each set logs left and right reps. Its score uses the weaker side, by reps."
        case (true, false):
            return "Unilateral: each set logs left and right. Its e1RM uses the weaker side, so an imbalance never inflates progress."
        case (false, true):
            return "Bodyweight: logged without weight, shown as BW, and scored by the best set's reps."
        case (false, false):
            return "Scored by the session's best set: e1RM = weight × (1 + reps ÷ 30). Progress compares it with the first session."
        }
    }
}

/// Rest timer between sets for this workout ("2:00"); empty = the app default.
struct WorkoutRestTimerCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var workout: Workout
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Rest timer")
            HStack(spacing: 10) {
                TextField(Self.format(app.settings.restSeconds), text: $draft)
                    .focused($focused)
                    .planField(height: 32, mono: true, focused: focused, alignment: .trailing)
                    .frame(width: 80)
                    .onSubmit(commit)
                    .accessibilityLabel("Default rest between sets")
                Text("between sets, starts when you check one off")
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thubanPanel(padding: 0)
        .onAppear { draft = Self.format(app.restSeconds(for: workout.id)) }
        .onChange(of: focused) { _, now in if !now { commit() } }
        .onDisappear { if focused { commit() } }
    }

    private func commit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            app.updateWorkout(workout.id) { $0.restSeconds = nil }
        } else if let seconds = Self.parse(text) {
            app.updateWorkout(workout.id) { $0.restSeconds = seconds }
        }
        draft = Self.format(app.restSeconds(for: workout.id))
    }

    static func format(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }

    /// "2:00" / "1:30" / "90" (seconds) → seconds; nil when unreadable or out of 0…30 min.
    static func parse(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        let seconds: Int?
        switch parts.count {
        case 1: seconds = Int(parts[0])
        case 2:
            guard let m = Int(parts[0].isEmpty ? "0" : parts[0]), let s = Int(parts[1]), (0..<60).contains(s) else { return nil }
            seconds = m * 60 + s
        default: seconds = nil
        }
        guard let seconds, (0...1800).contains(seconds) else { return nil }
        return seconds
    }
}

/// "USED IN": cycle slots, weekly days and upcoming swaps that name this workout.
struct WorkoutUsedInCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var workout: Workout

    var body: some View {
        let usages = app.usages(of: workout.id)
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Used in")
            if usages.isEmpty {
                Text("Not in the plan. Add it to the cycle or a weekday on the Plan screen.")
                    .font(ThubanFont.body(14))
                    .foregroundStyle(theme.inkDimColor)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                PlanFlowLayout(spacing: 6) {
                    ForEach(Array(usages.enumerated()), id: \.offset) { _, usage in chip(usage) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .thubanPanel(padding: 0)
    }

    private func chip(_ usage: WorkoutUsage) -> Chip {
        let active = app.plan.type
        switch usage {
        case .cycle(let index): return Chip("Cycle, day \(index + 1)", kind: active == .cycle ? .warn : .neutral)
        case .weekly(let day): return Chip("Weekly, \(day.short)", kind: active == .weekly ? .warn : .neutral)
        case .override(let date): return Chip("Swap target \(GymFormat.monthDay(date))", kind: .neutral)
        }
    }
}
