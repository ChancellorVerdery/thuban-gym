import Foundation

/// A completed session for the Progress "Recent" table.
public struct SessionSummary: Hashable, Sendable, Identifiable {
    public var completion: Completion
    public var workout: Workout?
    /// Minutes (nil when the completion has no times).
    public var duration: Int?
    /// Sets logged that day for exercises of this workout + that day's extras.
    public var setCount: Int
    /// Σ weight × reps of those sets (kg).
    public var volume: Double
    /// The highest-e1RM set of the day and its exercise.
    public var topSet: SetEntry?
    public var topExercise: Exercise?

    public var id: String { completion.id }
}

/// Progress → "By exercise" row.
public struct ExerciseProgress: Hashable, Sendable, Identifiable {
    public var exercise: Exercise
    public var workout: Workout?
    /// Latest session score (kg e1RM, or reps for bodyweight).
    public var score: Double
    public var index: Double
    public var isBodyweight: Bool
    public var sessionCount: Int
    /// Scores oldest first, for a sparkline.
    public var sparkline: [Double]

    public var id: String { exercise.id }
}

/// "On plan · 21 of 23 planned days, last 30".
public struct Adherence: Hashable, Sendable {
    public var done: Int
    public var planned: Int
    public var ratio: Double { planned == 0 ? 0 : Double(done) / Double(planned) }
}

public enum Stats {
    /// Training completions (rest excluded), newest first, summarised.
    public static func recentSessions(_ data: GymData, limit: Int = 20, includeRest: Bool = false) -> [SessionSummary] {
        let completions = data.completions
            .filter { includeRest || !(data.workout($0.workoutId)?.isRest ?? false) }
            .sorted { ($0.date, $0.ts) > ($1.date, $1.ts) }
        return completions.prefix(limit).map { summary(data, completion: $0) }
    }

    public static func summary(_ data: GymData, completion: Completion) -> SessionSummary {
        let date = completion.date
        let ids = Set(data.exercises(in: completion.workoutId).map(\.id) + data.extraIds(on: date))
        let rows = data.logs.filter { $0.date == date && ids.contains($0.exerciseId) }
        var top: (SetEntry, String)?
        for row in rows {
            for set in row.sets where top.map({ Scoring.e1RM(set) > Scoring.e1RM($0.0) }) ?? true {
                top = (set, row.exerciseId)
            }
        }
        return SessionSummary(
            completion: completion, workout: data.workout(completion.workoutId), duration: completion.durationMinutes,
            setCount: rows.reduce(0) { $0 + $1.sets.count }, volume: rows.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.volume } },
            topSet: top?.0, topExercise: data.exercise(top?.1)
        )
    }

    /// Number of training completions on or after `since` (all time when nil).
    public static func sessionCount(_ data: GymData, since: DayKey? = nil) -> Int {
        data.completions.filter { c in !(data.workout(c.workoutId)?.isRest ?? false) && (since.map { c.date >= $0 } ?? true) }.count
    }

    /// First day with a completion or a log.
    public static func firstActivity(_ data: GymData) -> DayKey? {
        (data.completions.map(\.date) + data.logs.map(\.date)).min()
    }

    /// Mean timed session length in minutes (training only) since `since`; nil without timed sessions.
    public static func averageDuration(_ data: GymData, since: DayKey? = nil) -> Int? {
        let lengths = data.completions
            .filter { c in !(data.workout(c.workoutId)?.isRest ?? false) && (since.map { c.date >= $0 } ?? true) }
            .compactMap(\.durationMinutes)
        guard !lengths.isEmpty else { return nil }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    /// Plan adherence over the `days` days ending today. A day counts as planned unless it was a rest day (rest
    /// completion, or a rest workout planned in weekly mode), an explicitly skipped day, or an empty weekly day;
    /// today counts only once it is done. Done = a training completion that day.
    public static func adherence(_ data: GymData, days: Int = 30, today: DayKey) -> Adherence {
        var planned = 0, done = 0
        for date in today.adding(days: -(days - 1)).through(today) {
            let day = date == today ? PlanEngine.day(data, on: date, today: today) : PlanEngine.pastDay(data, date: date, today: today)
            switch day.status {
            case .done: planned += 1; done += 1
            case .missed: planned += 1
            case .swapped where date < today: planned += 1
            default: break
            }
        }
        return Adherence(done: done, planned: planned)
    }

    /// Every exercise that has sessions, in workout order.
    public static func exerciseProgress(_ data: GymData) -> [ExerciseProgress] {
        data.exercises.compactMap { exercise in
            guard let history = Scoring.history(data, exerciseId: exercise.id), let latest = history.latest else { return nil }
            return ExerciseProgress(exercise: exercise, workout: data.workout(exercise.workoutId), score: latest.score,
                                    index: latest.index, isBodyweight: history.isBodyweight,
                                    sessionCount: history.sessions.count, sparkline: history.sessions.map(\.score))
        }
    }

    /// Σ volume (kg) of every set logged from `from` through `through`.
    public static func volume(_ data: GymData, from: DayKey, through: DayKey) -> Double {
        data.logs.filter { $0.date >= from && $0.date <= through }.reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.volume } }
    }

    /// Sets logged on a day for the given exercises (Today: "6 of 20 sets logged").
    public static func setCount(_ data: GymData, exerciseIds: [String], on date: DayKey) -> Int {
        let ids = Set(exerciseIds)
        return data.logs.filter { $0.date == date && ids.contains($0.exerciseId) }.reduce(0) { $0 + $1.sets.count }
    }
}
