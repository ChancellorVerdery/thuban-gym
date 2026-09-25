import Foundation
import ThubanGymCore

/// Extra smoke screens for Workouts (the standard walk captures the first workout as 12-workouts). OWNER: Engineer B.
extension SmokeScenes {
    static var workouts: [SmokeScene] {
        [
            // The design's selection: Pull (bodyweight Pull-up, unilateral Single-arm DB Row).
            SmokeScene(name: "workouts-pull") { app in
                app.section = .workouts
                app.selectedWorkoutId = app.workouts.first { $0.name == "Pull" }?.id
            },
            // A brand-new, empty workout (not in the plan).
            SmokeScene(name: "workouts-new") { app in
                app.section = .workouts
                let workout = app.addWorkout(name: "Arms")
                app.selectedWorkoutId = workout.id
            } cleanup: { app in
                if let id = app.workouts.first(where: { $0.name == "Arms" })?.id { app.deleteWorkoutKeepingSelection(id) }
                app.selectedWorkoutId = nil
            },
            // A rest day.
            SmokeScene(name: "workouts-rest") { app in
                app.section = .workouts
                app.selectedWorkoutId = app.workouts.first { $0.kind == .rest }?.id
            },
            SmokeScene(name: "workouts-pull-dark") { app in
                app.section = .workouts
                app.selectedWorkoutId = app.workouts.first { $0.name == "Pull" }?.id
                app.setAppearanceMode(.dark)
            } cleanup: { app in
                app.setAppearanceMode(.light)
                app.selectedWorkoutId = nil
            },
        ]
    }
}
