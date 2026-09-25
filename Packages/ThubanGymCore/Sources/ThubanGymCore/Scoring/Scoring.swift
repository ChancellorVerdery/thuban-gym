import Foundation

/// One exercise on one day, summarised (Exercise history rows, Today's "Last time …").
public struct ExerciseSession: Hashable, Sendable, Identifiable {
    public var date: DayKey
    /// Bilateral sets (side nil). For a unilateral exercise logged without sides these hold everything.
    public var sets: [SetEntry]
    public var left: [SetEntry]
    public var right: [SetEntry]
    /// Session score: best set e1RM (kg), or reps for bodyweight; unilateral uses the weaker side.
    public var score: Double
    /// Heaviest weight lifted (kg), nil when every set was bodyweight.
    public var topWeight: Double?
    /// Σ weight × reps over every set and side (kg).
    public var volume: Double
    public var totalReps: Int
    /// The set with the highest e1RM (on the scoring side).
    public var bestSet: SetEntry?
    /// Score beats every earlier session (the first session is not a PR).
    public var isBest: Bool
    /// Top weight minus the previous session's top weight (kg), nil when either is bodyweight / first session.
    public var topWeightChange: Double?
    /// Index = 100 · score / first session's score.
    public var index: Double

    public var id: String { date.rawValue }
    /// Every set regardless of side.
    public var allSets: [SetEntry] { sets + left + right }
    public var setCount: Int { allSets.count }
}

/// An exercise's whole history, oldest first.
public struct ExerciseHistory: Hashable, Sendable {
    public var exercise: Exercise
    public var sessions: [ExerciseSession]
    /// True when no logged set has a weight (Pull-up style → "BW", scored by reps).
    public var isBodyweight: Bool

    public var first: ExerciseSession? { sessions.first }
    public var latest: ExerciseSession? { sessions.last }
    public var best: ExerciseSession? { sessions.max { $0.score < $1.score } }
    /// Current index (latest session), nil without sessions.
    public var index: Double? { latest?.index }
    public var score: Double? { latest?.score }
}

/// Epley e1RM, progress indexes and the strength score. Everything is in kg; bodyweight sets score by reps.
public enum Scoring {
    /// Epley: w · (1 + reps/30). Bodyweight (nil / ≤ 0 weight): reps.
    public static func e1RM(_ set: SetEntry) -> Double {
        guard let weight = set.weight, weight > 0 else { return Double(set.reps) }
        return weight * (1 + Double(set.reps) / 30)
    }

    public static func e1RM(weightKg: Double?, reps: Int) -> Double { e1RM(SetEntry(weight: weightKg, reps: reps)) }

    /// Best e1RM in a list of sets (nil when empty).
    public static func best(_ sets: [SetEntry]) -> Double? { sets.map(e1RM).max() }

    /// Session score from one day's log rows. Unilateral with both sides logged: the weaker side's best, so an
    /// imbalance never inflates progress. Otherwise the best set.
    public static func sessionScore(_ rows: [LogEntry], unilateral: Bool) -> Double? {
        let bilateral = rows.filter { $0.side == nil }.flatMap(\.sets)
        let left = rows.filter { $0.side == .left }.flatMap(\.sets)
        let right = rows.filter { $0.side == .right }.flatMap(\.sets)
        if unilateral, let l = best(left), let r = best(right) {
            let sided = min(l, r)
            return best(bilateral).map { max($0, sided) } ?? sided
        }
        return best(bilateral + left + right)
    }

    /// (date, score) for every day the exercise has sets, oldest first.
    public static func scoreSeries(_ data: GymData, exerciseId: String) -> [(date: DayKey, score: Double)] {
        guard let exercise = data.exercise(exerciseId) else { return [] }
        let rows = data.logs.filter { $0.exerciseId == exerciseId && !$0.sets.isEmpty }
        let byDate = Dictionary(grouping: rows, by: \.date)
        return byDate.keys.sorted().compactMap { date in
            sessionScore(byDate[date] ?? [], unilateral: exercise.unilateral).map { (date, $0) }
        }
    }

    /// 100 · score(latest session on/before `date`) / score(first session); nil before the first session.
    public static func index(_ series: [(date: DayKey, score: Double)], at date: DayKey) -> Double? {
        guard let first = series.first, first.date <= date else { return nil }
        let latest = series.last { $0.date <= date } ?? first
        return first.score > 0 ? 100 * latest.score / first.score : 100
    }

    /// Mean of every existing exercise's latest index on `date` (equal weight: a curl counts as much as a squat).
    /// nil when nothing is logged yet.
    public static func strengthScore(_ data: GymData, on date: DayKey) -> Double? {
        let indexes = data.exercises.compactMap { index(scoreSeries(data, exerciseId: $0.id), at: date) }
        guard !indexes.isEmpty else { return nil }
        return indexes.reduce(0, +) / Double(indexes.count)
    }

    /// Strength score at every day with a logged set (from…through when given), oldest first.
    public static func strengthSeries(_ data: GymData, from: DayKey? = nil, through: DayKey? = nil) -> [(date: DayKey, score: Double)] {
        let series = Dictionary(uniqueKeysWithValues: data.exercises.map { ($0.id, scoreSeries(data, exerciseId: $0.id)) })
        let dates = Set(data.logs.filter { !$0.sets.isEmpty && data.exercise($0.exerciseId) != nil }.map(\.date)).sorted()
        return dates.compactMap { date -> (date: DayKey, score: Double)? in
            if let from, date < from { return nil }
            if let through, date > through { return nil }
            let values = series.values.compactMap { index($0, at: date) }
            guard !values.isEmpty else { return nil }
            return (date, values.reduce(0, +) / Double(values.count))
        }
    }

