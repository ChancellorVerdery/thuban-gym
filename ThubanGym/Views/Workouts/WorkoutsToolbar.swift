import SwiftUI
import ThubanGymCore

/// Workouts' section-bar actions on `app.selectedWorkoutId` (else the first workout): "Duplicate" · "Delete" (in
/// the negative tone; confirms first). OWNER: Engineer B.
struct WorkoutsToolbar: View {
    @Environment(AppModel.self) private var app
    @State private var pendingDelete: Workout?

    var body: some View {
        let workout = app.workout(app.selectedWorkoutId) ?? app.workouts.first
        PlanToneToolbarButton(label: "Duplicate", icon: .file) {
            guard let workout, let copy = app.duplicateWorkout(workout.id) else { return }
            app.selectedWorkoutId = copy.id
        }
        .disabled(workout == nil)
        .help(workout.map { "Duplicate \($0.name) with its exercises" } ?? "Duplicate")
        PlanToneToolbarButton(label: "Delete", icon: .trash, destructive: true) { pendingDelete = workout }
            .disabled(workout == nil)
            .help(workout.map { "Delete \($0.name)" } ?? "Delete")
            .confirmsWorkoutDelete($pendingDelete)
    }
}
