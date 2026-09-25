import Foundation

/// What a day looks like on the Plan / Today screens.
public enum DayStatus: String, Hashable, Sendable {
    /// A training workout was completed that day.
    case done
    /// Today's session is running.
    case inProgress
    /// Today or a future day with a training workout to do.
    case planned
    /// An override skips the day (`plannedWorkout` names what would have been done).
    case skipped
    /// An override replaces the planned workout (`plannedWorkout` names the replaced one).
    case swapped
    /// A rest workout is planned (today / future) or was the plan (past, weekly).
    case rest
    /// A rest workout was completed (manually or by the midnight auto-complete).
    case restDone
    /// A past day where the planned training was not done (in cycle mode the workout may be unknown → nil).
    case missed
    /// Nothing planned (empty weekly day, empty cycle).
    case empty
}

/// Where a day's workout came from.
public enum DaySource: String, Hashable, Sendable {
    case completion, session, override, weekly, cycle, none
}

/// One day of the plan: what is/was planned, what happened, and why.
public struct PlanDay: Identifiable, Hashable, Sendable {
    public var date: DayKey
    public var isToday: Bool
    /// The workout to show for the day (the done one, the running one, the swapped-in one, or the plan's).
    public var workout: Workout?
    public var status: DayStatus
    public var source: DaySource
    /// For skipped / swapped days: what the plan itself had for the day.
    public var plannedWorkout: Workout?
    /// For days fed by the cycle: the slot index (0-based) → "Cycle day 2 of 4".
    public var cycleIndex: Int?
    public var override: PlanOverride?
    public var completions: [Completion]
    /// Exercises pulled in from other workouts for this day.
    public var extraExerciseIds: [String]

    public var id: String { date.rawValue }
}

/// Where a workout is referenced (Workouts → "Used in").
public enum WorkoutUsage: Hashable, Sendable {
    /// 0-based cycle slot.
    case cycle(index: Int)
    case weekly(Weekday)
    case override(DayKey)
}

/// Pure plan rules over a `GymData` snapshot.
///
/// - Planned workout = override (skip / swap) > plan (weekly day, or the cycle projected from the pointer).
/// - Cycle projection: today uses slot `position`; every later day WITHOUT an override uses the next slot. Days with
///   an override (skip or swap) never consume a slot, and nothing but a completion moves the pointer. If today is
///   already done, the pointer has already advanced, so tomorrow starts at `position`.
/// - Past days show what happened (completions), not a reconstruction of the plan.
public enum PlanEngine {
    /// The workout planned for `date` (nil for skip / nothing planned). For today/future days this is the
    /// projected plan with overrides applied; for past days it is what was completed.
    public static func plannedWorkout(_ data: GymData, on date: DayKey, today: DayKey) -> Workout? {
        let entry = day(data, on: date, today: today)
        return entry.status == .skipped ? nil : entry.workout
    }

    /// One day.
    public static func day(_ data: GymData, on date: DayKey, today: DayKey) -> PlanDay {
        if date < today { return pastDay(data, date: date, today: today) }
        return project(data, from: today, through: date, today: today).last ?? emptyDay(date, today: today)
    }

    /// `count` consecutive days starting at `start` (the Plan screen's 14-day strip: `start` = Monday of this week).
    public static func days(_ data: GymData, from start: DayKey, count: Int, today: DayKey) -> [PlanDay] {
        guard count > 0 else { return [] }
        let end = start.adding(days: count - 1)
        var result: [PlanDay] = []
        var day = start
        while day < today && day <= end {
            result.append(pastDay(data, date: day, today: today))
            day = day.adding(days: 1)
        }
        if end >= today {
            let future = project(data, from: today, through: end, today: today)
            result.append(contentsOf: future.filter { $0.date >= start })
        }
        return result
    }

