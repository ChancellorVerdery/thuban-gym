import Foundation
import ThubanGymCore

/// Extra smoke screens for Progress (the standard walk already captures the section itself). OWNER: Engineer C.
extension SmokeScenes {
    /// The sample document while a scene shows the empty (first-run) state.
    @MainActor private static var progressSavedData: GymData?

    static var progress: [SmokeScene] {
        [
            SmokeScene(name: "progress-3m") { app in
                app.section = .progress
                app.progressRange = .threeMonths
            } cleanup: { app in
                app.progressRange = .all
            },
            SmokeScene(name: "progress-kg") { app in
                app.section = .progress
                app.setUnit(.kg)
            } cleanup: { app in
                app.setUnit(.lbs)
            },
            SmokeScene(name: "progress-dark") { app in
                app.section = .progress
                app.setAppearanceMode(.dark)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
            // The shared route: a By exercise row sets presentedExerciseId and the shell presents the sheet.
            SmokeScene(name: "progress-open-exercise", window: .sheet, settle: 1.5) { app in
                app.section = .progress
                app.presentedExerciseId = app.exerciseProgress().first { $0.exercise.name == "Barbell Row" }?.id
                    ?? app.exerciseProgress().first?.id
            } cleanup: { app in
                app.presentedExerciseId = nil
            },
            SmokeScene(name: "progress-empty") { app in
                progressSavedData = app.data
                app.replaceData(.empty)
                app.section = .progress
            } cleanup: { app in
                if let saved = progressSavedData { app.replaceData(saved) }
                progressSavedData = nil
            },
        ]
    }
}
