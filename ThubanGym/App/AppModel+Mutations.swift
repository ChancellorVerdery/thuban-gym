import Foundation
import ThubanGymCore

/// Every write a view may make. Each one goes through `mutate`, which saves gym.json atomically — there is no
/// separate "save" call. Dates default to `today` (set logging and extras: `sessionDay`); weights are ALWAYS kg (convert typed values with
/// `kilograms(fromDisplay:)`).
extension AppModel {
    // MARK: Logging sets

    /// Appends a set; returns its index. `weightKg` nil = bodyweight. `side` .left / .right for unilateral.
    @discardableResult
    func logSet(exerciseId: String, date: DayKey? = nil, side: Side? = nil, weightKg: Double?, reps: Int) -> Int {
        mutate { $0.logSet(exerciseId: exerciseId, date: date ?? sessionDay, side: side, weightKg: weightKg, reps: reps) }
    }

    /// Replaces set `index` (no-op when it does not exist).
    func updateSet(exerciseId: String, date: DayKey? = nil, side: Side? = nil, index: Int, weightKg: Double?, reps: Int) {
        mutate { try? $0.updateSet(exerciseId: exerciseId, date: date ?? sessionDay, side: side, index: index, weightKg: weightKg, reps: reps) }
    }

    func removeSet(exerciseId: String, date: DayKey? = nil, side: Side? = nil, index: Int) {
        mutate { $0.removeSet(exerciseId: exerciseId, date: date ?? sessionDay, side: side, index: index) }
    }

    /// Removes every set of an exercise on a day (both sides).
    func clearLogs(exerciseId: String, date: DayKey? = nil) {
        mutate { $0.clearLogs(exerciseId: exerciseId, date: date ?? sessionDay) }
    }

    // MARK: Sessions and completion

    /// Starts today's session for `workoutId` (default: today's planned workout). Doing something other than the
    /// plan records a swap override for today, so the plan and cycle projection stay truthful.
    func startSession(workoutId: String? = nil, at start: Date = Date()) {
        guard let id = workoutId ?? todayPlan.workout?.id else { return }
        lastFinish = nil
        mutate { $0.startSession(workoutId: id, date: today, at: start, today: today) }
    }

    /// Ends the running session: records the completion (start/end from the clock) and, in cycle mode, moves the
    /// pointer past the workout done. Keeps the receipt in `lastFinish` for "Resume session".
    @discardableResult
    func finishSession(at end: Date = Date()) -> FinishReceipt? {
        let receipt = mutate { $0.finishSession(at: end) }
        lastFinish = receipt
        focusedExerciseId = nil // a finished day shows every card collapsed
        return receipt
    }

    /// "Resume session": removes the completion `finishSession` made and restores the pointer and the session.
    func undoFinish() {
        guard let receipt = lastFinish else { return }
        mutate { $0.undoFinish(receipt) }
        lastFinish = nil
    }

    /// Drops the running session without a completion (logged sets stay).
    func discardSession() {
        mutate { $0.discardSession() }
    }

    /// Records a completion directly (e.g. "Mark done" on the Plan, or a rest day done by hand). Advances the cycle
    /// pointer past `workoutId` when it is in the cycle; otherwise the pointer is untouched.
    @discardableResult
    func complete(workoutId: String, date: DayKey? = nil, start: String = "", end: String = "") -> Completion {
        mutate { $0.complete(workoutId: workoutId, date: date ?? today, start: start, end: end) }
    }

    // MARK: Overrides (never move the cycle pointer; expire after 90 days)

    /// Skip a day.
    func skip(date: DayKey? = nil, note: String? = nil) {
        mutate { $0.setOverride(date: date ?? today, workoutId: nil, note: note) }
    }

    /// Do `workoutId` on a day instead of what the plan says.
    func swap(date: DayKey? = nil, to workoutId: String, note: String? = nil) {
        mutate { $0.setOverride(date: date ?? today, workoutId: workoutId, note: note) }
    }

