import SwiftUI
import ThubanGymCore

/// Workouts section (Workouts.dc.html). OWNER: Engineer B (Plan + Workouts).
///
/// A 300 pt library on the left (drag to reorder, + for a new workout) and the editor for `app.selectedWorkoutId`
/// on the right: name and day type, the exercise table (target, L / R, bodyweight, current e1RM), and the side cards
/// (the focused exercise, rest timer, where the workout is used).
struct WorkoutsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    /// A workout created from the sidebar: its editor focuses the name field once.
    @State private var renameRequest: String?

    var body: some View {
        HStack(spacing: 0) {
            WorkoutsSidebar(selectedId: selected?.id) { created in renameRequest = created }
                .frame(width: 300)
            Group {
                if let workout = selected {
                    WorkoutEditor(workout: workout, focusName: renameRequest == workout.id) { renameRequest = nil }
                        .id(workout.id)
                } else {
                    EmptyState(icon: .workouts, title: "No workouts yet",
                               message: "Create a workout, then add its exercises. Or import your Atlas workouts from Settings.") {
                        HStack(spacing: 8) {
                            Button("New workout") {
                                let workout = app.addWorkout(name: "New workout")
                                app.selectedWorkoutId = workout.id
                                renameRequest = workout.id
                            }
                            .buttonStyle(.thubanPrimary)
                            Button("Import from Atlas") { app.openSettings(.importAtlas) }
                                .buttonStyle(.thubanSecondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.bgColor)
        .onAppear(perform: ensureSelection)
        .onChange(of: app.workouts.map(\.id)) { _, _ in ensureSelection() }
    }

    /// The editor's workout: the selection, else the first one.
    private var selected: Workout? { app.workout(app.selectedWorkoutId) ?? app.workouts.first }

    private func ensureSelection() {
        if app.workout(app.selectedWorkoutId) == nil { app.selectedWorkoutId = app.workouts.first?.id }
    }
}

/// Helpers the Workouts views share.
extension AppModel {
    /// 1-based cycle positions of a workout ("cycle 2", "cycle 1, 3").
    func cycleSlots(of workoutId: String) -> [Int] {
        plan.cycle.enumerated().filter { $0.element == workoutId }.map { $0.offset + 1 }
    }

    /// Deletes a workout and moves the selection to its neighbour.
    func deleteWorkoutKeepingSelection(_ id: String) {
        let index = workouts.firstIndex { $0.id == id } ?? 0
        deleteWorkout(id)
        if selectedWorkoutId == id || workout(selectedWorkoutId) == nil {
            selectedWorkoutId = workouts.isEmpty ? nil : workouts[min(index, workouts.count - 1)].id
        }
    }

    /// "Its 5 exercises go too, and it leaves cycle slot 2 and Tuesday. Logged history stays."
    func deleteWorkoutMessage(_ workout: Workout) -> String {
        let count = exercises(in: workout.id).count
        var places: [String] = []
        let slots = cycleSlots(of: workout.id)
        if !slots.isEmpty { places.append(slots.count == 1 ? "cycle slot \(slots[0])" : "cycle slots \(slots.map(String.init).joined(separator: ", "))") }
        let days = Weekday.allCases.filter { plan.weeklyWorkoutId($0) == workout.id }.map(\.name)
        if !days.isEmpty { places.append("the weekly plan (\(days.joined(separator: ", ")))") }
        var text = count == 0 ? "" : "Its \(Self.plural(count, "exercise")) go too. "
        if !places.isEmpty { text += "It leaves \(places.joined(separator: " and ")). " }
        return text + "Logged sets and past sessions stay in your history."
    }
}

/// Confirms deleting a workout (toolbar and sidebar share it).
struct WorkoutDeleteConfirmation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var workout: Workout?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \(workout?.name ?? "workout")?",
            isPresented: Binding(get: { workout != nil }, set: { if !$0 { workout = nil } }),
            titleVisibility: .visible,
            presenting: workout
        ) { target in
            Button("Delete \(target.name)", role: .destructive) { app.deleteWorkoutKeepingSelection(target.id) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text(app.deleteWorkoutMessage(target))
        }
    }
}

extension View {
    func confirmsWorkoutDelete(_ workout: Binding<Workout?>) -> some View {
        modifier(WorkoutDeleteConfirmation(workout: workout))
    }
}
