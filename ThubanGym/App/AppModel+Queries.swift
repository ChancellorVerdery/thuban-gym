import Foundation
import ThubanGymCore

/// Read-only API for views. Everything is computed from `data` + `today` through the core's pure functions, so a
/// view that reads these re-renders whenever the document changes. All weights are kg; format with `weight(_:)`.
extension AppModel {
    // MARK: Basics

    var unit: WeightUnit { data.settings.unit }
    var settings: GymSettings { data.settings }
    var workouts: [Workout] { data.workouts }
    var plan: Plan { data.plan }
    var isCycle: Bool { data.plan.type == .cycle }
    /// Nothing local yet and never imported → Today shows the first-run import prompt.
    var isFirstRun: Bool { data.isEmpty && data.importedAt == nil }

    func workout(_ id: String?) -> Workout? { data.workout(id) }
    func exercise(_ id: String?) -> Exercise? { data.exercise(id) }
    func exercises(in workoutId: String) -> [Exercise] { data.exercises(in: workoutId) }

    // MARK: Plan

    /// Today's plan entry (done / in progress / planned / skipped / swapped / rest …).
    var todayPlan: PlanDay { PlanEngine.day(data, on: today, today: today) }

    func planDay(_ date: DayKey) -> PlanDay { PlanEngine.day(data, on: date, today: today) }

    /// The workout planned for a date (override > plan; nil for skip / nothing planned).
    func plannedWorkout(on date: DayKey) -> Workout? { PlanEngine.plannedWorkout(data, on: date, today: today) }

    /// Consecutive days from `start` (past days show what happened, today/future the projection).
    func planDays(from start: DayKey, count: Int) -> [PlanDay] { PlanEngine.days(data, from: start, count: count, today: today) }

    /// Monday of the current week.
    var weekStart: DayKey { today.adding(days: -(Weekday.allCases.firstIndex(of: today.weekday) ?? 0)) }

    /// The Plan screen's strip: 14 days from Monday of this week.
    var planStrip: [PlanDay] { planDays(from: weekStart, count: 14) }

    /// "Cycle day 2 of 4" for a date fed by the cycle.
    func cyclePosition(on date: DayKey) -> (index: Int, count: Int)? { PlanEngine.cyclePosition(data, on: date, today: today) }

    /// Next date (after `after`) the workout is projected — "Legs moves to Sat Sep 26".
    func nextDate(of workoutId: String, after: DayKey) -> DayKey? { PlanEngine.nextDate(of: workoutId, in: data, after: after, today: today) }

    /// Where a workout is referenced (cycle slots, weekly days, upcoming swaps) — Workouts → "Used in".
    func usages(of workoutId: String) -> [WorkoutUsage] { PlanEngine.usages(of: workoutId, in: data, today: today) }

    /// Average timed session length for a workout, or the default duration.
    func workoutDuration(_ workoutId: String) -> Int { PlanEngine.workoutDuration(data, workoutId: workoutId) }

    /// Upcoming overrides (today and later), date order.
    var upcomingOverrides: [PlanOverride] { data.overrides.filter { $0.date >= today }.sorted { $0.date < $1.date } }

    /// Extras on a date (exercise ids, add order).
    func extraIds(on date: DayKey) -> [String] { data.extraIds(on: date) }

    // MARK: Session

    var activeSession: ActiveSession? { data.activeSession }
    var activeWorkout: Workout? { data.workout(data.activeSession?.workoutId) }

    /// Seconds since the running session started (drive with `TimelineView(.periodic(from: .now, by: 1))`).
    func sessionElapsed(now: Date = Date()) -> TimeInterval {
        guard let session = data.activeSession else { return 0 }
        return max(0, now.timeIntervalSince(session.startedAt))
    }

    /// The workout's exercises then the day's extras. `workoutId` nil → the workout shown for that day.
    func sessionExercises(on date: DayKey, workoutId: String? = nil) -> [SessionExercise] {
        PlanEngine.sessionExercises(data, workoutId: workoutId ?? planDay(date).workout?.id, on: date)
    }

