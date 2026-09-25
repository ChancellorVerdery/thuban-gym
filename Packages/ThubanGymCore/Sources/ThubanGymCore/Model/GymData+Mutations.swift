import Foundation

/// Receipt from `finishSession`, enough to undo it ("Resume session").
public struct FinishReceipt: Hashable, Sendable {
    public var completion: Completion
    public var session: ActiveSession
    public var previousPosition: Int
}

/// Every write to the domain. Views never call these directly — they go through `AppModel`, which persists after
/// each call. All functions are deterministic given their `now` / `calendar` arguments (tests pass fixed values).
extension GymData {
    /// Overrides and extras older than this many days are dropped (Atlas: 90).
    public static let overrideLifetimeDays = 90

    // MARK: - Logging

    /// Appends a set to exercise + day + side and returns its index. Weight in kg (nil / ≤ 0 = bodyweight).
    @discardableResult
    public mutating func logSet(exerciseId: String, date: DayKey, side: Side? = nil, weightKg: Double?, reps: Int) -> Int {
        let set = SetEntry(weight: weightKg, reps: reps)
        if let index = logs.firstIndex(where: { $0.exerciseId == exerciseId && $0.date == date && $0.side == side }) {
            logs[index].sets.append(set)
            return logs[index].sets.count - 1
        }
        logs.append(LogEntry(exerciseId: exerciseId, date: date, side: side, sets: [set]))
        return 0
    }

    /// Replaces set `index`. Throws for a missing row / index.
    public mutating func updateSet(exerciseId: String, date: DayKey, side: Side? = nil, index: Int, weightKg: Double?, reps: Int) throws {
        guard let row = logs.firstIndex(where: { $0.exerciseId == exerciseId && $0.date == date && $0.side == side }),
              logs[row].sets.indices.contains(index) else { throw ThubanError.invalid("No set \(index + 1) to update.") }
        // Keep the set's sync identity: an edit is a change of this set, not a delete + a new set.
        var entry = SetEntry(weight: weightKg, reps: reps)
        let old = logs[row].sets[index]
        entry.id = old.id
        entry.loggedAt = old.loggedAt
        entry.updatedAt = old.updatedAt
        logs[row].sets[index] = entry
    }

    /// Removes set `index`; the row goes when its last set does. No-op for a missing set.
    public mutating func removeSet(exerciseId: String, date: DayKey, side: Side? = nil, index: Int) {
        guard let row = logs.firstIndex(where: { $0.exerciseId == exerciseId && $0.date == date && $0.side == side }),
              logs[row].sets.indices.contains(index) else { return }
        logs[row].sets.remove(at: index)
        if logs[row].sets.isEmpty { logs.remove(at: row) }
    }

    /// Removes every set of an exercise on a day (both sides).
    public mutating func clearLogs(exerciseId: String, date: DayKey) {
        logs.removeAll { $0.exerciseId == exerciseId && $0.date == date }
    }

    // MARK: - Overrides and extras

    /// Skip (`workoutId == nil`) or swap a day. Replaces any override on that date. Never touches the cycle pointer.
    public mutating func setOverride(date: DayKey, workoutId: String?, note: String? = nil) {
        overrides.removeAll { $0.date == date }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        overrides.append(PlanOverride(date: date, workoutId: workoutId, note: (trimmed?.isEmpty ?? true) ? nil : trimmed))
        overrides.sort { $0.date < $1.date }
    }

    public mutating func clearOverride(date: DayKey) {
        overrides.removeAll { $0.date == date }
    }

    /// Pulls an exercise into a day's session (no duplicates).
    public mutating func addExtra(exerciseId: String, date: DayKey) {
        guard exercise(exerciseId) != nil, !extras.contains(where: { $0.date == date && $0.exerciseId == exerciseId }) else { return }
        extras.append(PlanExtra(date: date, exerciseId: exerciseId))
    }

    public mutating func removeExtra(exerciseId: String, date: DayKey) {
        extras.removeAll { $0.date == date && $0.exerciseId == exerciseId }
    }

    // MARK: - Completion and sessions

    /// Records a completion and, in cycle mode, moves the pointer to the slot AFTER the workout actually done: the
    /// nearest occurrence of that workout at or after the pointer (cyclically). A workout that is not in the cycle
    /// leaves the pointer where it is. Skips and swaps never move it on their own.
    @discardableResult
    public mutating func complete(workoutId: String, date: DayKey, start: String = "", end: String = "",
                                  now: Date = Date(), auto: Bool = false) -> Completion {
        let completion = Completion(workoutId: workoutId, date: date, ts: (now.timeIntervalSince1970 * 1000).rounded(),
                                    start: start, end: end, auto: auto)
        completions.append(completion)
        advanceCycle(after: workoutId)
        return completion
    }

