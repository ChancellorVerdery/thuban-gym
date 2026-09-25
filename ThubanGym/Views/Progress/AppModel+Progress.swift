import Foundation
import ThubanGymCore

/// One row of Progress → Recent: a finished session, or the one running now ("5:42 PM – now").
struct ProgressSessionRow: Identifiable, Hashable {
    var id: String
    var date: DayKey
    var workoutName: String
    /// "5:40 – 6:44 PM", "5:42 PM – now", or "" when the completion has no times.
    var time: String
    var minutes: Int?
    var isLive: Bool
    /// "16" or, while live, "6 of 20".
    var sets: String
    /// "Barbell Row 140 × 8" in the display unit, nil when nothing was logged.
    var topSet: String?
}

/// One row of Progress → By exercise, limited to the selected range.
struct ProgressExerciseRow: Identifiable, Hashable {
    var exercise: Exercise
    var workoutName: String?
    var isBodyweight: Bool
    /// Latest session score (kg e1RM, or reps) and index against the first session ever.
    var score: Double
    var index: Double
    /// Session scores inside the range, oldest first.
    var sparkline: [Double]
    var id: String { exercise.id }
}

/// Read-only queries for the Progress section (Engineer C). Built only from `data` / `today` and core functions.
extension AppModel {
    /// First day of the Progress range: the range start, but never before the first logged activity.
    func progressStart(_ range: ProgressRange) -> DayKey? {
        guard let first = firstActivity else { return nil }
        guard let start = range.start(today: today) else { return first }
        return max(first, start)
    }

    /// "Progress · Feb 2 – Sep 24".
    func progressEyebrow(_ range: ProgressRange) -> String {
        guard let start = progressStart(range) else { return "Progress" }
        return "Progress · \(GymFormat.monthDay(start)) – \(GymFormat.monthDay(today))"
    }

    /// Strength score minus the 100 baseline, as a percentage ("Stronger by 17.3%").
    var strengthGainPercent: Double? { strengthScore().map { $0 - 100 } }

    /// Sessions (training completions) in the range.
    func progressSessionCount(_ range: ProgressRange) -> Int { sessionCount(since: progressStart(range)) }

    /// Recent sessions, newest first, with the running session (if any) on top.
    func progressRecentRows(limit: Int = 30) -> [ProgressSessionRow] {
        var rows: [ProgressSessionRow] = []
        if let live = liveSessionRow() { rows.append(live) }
        for summary in recentSessions(limit: limit) {
            let completion = summary.completion
            rows.append(ProgressSessionRow(
                id: summary.id, date: completion.date, workoutName: summary.workout?.name ?? "Deleted workout",
                time: GymFormat.clockRange(start: completion.start, end: completion.end),
                minutes: summary.duration, isLive: false, sets: String(summary.setCount),
                topSet: topSetText(summary.topSet, exercise: summary.topExercise)))
        }
        return rows
    }

    private func liveSessionRow() -> ProgressSessionRow? {
        guard let session = activeSession, let workout = workout(session.workoutId) else { return nil }
        let exercises = sessionExercises(on: session.date, workoutId: workout.id)
        let ids = exercises.map(\.exercise.id)
        let logged = setCount(exerciseIds: ids, on: session.date)
        let planned = PlanEngine.plannedSetCount(exercises)
        var top: (SetEntry, Exercise)?
        for exercise in exercises.map(\.exercise) {
            for side in exercise.unilateral ? [Side?.none, .left, .right] : [nil] {
                for set in sets(exerciseId: exercise.id, date: session.date, side: side)
                where top.map({ Scoring.e1RM(set) > Scoring.e1RM($0.0) }) ?? true {
                    top = (set, exercise)
                }
            }
        }
        let start = GymFormat.clock(ClockTime.string(from: session.startedAt))
        return ProgressSessionRow(
            id: "live|\(session.date.rawValue)|\(workout.id)", date: session.date, workoutName: workout.name,
            time: start.isEmpty ? "now" : "\(start) – now",
            minutes: Int(sessionElapsed() / 60), isLive: true,
            sets: planned > 0 ? "\(logged) of \(planned)" : String(logged),
            topSet: topSetText(top?.0, exercise: top?.1))
    }

    private func topSetText(_ set: SetEntry?, exercise: Exercise?) -> String? {
        guard let set, let exercise else { return nil }
        return "\(exercise.name) \(GymFormat.set(set, unit: unit))"
    }

    /// At most `count` points: the best score of each consecutive bucket, so a long history reads as a trend.
    static func downsample(_ values: [Double], to count: Int) -> [Double] {
        guard values.count > count, count > 1 else { return values }
        return (0..<count).map { bucket in
            let lower = bucket * values.count / count
            let upper = max(lower + 1, (bucket + 1) * values.count / count)
            return values[lower..<upper].max() ?? values[lower]
        }
    }

    /// Every exercise with history, in workout order, with its sparkline cut to the range (at least the last two
    /// sessions, so a quiet range still draws a line).
    func progressExerciseRows(_ range: ProgressRange) -> [ProgressExerciseRow] {
        let start = range.start(today: today)
        return data.exercises.compactMap { exercise in
            guard let history = history(exerciseId: exercise.id), let latest = history.latest else { return nil }
            var sessions = history.sessions
            if let start {
                let inRange = sessions.filter { $0.date >= start }
                sessions = inRange.count >= 2 ? inRange : Array(sessions.suffix(2))
            }
            return ProgressExerciseRow(exercise: exercise, workoutName: workout(exercise.workoutId)?.name,
                                       isBodyweight: history.isBodyweight, score: latest.score, index: latest.index,
                                       sparkline: Self.downsample(sessions.map(\.score), to: 12))
        }
    }
}