    /// Sets logged for an exercise on a day and side (nil = bilateral).
    func sets(exerciseId: String, date: DayKey, side: Side? = nil) -> [SetEntry] { data.sets(exerciseId: exerciseId, date: date, side: side) }

    /// Σ sets logged on a day across the given exercises ("6 of 20 sets logged").
    func setCount(exerciseIds: [String], on date: DayKey) -> Int { Stats.setCount(data, exerciseIds: exerciseIds, on: date) }

    /// The last session before `date` ("Last time, Sun Sep 20 · 135 × 8, 8, 8, 7 · e1RM 171.0").
    func previousSession(exerciseId: String, before date: DayKey) -> ExerciseSession? {
        guard let previous = data.previousSessionDate(exerciseId: exerciseId, before: date) else { return nil }
        return Scoring.session(data, exerciseId: exerciseId, on: previous)
    }

    /// Rest timer for a workout (seconds).
    func restSeconds(for workoutId: String?) -> Int { data.restSeconds(for: workoutId) }

    // MARK: Scores and history

    func history(exerciseId: String) -> ExerciseHistory? { Scoring.history(data, exerciseId: exerciseId) }

    func session(exerciseId: String, on date: DayKey) -> ExerciseSession? { Scoring.session(data, exerciseId: exerciseId, on: date) }

    func nextTarget(exerciseId: String) -> NextTarget? { Scoring.nextTarget(data, exerciseId: exerciseId) }

    /// Mean of every exercise's latest index on `date` (default today); nil before any log.
    func strengthScore(on date: DayKey? = nil) -> Double? { Scoring.strengthScore(data, on: date ?? today) }

    /// Strength score at every logged day in the range, oldest first.
    func strengthSeries(_ range: ProgressRange = .all) -> [(date: DayKey, score: Double)] {
        Scoring.strengthSeries(data, from: range.start(today: today), through: today)
    }

    /// Strength score sampled weekly (the Progress chart), oldest first.
    func weeklyStrengthSeries(_ range: ProgressRange = .all) -> [(date: DayKey, score: Double)] {
        guard let first = Stats.firstActivity(data) else { return [] }
        let start = max(first, range.start(today: today) ?? first)
        return Scoring.sampledStrengthSeries(data, from: start, through: today, stepDays: 7)
    }

    /// Change in strength score over the last `days` days ("+1.6 in 4 weeks"); nil without both ends.
    func strengthChange(days: Int = 28) -> Double? {
        guard let now = strengthScore(), let then = Scoring.strengthScore(data, on: today.adding(days: -days)) else { return nil }
        return now - then
    }

    func recentSessions(limit: Int = 20) -> [SessionSummary] { Stats.recentSessions(data, limit: limit) }
    func exerciseProgress() -> [ExerciseProgress] { Stats.exerciseProgress(data) }
    func adherence(days: Int = 30) -> Adherence { Stats.adherence(data, days: days, today: today) }
    func sessionCount(since: DayKey? = nil) -> Int { Stats.sessionCount(data, since: since) }
    func averageDuration(since: DayKey? = nil) -> Int? { Stats.averageDuration(data, since: since) }
    var firstActivity: DayKey? { Stats.firstActivity(data) }

    // MARK: Formatting in the display unit

    /// "140" / "63.5" / "BW".
    func weight(_ kg: Double?) -> String { GymFormat.weight(kg, unit: unit) }
    /// "140 lb" / "BW".
    func weightWithUnit(_ kg: Double?) -> String { GymFormat.weightWithUnit(kg, unit: unit) }
    /// e1RM score in the display unit ("177.3") or "8 reps" for bodyweight.
    func score(_ value: Double, bodyweight: Bool) -> String { GymFormat.score(value, bodyweight: bodyweight, unit: unit) }
    /// Display-unit number typed by the user → kg (nil / ≤ 0 = bodyweight). Never rounds.
    func kilograms(fromDisplay value: Double?) -> Double? { value.flatMap { $0 > 0 ? unit.toKilograms($0) : nil } }
    /// kg → display-unit number (for editing fields).
    func displayValue(_ kg: Double?) -> Double? { kg.map(unit.fromKilograms) }
}