    /// Strength score sampled every `stepDays` from `from` through `through` (the weekly chart). Days before the
    /// first log are omitted.
    public static func sampledStrengthSeries(_ data: GymData, from: DayKey, through: DayKey, stepDays: Int = 7) -> [(date: DayKey, score: Double)] {
        let series = data.exercises.map { scoreSeries(data, exerciseId: $0.id) }
        var result: [(date: DayKey, score: Double)] = []
        var date = from
        while date <= through {
            let values = series.compactMap { index($0, at: date) }
            if !values.isEmpty { result.append((date, values.reduce(0, +) / Double(values.count))) }
            date = date.adding(days: max(1, stepDays))
        }
        if let last = result.last, last.date < through {
            let values = series.compactMap { index($0, at: through) }
            if !values.isEmpty { result.append((through, values.reduce(0, +) / Double(values.count))) }
        }
        return result
    }

    /// The full history of one exercise.
    public static func history(_ data: GymData, exerciseId: String) -> ExerciseHistory? {
        guard let exercise = data.exercise(exerciseId) else { return nil }
        let rows = data.logs.filter { $0.exerciseId == exerciseId && !$0.sets.isEmpty }
        let byDate = Dictionary(grouping: rows, by: \.date)
        var sessions: [ExerciseSession] = []
        var bestSoFar: Double?
        var firstScore: Double?
        for date in byDate.keys.sorted() {
            let dayRows = byDate[date] ?? []
            guard let score = sessionScore(dayRows, unilateral: exercise.unilateral) else { continue }
            let sets = dayRows.filter { $0.side == nil }.flatMap(\.sets)
            let left = dayRows.filter { $0.side == .left }.flatMap(\.sets)
            let right = dayRows.filter { $0.side == .right }.flatMap(\.sets)
            let all = sets + left + right
            let top = all.compactMap(\.weight).max()
            let previousTop = sessions.last?.topWeight
            let scoring: [SetEntry]
            if exercise.unilateral, let l = best(left), let r = best(right), sets.isEmpty {
                scoring = l <= r ? left : right
            } else {
                scoring = all
            }
            if firstScore == nil { firstScore = score }
            let session = ExerciseSession(
                date: date, sets: sets, left: left, right: right, score: score, topWeight: top,
                volume: all.reduce(0) { $0 + $1.volume }, totalReps: all.reduce(0) { $0 + $1.reps },
                bestSet: scoring.max { e1RM($0) < e1RM($1) },
                isBest: bestSoFar.map { score > $0 + 1e-9 } ?? false,
                topWeightChange: (top != nil && previousTop != nil) ? top! - previousTop! : nil,
                index: (firstScore ?? 0) > 0 ? 100 * score / firstScore! : 100
            )
            bestSoFar = max(bestSoFar ?? score, score)
            sessions.append(session)
        }
        let loggedWeights = rows.flatMap(\.sets).contains { $0.weight != nil }
        return ExerciseHistory(exercise: exercise, sessions: sessions, isBodyweight: exercise.bodyweight || (!rows.isEmpty && !loggedWeights))
    }

    /// The session for one day (nil when nothing was logged).
    public static func session(_ data: GymData, exerciseId: String, on date: DayKey) -> ExerciseSession? {
        history(data, exerciseId: exerciseId)?.sessions.first { $0.date == date }
    }
}

/// A progression suggestion ("Next target · 140 × 8 × 4 · then add 5 lb").
public struct NextTarget: Hashable, Sendable {
    /// kg; nil for bodyweight.
    public var weightKg: Double?
    public var reps: Int
    public var sets: Int
    /// True when the last session hit every target rep, so the weight goes up by `incrementKg`.
    public var increase: Bool
    public var incrementKg: Double
}

extension Scoring {
    /// Double progression on the exercise's target: when the latest session reached the top of the rep range on at
    /// least `sets` sets at its top weight, suggest top weight + one plate step; otherwise repeat the top weight and
    /// aim for the top of the range. Bodyweight exercises add a rep instead. nil without history or a target.
    public static func nextTarget(_ data: GymData, exerciseId: String) -> NextTarget? {
        guard let history = history(data, exerciseId: exerciseId), let latest = history.latest,
              let spec = history.exercise.targetSpec else { return nil }
        let increment = data.settings.unit.incrementKg
        if history.isBodyweight {
            let bestReps = latest.allSets.map(\.reps).max() ?? spec.repsLow
            return NextTarget(weightKg: nil, reps: max(spec.repsLow, bestReps + 1), sets: spec.sets, increase: false, incrementKg: 0)
        }
        guard let top = latest.topWeight else { return nil }
        let working: [SetEntry]
        if history.exercise.unilateral, !latest.left.isEmpty, !latest.right.isEmpty {
            let l = latest.left.filter { $0.weight == top }.filter { $0.reps >= spec.repsHigh }.count
            let r = latest.right.filter { $0.weight == top }.filter { $0.reps >= spec.repsHigh }.count
            working = Array(repeating: SetEntry(weight: top, reps: spec.repsHigh), count: min(l, r))
        } else {
            working = latest.allSets.filter { $0.weight == top && $0.reps >= spec.repsHigh }
        }
        let hit = working.count >= spec.sets
        return NextTarget(weightKg: hit ? top + increment : top, reps: hit ? spec.repsLow : spec.repsHigh, sets: spec.sets,
                          increase: hit, incrementKg: increment)
    }
}