    /// Moves the pointer past the nearest occurrence of `workoutId` at or after it. No-op when not in the cycle.
    mutating func advanceCycle(after workoutId: String) {
        let cycle = plan.cycle
        guard plan.type == .cycle, !cycle.isEmpty else { return }
        let start = plan.normalizedPosition
        for step in 0..<cycle.count {
            let index = (start + step) % cycle.count
            if cycle[index] == workoutId {
                plan.position = (index + 1) % cycle.count
                return
            }
        }
    }

    /// Starts a session. When the workout is not what the plan has for `date`, a swap override is recorded so the
    /// plan shows what is being done (and the cycle slot is not consumed by it).
    public mutating func startSession(workoutId: String, date: DayKey, at start: Date, today: DayKey) {
        let planned = PlanEngine.day(self, on: date, today: today)
        let plannedId = planned.status == .skipped ? nil : planned.workout?.id
        if plannedId != workoutId || planned.status == .skipped {
            setOverride(date: date, workoutId: workoutId, note: override(on: date)?.note)
        }
        activeSession = ActiveSession(workoutId: workoutId, date: date, startedAt: start)
    }

    /// Ends the running session: records the completion (start/end from the session clock) and clears it.
    public mutating func finishSession(at end: Date, calendar: Calendar = .current) -> FinishReceipt? {
        guard let session = activeSession else { return nil }
        let previous = plan.position
        let completion = complete(workoutId: session.workoutId, date: session.date,
                                  start: ClockTime.string(from: session.startedAt, calendar: calendar),
                                  end: ClockTime.string(from: end, calendar: calendar), now: end)
        activeSession = nil
        return FinishReceipt(completion: completion, session: session, previousPosition: previous)
    }

    /// Undoes `finishSession` (the design's "Resume session"): removes that completion, restores the pointer and
    /// the running session. The only exception to completions being append-only.
    public mutating func undoFinish(_ receipt: FinishReceipt) {
        // By id: the stored copy may carry a sync stamp the receipt does not.
        if let index = completions.lastIndex(where: { $0.id == receipt.completion.id }) { completions.remove(at: index) }
        plan.position = receipt.previousPosition
        activeSession = receipt.session
    }

    /// Drops the running session without recording anything (logged sets stay).
    public mutating func discardSession() {
        activeSession = nil
    }

    // MARK: - Day rollover

    /// Run at launch and when the day changes. For every day that has passed since the last run (cycle mode): a
    /// day with no completion and no override whose slot is a rest workout auto-completes it (and advances the
    /// pointer). A missed training slot stays put. Then expires old overrides / extras. First run ever: no
    /// back-filling, just marks today.
    public mutating func rollover(to today: DayKey, now: Date = Date()) {
        if let last = lastRollover, last < today, plan.type == .cycle, !plan.cycle.isEmpty {
            // Bounded: a long absence only needs one lap of the cycle to settle.
            // `last` itself is included: when the pass ran on `last` that day had not yet passed.
            let first = max(last, today.adding(days: -(plan.cycle.count * 2 + 1)))
            for day in first.through(today.adding(days: -1)) {
                guard completions(on: day).isEmpty, override(on: day) == nil,
                      let workout = workout(plan.cycle[plan.normalizedPosition]), workout.isRest else { continue }
                complete(workoutId: workout.id, date: day, now: day.date(hour: 23, minute: 59), auto: true)
            }
        }
        pruneExpired(today: today)
        if lastRollover.map({ $0 < today }) ?? true { lastRollover = today }
    }

    /// Drops overrides / extras dated more than 90 days ago, and any that point at deleted workouts / exercises.
    public mutating func pruneExpired(today: DayKey) {
        let cutoff = today.adding(days: -GymData.overrideLifetimeDays)
        let workoutIds = Set(workouts.map(\.id))
        let exerciseIds = Set(exercises.map(\.id))
        overrides.removeAll { $0.date < cutoff || ($0.workoutId.map { !workoutIds.contains($0) } ?? false) }
        var seen = Set<String>()
        extras = extras.filter { extra in
            guard extra.date >= cutoff, exerciseIds.contains(extra.exerciseId) else { return false }
            return seen.insert(extra.id).inserted
        }
    }

    // MARK: - Workouts

    @discardableResult
    public mutating func addWorkout(name: String, kind: WorkoutKind = .training) -> Workout {
        var workout = Workout(name: name)
        workout.kind = kind
        workouts.append(workout)
        return workout
    }

