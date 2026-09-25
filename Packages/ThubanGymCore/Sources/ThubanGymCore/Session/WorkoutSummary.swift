import Foundation

/// The "Workout complete" screen: what a finished session added up to, and what stood out.
public struct WorkoutSummary: Hashable, Sendable {
    public enum Highlight: Hashable, Sendable {
        /// A weighted exercise beat every earlier session: its best set and the gain over the previous session (kg).
        case newBest(exercise: Exercise, set: SetEntry, score: Double, gain: Double?)
        /// A bodyweight exercise did more total reps than last time.
        case moreReps(exercise: Exercise, sets: [SetEntry], totalReps: Int, gain: Int)
        /// Every target set reached the top of the range: the next target goes up.
        case targetHit(exercise: Exercise, spec: TargetSpec, nextWeightKg: Double?)
    }

    public var completion: Completion
    public var workout: Workout?
    public var minutes: Int?
    public var setsLogged: Int
    public var setsPlanned: Int
    /// kg × reps over the session's exercises.
    public var volume: Double
    /// Volume of the previous completion of the same workout (nil without one, or when it logged nothing).
    public var previousVolume: Double?
    /// The weighted exercise with the best e1RM today.
    public var bestLift: BestLift?
    public var strengthScore: Double?
    /// Strength score change over the day (today vs yesterday).
    public var strengthChange: Double?
    public var highlights: [Highlight]
    /// In cycle mode: the workout the pointer now points at and its next projected date.
    public var nextWorkout: Workout?
    public var nextDate: DayKey?

    public struct BestLift: Hashable, Sendable {
        public var exercise: Exercise
        /// e1RM, kg.
        public var score: Double
    }

    /// Builds the summary for a completion (normally the receipt of `finishSession`).
    public static func make(_ data: GymData, completion: Completion, maxHighlights: Int = 4) -> WorkoutSummary {
        let date = completion.date
        let items = PlanEngine.sessionExercises(data, workoutId: completion.workoutId, on: date)
        let progress = SessionLogic.progress(data, items: items, on: date)
        let ids = Set(items.map(\.id))
        let volume = data.logs.filter { $0.date == date && ids.contains($0.exerciseId) }
            .reduce(0.0) { $0 + $1.sets.reduce(0.0) { $0 + $1.volume } }

        let previous = data.completions
            .filter { $0.workoutId == completion.workoutId && $0.date < date }
            .max { ($0.date, $0.ts) < ($1.date, $1.ts) }
        var previousVolume: Double?
        if let previous {
            let previousIds = Set(PlanEngine.sessionExercises(data, workoutId: previous.workoutId, on: previous.date).map(\.id))
            let value = data.logs.filter { $0.date == previous.date && previousIds.contains($0.exerciseId) }
                .reduce(0.0) { $0 + $1.sets.reduce(0.0) { $0 + $1.volume } }
            previousVolume = value > 0 ? value : nil
        }

        var best: BestLift?
        var highlights: [Highlight] = []
        var targetHits: [Highlight] = []
        for item in items {
            guard let history = Scoring.history(data, exerciseId: item.id),
                  let index = history.sessions.firstIndex(where: { $0.date == date }) else { continue }
            let session = history.sessions[index]
            let before = index > 0 ? history.sessions[index - 1] : nil
            if session.topWeight != nil, !history.isBodyweight {
                if best == nil || session.score > best!.score { best = BestLift(exercise: item.exercise, score: session.score) }
                if session.isBest, let set = session.bestSet {
                    highlights.append(.newBest(exercise: item.exercise, set: set, score: session.score, gain: before.map { session.score - $0.score }))
                }
            } else if history.isBodyweight, let before, session.totalReps > before.totalReps {
                highlights.append(.moreReps(exercise: item.exercise, sets: session.allSets, totalReps: session.totalReps,
                                            gain: session.totalReps - before.totalReps))
            }
            if let spec = item.exercise.targetSpec, let target = Scoring.nextTarget(data, exerciseId: item.id), target.increase,
               history.latest?.date == date {
                targetHits.append(.targetHit(exercise: item.exercise, spec: spec, nextWeightKg: target.weightKg))
            }
        }
        // New bests first, then rep gains, then targets reached (whose exercise is not already a highlight).
        let named = Set(highlights.map(\.exerciseId))
        highlights += targetHits.filter { !named.contains($0.exerciseId) }

        let score = Scoring.strengthScore(data, on: date)
        let yesterday = Scoring.strengthScore(data, on: date.adding(days: -1))
        var nextWorkout: Workout?
        var nextDate: DayKey?
        if data.plan.type == .cycle, !data.plan.cycle.isEmpty, let next = data.workout(data.plan.cycle[data.plan.normalizedPosition]) {
            nextWorkout = next
            nextDate = PlanEngine.nextDate(of: next.id, in: data, after: date, today: date)
        }

        return WorkoutSummary(
            completion: completion, workout: data.workout(completion.workoutId), minutes: completion.durationMinutes,
            setsLogged: progress.logged, setsPlanned: progress.planned, volume: volume, previousVolume: previousVolume,
            bestLift: best, strengthScore: score,
            strengthChange: (score != nil && yesterday != nil) ? score! - yesterday! : nil,
            highlights: Array(highlights.prefix(maxHighlights)), nextWorkout: nextWorkout, nextDate: nextDate)
    }
}

extension WorkoutSummary.Highlight {
    public var exerciseId: String {
        switch self {
        case .newBest(let exercise, _, _, _), .moreReps(let exercise, _, _, _), .targetHit(let exercise, _, _): return exercise.id
        }
    }
}
