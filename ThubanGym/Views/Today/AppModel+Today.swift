import Foundation
import ThubanGymCore

/// Today's read-only queries (session progress, the rail's numbers, the cycle note). Built from `data` / `today` and
/// the core's public functions only. OWNER: Engineer A.
extension AppModel {
    /// Sets logged for one exercise on a day, counting a unilateral L + R pair as ONE set (the target counts sets,
    /// not sides: "3 × 10" on a single-arm row is three pairs).
    func todayLoggedSets(_ exercise: Exercise, on date: DayKey? = nil) -> Int {
        let day = date ?? today
        if exercise.unilateral {
            let left = sets(exerciseId: exercise.id, date: day, side: .left).count
            let right = sets(exerciseId: exercise.id, date: day, side: .right).count
            let both = sets(exerciseId: exercise.id, date: day, side: nil).count
            return max(left, right) + both
        }
        return sets(exerciseId: exercise.id, date: day, side: nil).count
    }

    /// Target sets for an exercise (0 when the target does not parse).
    func todayTargetSets(_ exercise: Exercise) -> Int { exercise.targetSpec?.sets ?? 0 }

    /// "6 of 20 sets logged" for a list of session exercises.
    func todayProgress(_ items: [SessionExercise], on date: DayKey? = nil) -> (logged: Int, planned: Int) {
        let logged = items.reduce(0) { $0 + todayLoggedSets($1.exercise, on: date) }
        return (logged, PlanEngine.plannedSetCount(items))
    }

    /// An exercise is finished for the day once it has at least its target number of sets.
    func todayIsFinished(_ exercise: Exercise, on date: DayKey? = nil) -> Bool {
        let target = todayTargetSets(exercise)
        return target > 0 && todayLoggedSets(exercise, on: date) >= target
    }

    /// The card that is expanded: the focused one if it is in the list, else the first unfinished, else the first.
    func todayFocusId(_ items: [SessionExercise]) -> String? {
        if let id = focusedExerciseId, items.contains(where: { $0.id == id }) { return id }
        return items.first { !todayIsFinished($0.exercise) }?.id ?? items.first?.id
    }

    /// The most recent completion of a workout before `date` ("last Pull Sun Sep 20, 61 min").
    func todayLastCompletion(of workoutId: String, before date: DayKey? = nil) -> Completion? {
        let day = date ?? today
        return data.completions
            .filter { $0.workoutId == workoutId && $0.date < day }
            .max { ($0.date, $0.ts) < ($1.date, $1.ts) }
    }

    /// Σ volume (kg) of the given exercises on a day.
    func todayVolume(exerciseIds: [String], on date: DayKey) -> Double {
        let ids = Set(exerciseIds)
        return data.logs.filter { $0.date == date && ids.contains($0.exerciseId) }
            .reduce(0) { $0 + $1.sets.reduce(0) { $0 + $1.volume } }
    }

    /// Volume of the last session of the same workout (its own exercises + that day's extras).
    func todayLastVolume(of workoutId: String) -> (volume: Double, date: DayKey)? {
        guard let last = todayLastCompletion(of: workoutId) else { return nil }
        let ids = exercises(in: workoutId).map(\.id) + extraIds(on: last.date)
        let volume = todayVolume(exerciseIds: ids, on: last.date)
        return volume > 0 ? (volume, last.date) : nil
    }

    /// The weighted exercise with the best e1RM logged today, with its change against its previous session.
    func todayBestLift(_ items: [SessionExercise]) -> (exercise: Exercise, score: Double, delta: Double?)? {
        var best: (exercise: Exercise, score: Double, delta: Double?)?
        for item in items {
            guard let session = session(exerciseId: item.id, on: today), session.topWeight != nil else { continue }
            if best == nil || session.score > best!.score {
                let previous = previousSession(exerciseId: item.id, before: today)
                best = (item.exercise, session.score, previous.map { session.score - $0.score })
            }
        }
        return best
    }

    /// The first upcoming override (tomorrow … a week out) that moves a cycle / plan workout, phrased for the rail:
    /// "Tomorrow is skipped (career fair), so Legs moves to Sat Sep 26."
    func todayPlanNote() -> String? {
        for offset in 1...7 {
            let date = today.adding(days: offset)
            guard let override = data.override(on: date) else { continue }
            let day = planDay(date)
            let when = offset == 1 ? "Tomorrow" : GymFormat.shortDay(date)
            let reason = override.note.map { " (\(Self.todayShortNote($0)))" } ?? ""
            if override.isSkip {
                guard let moved = day.plannedWorkout ?? day.workout else { return "\(when) is skipped\(reason)." }
                if let next = nextDate(of: moved.id, after: date) {
                    return "\(when) is skipped\(reason), so \(moved.name) moves to \(GymFormat.shortDay(next))."
                }
                return "\(when) is skipped\(reason)."
            } else if let swapped = workout(override.workoutId) {
                if let planned = day.plannedWorkout, planned.id != swapped.id {
                    return "\(when) is swapped to \(swapped.name)\(reason); \(planned.name) waits a day."
                }
                return "\(when) is swapped to \(swapped.name)\(reason)."
            }
        }
        return nil
    }

    /// "Career fair at the student union, 10–3" → "career fair at the student union".
    static func todayShortNote(_ note: String) -> String {
        let head = note.split(separator: ",").first.map(String.init) ?? note
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return trimmed }
        // Keep acronyms ("TA office hours") as typed.
        let second = trimmed.dropFirst().first
        if let second, second.isUppercase { return trimmed }
        return first.lowercased() + trimmed.dropFirst()
    }

    /// Exercises that can be pulled into today (not already in the session), grouped by workout in plan order.
    func todayExtraCandidates(excluding ids: Set<String>) -> [(workout: Workout, exercises: [Exercise])] {
        workouts.compactMap { workout in
            let list = exercises(in: workout.id).filter { !ids.contains($0.id) }
            return list.isEmpty ? nil : (workout, list)
        }
    }
}
