import Foundation
import ThubanGymCore

/// Extra smoke screens for Today (the standard walk already captures the section itself as 10-today, and the
/// harness captures 70-today-dark). Every scene restores the sample world in `cleanup`. OWNER: Engineer A.
extension SmokeScenes {
    static var today: [SmokeScene] {
        [
            // Mid-session: the rest timer running (1:24 of 2:00 left) after checking a set.
            SmokeScene(name: "today-resting") { app in
                app.section = .today
                TodayRestClock.shared.start(seconds: app.restSeconds(for: app.activeSession?.workoutId), at: Date().addingTimeInterval(-36))
            } cleanup: { _ in
                TodayRestClock.shared.stop()
            },
            // Focus on the unilateral exercise (L / R table) with an added row.
            SmokeScene(name: "today-unilateral") { app in
                app.section = .today
                app.focusedExerciseId = app.data.exercises.first { $0.name == "Single-arm DB Row" }?.id
                if let id = app.focusedExerciseId {
                    app.logSet(exerciseId: id, side: .left, weightKg: WeightUnit.lbs.toKilograms(60), reps: 10)
                    app.logSet(exerciseId: id, side: .right, weightKg: WeightUnit.lbs.toKilograms(60), reps: 10)
                }
            } cleanup: { app in
                if let id = app.focusedExerciseId { app.clearLogs(exerciseId: id) }
                app.focusedExerciseId = nil
            },
            // "Finish session": the rail shows the saved time and Resume session.
            SmokeScene(name: "today-finished") { app in
                app.section = .today
                app.finishSession()
            } cleanup: { app in
                app.undoFinish()
            },
            TodaySmokeState.scene("today-skipped") { app in
                app.discardSession()
                app.skip(note: "Career fair at the student union, 10–3")
            },
            TodaySmokeState.scene("today-rest-day") { app in
                app.discardSession()
                if let rest = app.workouts.first(where: { $0.isRest }) { app.swap(to: rest.id) }
                for id in app.extraIds(on: app.today) { app.removeExtra(exerciseId: id) }
            },
            TodaySmokeState.scene("today-nothing-planned") { app in
                app.discardSession()
                app.setPlanType(.weekly)
                app.setWeekly(app.today.weekday, workoutId: nil)
                for id in app.extraIds(on: app.today) { app.removeExtra(exerciseId: id) }
            },
            TodaySmokeState.scene("today-not-started") { app in
                app.discardSession()
                for item in app.sessionExercises(on: app.today) { app.clearLogs(exerciseId: item.id) }
            },
            TodaySmokeState.scene("today-first-run") { app in
                app.replaceData(.empty)
            },
        ]
    }
}

/// Scenes that rewrite the document snapshot it first and put it back afterwards (the smoke home is temporary).
enum TodaySmokeState {
    @MainActor static var snapshot: GymData?

    static func scene(_ name: String, prepare: @escaping @MainActor (AppModel) async -> Void) -> SmokeScene {
        SmokeScene(name: name) { app in
            snapshot = app.data
            app.section = .today
            app.focusedExerciseId = nil
            await prepare(app)
        } cleanup: { app in
            if let snapshot { app.replaceData(snapshot) }
            snapshot = nil
            app.focusedExerciseId = nil
        }
    }
}