    /// The first day on or after `after` (exclusive) the workout is projected (Today: "Legs moves to Sat Sep 26").
    public static func nextDate(of workoutId: String, in data: GymData, after: DayKey, today: DayKey, horizon: Int = 60) -> DayKey? {
        let start = max(after.adding(days: 1), today)
        return project(data, from: today, through: start.adding(days: horizon), today: today)
            .first { $0.date >= start && $0.workout?.id == workoutId && ($0.status == .planned || $0.status == .swapped || $0.status == .rest) }?
            .date
    }

    /// "Cycle day 2 of 4" source: (slot index, cycle length) when the day is fed by the cycle.
    public static func cyclePosition(_ data: GymData, on date: DayKey, today: DayKey) -> (index: Int, count: Int)? {
        guard data.plan.type == .cycle, !data.plan.cycle.isEmpty else { return nil }
        if let index = day(data, on: date, today: today).cycleIndex { return (index, data.plan.cycle.count) }
        return nil
    }

    /// Cycle slots, weekly days and upcoming overrides that reference a workout.
    public static func usages(of workoutId: String, in data: GymData, today: DayKey) -> [WorkoutUsage] {
        var result: [WorkoutUsage] = []
        for (index, id) in data.plan.cycle.enumerated() where id == workoutId { result.append(.cycle(index: index)) }
        for day in Weekday.allCases where data.plan.weeklyWorkoutId(day) == workoutId { result.append(.weekly(day)) }
        for override in data.overrides.sorted(by: { $0.date < $1.date }) where override.workoutId == workoutId && override.date >= today {
            result.append(.override(override.date))
        }
        return result
    }

