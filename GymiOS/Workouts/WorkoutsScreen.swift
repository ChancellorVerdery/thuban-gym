import SwiftUI
import ThubanGymCore

/// Workouts (board Workouts): search, the workouts in the cycle (with their day), the others, and a count. Tap a
/// workout to edit it; "+" adds one. Searching also finds exercises (tap → history).
struct WorkoutsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var query = ""
    @State private var adding = false
    @State private var newName = ""
    @State private var deleting: Workout?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    lists
                } else {
                    results
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .phoneScreen(theme)
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                IconButton(.plus, label: "New workout") { newName = ""; adding = true }
            }
        }
        .alert("New workout", isPresented: $adding) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                let workout = app.addWorkout(name: name)
                app.workoutsPath.append(.workout(workout.id))
            }
        }
        .confirmationDialog("Delete \(deleting?.name ?? "")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                if let id = deleting?.id { app.deleteWorkout(id) }
                deleting = nil
            }
        } message: {
            Text("Its exercises go too; their logged history stays.")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 18).foregroundStyle(theme.inkDimColor)
            TextField("Workouts and exercises", text: $query)
                .font(.body)
                .foregroundStyle(theme.inkColor)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Glyph(.close, size: 14).foregroundStyle(theme.inkFaintColor).frame(width: 32, height: 32) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous))
        .padding(.bottom, 20)
    }

    // MARK: Lists

    @ViewBuilder private var lists: some View {
        let cycleIds = app.plan.cycle
        let inCycle = app.isCycle ? cycleIds.compactMap { id in app.workout(id) } : []
        let unique = uniqued(inCycle)
        let others = app.workouts.filter { workout in !unique.contains(where: { $0.id == workout.id }) }
        if !unique.isEmpty {
            SectionHeading("In the cycle")
            Card {
                ForEach(Array(unique.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 { RowDivider() }
                    row(workout, day: (cycleIds.firstIndex(of: workout.id) ?? index) + 1)
                }
            }
            .padding(.bottom, 22)
        }
        if !others.isEmpty {
            SectionHeading(unique.isEmpty ? "Workouts" : "Other workouts")
            Card {
                ForEach(Array(others.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 { RowDivider() }
                    row(workout, day: nil)
                }
            }
        }
        if app.workouts.isEmpty {
            Text("No workouts yet. Tap + to add one, or import gym.json from the Mac in Settings.")
                .font(.subheadline).foregroundStyle(theme.inkDimColor).padding(.horizontal, 4)
        } else {
            CardFootnote(text: "\(PhoneFormat.count(app.data.exercises.count, "exercise")) across \(PhoneFormat.count(app.workouts.count, "workout")).")
        }
    }

    private func uniqued(_ list: [Workout]) -> [Workout] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }

    private func row(_ workout: Workout, day: Int?) -> some View {
        Button { app.workoutsPath.append(.workout(workout.id)) } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(workout.name).font(.body.weight(.semibold))
                            .foregroundStyle(workout.isRest ? theme.inkDimColor : theme.inkColor)
                        if workout.id == app.todayPlan.workout?.id, !workout.isRest { PhoneChip("Today", kind: .warn) }
                        if workout.kind == .rest { PhoneChip("Rest day", kind: .neutral) }
                        if workout.kind == .flex { PhoneChip("Flex", kind: .signal) }
                    }
                    Text(subtitle(workout))
                        .font(.subheadline).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let day { Text("Day \(day)").font(PhoneFont.mono(14)).foregroundStyle(theme.inkFaintColor) }
                RowChevron()
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .contextMenu {
            Button("Duplicate") { _ = app.duplicateWorkout(workout.id) }
            Button("Delete…", role: .destructive) { deleting = workout }
        }
        .accessibilityHint("Edit the workout")
    }

    private func subtitle(_ workout: Workout) -> String {
        switch workout.kind {
        case .rest: return "No targets, counts toward the cycle"
        case .flex: return "Log anything, no targets"
        case .training:
            let items = app.exercises(in: workout.id)
            var parts = [PhoneFormat.count(items.count, "exercise")]
            let sets = items.reduce(0) { $0 + ($1.targetSpec?.sets ?? 0) }
            if app.isCycle && app.plan.cycle.contains(workout.id) {
                if sets > 0 { parts.append("\(sets) sets") }
                let minutes = app.workoutDuration(workout.id)
                parts.append("\(max(5, minutes - 5))–\(minutes + 5) min")
            } else if let swap = app.upcomingOverrides.first(where: { $0.workoutId == workout.id }) {
                parts.append("swapped in \(GymFormat.shortDay(swap.date))")
            } else if let last = app.data.completions.filter({ $0.workoutId == workout.id }).map(\.date).max() {
                parts.append("last done \(GymFormat.monthDay(last))")
            } else if sets > 0 {
                parts.append("\(sets) sets")
            }
            return parts.joined(separator: " · ")
        }
    }

    // MARK: Search

    @ViewBuilder private var results: some View {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let workouts = app.workouts.filter { $0.name.lowercased().contains(needle) }
        let exercises = app.data.exercises.filter { $0.name.lowercased().contains(needle) }
        if !workouts.isEmpty {
            SectionHeading("Workouts")
            Card {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    if index > 0 { RowDivider() }
                    row(workout, day: nil)
                }
            }
            .padding(.bottom, 22)
        }
        if !exercises.isEmpty {
            SectionHeading("Exercises")
            Card {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    if index > 0 { RowDivider() }
                    Button { app.workoutsPath.append(.exercise(exercise.id)) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                                Text([app.workout(exercise.workoutId)?.name, exercise.targetSpec?.display].compactMap { $0 }.joined(separator: " · "))
                                    .font(.subheadline).foregroundStyle(theme.inkDimColor)
                            }
                            Spacer()
                            RowChevron()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(RowPressStyle())
                }
            }
        }
        if workouts.isEmpty && exercises.isEmpty {
            Text("Nothing matches “\(query)”.").font(.subheadline).foregroundStyle(theme.inkDimColor).padding(.horizontal, 4)
        }
    }
}