    /// General form: `workoutId` nil = skip.
    func override(date: DayKey, workoutId: String?, note: String? = nil) {
        mutate { $0.setOverride(date: date, workoutId: workoutId, note: note) }
    }

    /// Undo a skip / swap.
    func clearOverride(date: DayKey) {
        mutate { $0.clearOverride(date: date) }
    }

    // MARK: Extras

    /// Pull an exercise from another workout into a day's session.
    func addExtra(exerciseId: String, date: DayKey? = nil) {
        mutate { $0.addExtra(exerciseId: exerciseId, date: date ?? sessionDay) }
    }

    func removeExtra(exerciseId: String, date: DayKey? = nil) {
        mutate { $0.removeExtra(exerciseId: exerciseId, date: date ?? sessionDay) }
    }

    // MARK: Plan

    func setPlanType(_ type: PlanType) {
        mutate { $0.plan.type = type }
    }

    /// Weekly plan: nil = nothing that day.
    func setWeekly(_ day: Weekday, workoutId: String?) {
        mutate { $0.setWeekly(day, workoutId: workoutId) }
    }

    /// New cycle order (duplicates allowed). The pointer follows the workout it was on.
    func setCycle(_ workoutIds: [String]) {
        mutate { $0.setCycle(workoutIds) }
    }

    /// Moves the pointer by hand ("make this next").
    func setCyclePosition(_ index: Int) {
        mutate { $0.setCyclePosition(index) }
    }

    // MARK: Workouts

    @discardableResult
    func addWorkout(name: String, kind: WorkoutKind = .training) -> Workout {
        mutate { $0.addWorkout(name: name, kind: kind) }
    }

    /// Edit name / kind / restSeconds: `app.updateWorkout(id) { $0.name = "Pull B" }`.
    func updateWorkout(_ id: String, _ change: (inout Workout) -> Void) {
        mutate { $0.updateWorkout(id, change) }
    }

    @discardableResult
    func duplicateWorkout(_ id: String) -> Workout? {
        mutate { $0.duplicateWorkout(id) }
    }

    /// Deletes a workout and its exercises; cleans the plan, overrides and extras. History stays.
    func deleteWorkout(_ id: String) {
        mutate { $0.deleteWorkout(id) }
    }

    func moveWorkout(_ id: String, to index: Int) {
        mutate { $0.moveWorkout(id, to: index) }
    }

    // MARK: Exercises

    @discardableResult
    func addExercise(to workoutId: String, name: String, target: String = "", unilateral: Bool = false, bodyweight: Bool = false) -> Exercise {
        mutate { $0.addExercise(to: workoutId, name: name, target: target, unilateral: unilateral, bodyweight: bodyweight) }
    }

    /// Edit name / target / unilateral / bodyweight / workoutId: `app.updateExercise(id) { $0.target = "4×8" }`.
    func updateExercise(_ id: String, _ change: (inout Exercise) -> Void) {
        mutate { $0.updateExercise(id, change) }
    }

    func deleteExercise(_ id: String) {
        mutate { $0.deleteExercise(id) }
    }

    func moveExercise(_ id: String, to index: Int) {
        mutate { $0.moveExercise(id, to: index) }
    }

    /// "Copy from another workout" (new ids; logs are not copied).
    @discardableResult
    func copyExercises(from source: String, to target: String, only exerciseIds: [String]? = nil) -> [Exercise] {
        mutate { $0.copyExercises(from: source, to: target, only: exerciseIds) }
    }

    // MARK: Settings stored in the document

    /// `app.updateSettings { $0.defaultDuration = 60 }` — address, hours, defaultDuration, restSeconds, unit.
    func updateSettings(_ change: (inout GymSettings) -> Void) {
        mutate { change(&$0.settings) }
    }

    /// Display unit only; stored weights never change.
    func setUnit(_ unit: WeightUnit) {
        updateSettings { $0.unit = unit }
    }
}