    /// Average session length in minutes for a workout from timed completions; `settings.defaultDuration` when none.
    public static func workoutDuration(_ data: GymData, workoutId: String) -> Int {
        let lengths = data.completions.filter { $0.workoutId == workoutId }.compactMap(\.durationMinutes)
        guard !lengths.isEmpty else { return data.settings.defaultDuration }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    // MARK: - Projection

    /// Days `today…through` (inclusive). Empty when `through < from` or `from < today`.
    static func project(_ data: GymData, from: DayKey, through: DayKey, today: DayKey) -> [PlanDay] {
        guard from >= today, through >= from else { return [] }
        var result: [PlanDay] = []
        let cycle = data.plan.cycle
        let isCycle = data.plan.type == .cycle && !cycle.isEmpty
        var offset = 0

        func slot() -> (index: Int, workout: Workout?) {
            let index = (data.plan.normalizedPosition + offset) % cycle.count
            return (index, data.workout(cycle[index]))
        }

        for date in today.through(through) {
            let isToday = date == today
            let override = data.override(on: date)
            let completions = data.completions(on: date)
            let extras = data.extraIds(on: date)
            var entry = PlanDay(date: date, isToday: isToday, workout: nil, status: .empty, source: .none,
                                plannedWorkout: nil, cycleIndex: nil, override: override, completions: completions,
                                extraExerciseIds: extras)

            // What the plan itself says (without the override), consuming a cycle slot only for override-free days.
            var planWorkout: Workout?
            var planIndex: Int?
            if isCycle {
                let s = slot()
                planWorkout = s.workout
                planIndex = s.index
            } else if data.plan.type == .weekly {
                planWorkout = data.workout(data.plan.weeklyWorkoutId(date.weekday))
            }

            if isToday, let session = data.activeSession, session.date == today {
                // A running session wins over anything finished earlier today ("Train anyway" after a rest day,
                // a second session): it is what is being done and logged against right now.
                entry.workout = data.workout(session.workoutId)
                entry.status = .inProgress
                entry.source = .session
                if !completions.isEmpty {
                    // Something was already done today, so the pointer has moved past today's slot.
                    entry.plannedWorkout = override == nil ? nil : planWorkout
                } else if override == nil {
                    entry.cycleIndex = planIndex
                    if isCycle { offset += 1 }
                } else {
                    entry.plannedWorkout = planWorkout
                }
            } else if isToday, let done = completions.last {
                // Done today: the pointer already moved past it, so today consumes nothing.
                entry.workout = data.workout(done.workoutId)
                entry.status = (entry.workout?.isRest ?? false) ? .restDone : .done
                entry.source = .completion
                entry.plannedWorkout = override == nil ? nil : planWorkout
            } else if let override {
                entry.plannedWorkout = planWorkout
                entry.source = .override
                if override.isSkip {
                    entry.workout = planWorkout
                    entry.status = .skipped
                } else {
                    entry.workout = data.workout(override.workoutId)
                    entry.status = (entry.workout?.isRest ?? false) ? .rest : .swapped
                }
            } else {
                entry.workout = planWorkout
                entry.source = planWorkout == nil ? .none : (isCycle ? .cycle : .weekly)
                entry.cycleIndex = planIndex
                if let workout = planWorkout {
                    entry.status = workout.isRest ? .rest : .planned
                } else {
                    entry.status = .empty
                }
                if isCycle { offset += 1 }
            }
            if date >= from { result.append(entry) }
        }
        return result
    }

    static func pastDay(_ data: GymData, date: DayKey, today: DayKey) -> PlanDay {
        let override = data.override(on: date)
        let completions = data.completions(on: date)
        var entry = PlanDay(date: date, isToday: false, workout: nil, status: .empty, source: .none, plannedWorkout: nil,
                            cycleIndex: nil, override: override, completions: completions, extraExerciseIds: data.extraIds(on: date))
        let weeklyPlan = data.plan.type == .weekly ? data.workout(data.plan.weeklyWorkoutId(date.weekday)) : nil
        if let done = completions.last(where: { !(data.workout($0.workoutId)?.isRest ?? false) }) ?? completions.last {
            entry.workout = data.workout(done.workoutId)
            entry.status = (entry.workout?.isRest ?? false) ? .restDone : .done
            entry.source = .completion
            if override != nil { entry.plannedWorkout = weeklyPlan }
        } else if let override {
            entry.source = .override
            entry.plannedWorkout = weeklyPlan
            if override.isSkip {
                entry.workout = weeklyPlan
                entry.status = .skipped
            } else {
                entry.workout = data.workout(override.workoutId)
                entry.status = (entry.workout?.isRest ?? false) ? .rest : .missed
            }
        } else if let weeklyPlan {
            entry.workout = weeklyPlan
            entry.source = .weekly
            entry.status = weeklyPlan.isRest ? .rest : .missed
        } else {
            entry.status = data.plan.type == .cycle && !data.plan.cycle.isEmpty ? .missed : .empty
        }
        return entry
    }

    private static func emptyDay(_ date: DayKey, today: DayKey) -> PlanDay {
        PlanDay(date: date, isToday: date == today, workout: nil, status: .empty, source: .none, plannedWorkout: nil,
                cycleIndex: nil, override: nil, completions: [], extraExerciseIds: [])
    }
}

// MARK: - Session contents

/// One exercise in a day's session (Today's list).
public struct SessionExercise: Hashable, Sendable, Identifiable {
    public var exercise: Exercise
    /// Pulled in from another workout for this day only.
    public var isExtra: Bool
    /// For extras: the workout it belongs to ("Extra · from Upper").
    public var sourceWorkout: Workout?

    public var id: String { exercise.id }
}

extension PlanEngine {
    /// The workout's exercises in order, then the day's extras (skipping any already in the workout).
    public static func sessionExercises(_ data: GymData, workoutId: String?, on date: DayKey) -> [SessionExercise] {
        let own = workoutId.map { data.exercises(in: $0) } ?? []
        let ownIds = Set(own.map(\.id))
        let extras = data.extraIds(on: date).filter { !ownIds.contains($0) }.compactMap { data.exercise($0) }
        return own.map { SessionExercise(exercise: $0, isExtra: false, sourceWorkout: nil) }
            + extras.map { SessionExercise(exercise: $0, isExtra: true, sourceWorkout: data.workout($0.workoutId)) }
    }

    /// Σ target sets over a session (a unilateral 3 × 10 counts 3). Exercises without a parseable target count 0.
    public static func plannedSetCount(_ exercises: [SessionExercise]) -> Int {
        exercises.reduce(0) { $0 + ($1.exercise.targetSpec?.sets ?? 0) }
    }
}
