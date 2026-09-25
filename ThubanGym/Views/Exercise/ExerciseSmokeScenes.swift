import Foundation
import ThubanGymCore

/// Smoke screens for the Exercise history sheet. OWNER: Engineer A (Today + Exercise sheet).
extension SmokeScenes {
    static var exercise: [SmokeScene] {
        [
            // The sheet for the design's exercise (Barbell Row in the sample data), captured from its sheet window.
            SmokeScene(name: "exercise-sheet", window: .sheet) { app in
                app.section = .progress
                app.presentedExerciseId = app.data.exercises.first { $0.name == "Barbell Row" }?.id ?? app.data.exercises.first?.id
            } cleanup: { app in
                app.presentedExerciseId = nil
            },
        ]
    }
}