    /// Edits a workout in place (`name`, `kind`, `restSeconds`). No-op for an unknown id.
    public mutating func updateWorkout(_ id: String, _ change: (inout Workout) -> Void) {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return }
        var workout = workouts[index]
        change(&workout)
        workout.id = id
        workouts[index] = workout
    }

    /// Copies a workout and its exercises (new ids) right after the original. Logs are not copied.
    @discardableResult
    public mutating func duplicateWorkout(_ id: String) -> Workout? {
        guard let index = workouts.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = workouts[index]
        copy.id = GymID.make("gw")
        copy.name = "\(copy.name) copy"
        workouts.insert(copy, at: index + 1)
        for exercise in exercises(in: id) {
            var clone = exercise
            clone.id = GymID.make("ge")
            clone.workoutId = copy.id
            exercises.append(clone)
        }
        return copy
    }

    /// Deletes a workout and its exercises; removes it from the weekly plan, the cycle (keeping the pointer on the
    /// same upcoming workout where possible), overrides and extras. Logs and completions stay as history.
    public mutating func deleteWorkout(_ id: String) {
        let exerciseIds = Set(exercises(in: id).map(\.id))
        workouts.removeAll { $0.id == id }
        exercises.removeAll { $0.workoutId == id }
        for (day, workoutId) in plan.weekly where workoutId == id { plan.weekly[day] = nil }
        let removedBefore = plan.cycle.prefix(plan.normalizedPosition).filter { $0 == id }.count
        let pointer = plan.normalizedPosition
        plan.cycle.removeAll { $0 == id }
        plan.position = plan.cycle.isEmpty ? 0 : (pointer - removedBefore) % plan.cycle.count
        overrides.removeAll { $0.workoutId == id }
        extras.removeAll { exerciseIds.contains($0.exerciseId) }
        if activeSession?.workoutId == id { activeSession = nil }
    }

    /// Moves a workout to `index` in the list.
    public mutating func moveWorkout(_ id: String, to index: Int) {
        guard let from = workouts.firstIndex(where: { $0.id == id }) else { return }
        let workout = workouts.remove(at: from)
        workouts.insert(workout, at: max(0, min(index, workouts.count)))
    }

    // MARK: - Exercises

    /// Appends an exercise to the end of a workout.
    @discardableResult
    public mutating func addExercise(to workoutId: String, name: String, target: String = "", unilateral: Bool = false, bodyweight: Bool = false) -> Exercise {
        let exercise = Exercise(workoutId: workoutId, name: name, unilateral: unilateral, bodyweight: bodyweight, target: target)
        if let last = exercises.lastIndex(where: { $0.workoutId == workoutId }) {
            exercises.insert(exercise, at: last + 1)
        } else {
            exercises.append(exercise)
        }
        return exercise
    }

    /// Edits an exercise (`name`, `target`, `unilateral`, `bodyweight`, `workoutId`).
    public mutating func updateExercise(_ id: String, _ change: (inout Exercise) -> Void) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        var exercise = exercises[index]
        change(&exercise)
        exercise.id = id
        exercises[index] = exercise
    }

    /// Deletes an exercise and pulls it out of extras. Its logs stay (orphaned history, as in Atlas's workout delete)
    /// but no longer count toward the strength score.
    public mutating func deleteExercise(_ id: String) {
        exercises.removeAll { $0.id == id }
        extras.removeAll { $0.exerciseId == id }
    }

    /// Moves an exercise to position `index` within its workout.
    public mutating func moveExercise(_ id: String, to index: Int) {
        guard let exercise = exercise(id) else { return }
        var group = exercises(in: exercise.workoutId)
        guard let from = group.firstIndex(where: { $0.id == id }) else { return }
        group.remove(at: from)
        group.insert(exercise, at: max(0, min(index, group.count)))
        let firstSlot = exercises.firstIndex { $0.workoutId == exercise.workoutId } ?? exercises.count
        exercises.removeAll { $0.workoutId == exercise.workoutId }
        exercises.insert(contentsOf: group, at: min(firstSlot, exercises.count))
    }

    /// "Copy from another workout": appends copies (new ids) of `exerciseIds` (default: all of `source`'s) to `target`.
    @discardableResult
    public mutating func copyExercises(from source: String, to target: String, only exerciseIds: [String]? = nil) -> [Exercise] {
        let picked = exercises(in: source).filter { exerciseIds?.contains($0.id) ?? true }
        return picked.map { addExercise(to: target, name: $0.name, target: $0.target, unilateral: $0.unilateral, bodyweight: $0.bodyweight) }
    }

    // MARK: - Plan

    public mutating func setWeekly(_ day: Weekday, workoutId: String?) {
        plan.weekly[day.rawValue] = workoutId
    }

    /// Replaces the cycle order. The pointer follows the workout it pointed at ("The pointer stays on Pull").
    public mutating func setCycle(_ order: [String]) {
        let current = plan.cycle.isEmpty ? nil : plan.cycle[plan.normalizedPosition]
        plan.cycle = order
        if let current, let index = order.firstIndex(of: current) {
            plan.position = index
        } else {
            plan.position = order.isEmpty ? 0 : min(plan.normalizedPosition, order.count - 1)
        }
    }

    /// Moves the pointer by hand (Plan → "make this next").
    public mutating func setCyclePosition(_ index: Int) {
        plan.position = plan.cycle.isEmpty ? 0 : ((index % plan.cycle.count) + plan.cycle.count) % plan.cycle.count
    }
}
