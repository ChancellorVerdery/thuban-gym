import Foundation

// Rules for logging a session set by set (the iPhone's full-screen logger and the iPad's session column): which
// set is next, what to pre-fill, how far the session is, and the rest countdown. Pure functions over `GymData`.

/// A set being typed: weight in kg (nil = bodyweight, 0 allowed while editing) and reps.
public struct SetDraft: Hashable, Sendable {
    public var weightKg: Double?
    public var reps: Int

    public init(weightKg: Double?, reps: Int) {
        self.weightKg = weightKg
        self.reps = max(0, reps)
    }

    /// The set to store: a weight ≤ 0 is stored as bodyweight.
    public var entry: SetEntry { SetEntry(weight: weightKg, reps: reps) }
    /// Epley e1RM of the draft (kg, or reps for bodyweight).
    public var e1RM: Double { Scoring.e1RM(entry) }
}

/// One row of the set table (done, the one being logged, or still to come).
public struct SetSlot: Hashable, Sendable, Identifiable {
    public enum State: String, Sendable { case done, current, upcoming }

    /// 0-based set number within the exercise (for unilateral exercises: the L / R pair).
    public var index: Int
    public var state: State
    /// Logged set (done rows). For a unilateral pair: the left side.
    public var logged: SetEntry?
    /// Right side of a unilateral pair.
    public var loggedRight: SetEntry?
    /// Same set number in the previous session ("last 135×7").
    public var previous: SetEntry?

    public var id: Int { index }
}

/// Where the session is: segments for the progress line and the position within the exercise list.
public struct SessionProgress: Hashable, Sendable {
    public struct Segment: Hashable, Sendable {
        public var exerciseId: String
        public var done: Bool
    }

    public var segments: [Segment]
    public var logged: Int
    public var planned: Int
}

public enum SessionLogic {
    /// Sets logged for an exercise on a day, counting a unilateral L + R pair as ONE set.
    public static func loggedSetCount(_ data: GymData, exercise: Exercise, on date: DayKey) -> Int {
        if exercise.unilateral {
            let left = data.sets(exerciseId: exercise.id, date: date, side: .left).count
            let right = data.sets(exerciseId: exercise.id, date: date, side: .right).count
            let both = data.sets(exerciseId: exercise.id, date: date, side: nil).count
            return max(left, right) + both
        }
        return data.sets(exerciseId: exercise.id, date: date, side: nil).count
    }

    /// For a unilateral exercise: the side the next entry goes to (left first; right until the pair is complete).
    public static func nextSide(_ data: GymData, exercise: Exercise, on date: DayKey) -> Side? {
        guard exercise.unilateral else { return nil }
        let left = data.sets(exerciseId: exercise.id, date: date, side: .left).count
        let right = data.sets(exerciseId: exercise.id, date: date, side: .right).count
        return right < left ? .right : .left
    }

    /// The set table: every logged set, then the rest of the target as upcoming rows (the first one current).
    /// At least one current row is always present, so a set beyond the target can still be logged.
    public static func slots(_ data: GymData, exercise: Exercise, on date: DayKey) -> [SetSlot] {
        let previousDate = data.previousSessionDate(exerciseId: exercise.id, before: date)
        func previousSet(_ index: Int, side: Side?) -> SetEntry? {
            guard let previousDate else { return nil }
            var sets = data.sets(exerciseId: exercise.id, date: previousDate, side: side)
            if sets.isEmpty, exercise.unilateral { sets = data.sets(exerciseId: exercise.id, date: previousDate, side: nil) }
            return index < sets.count ? sets[index] : sets.last
        }
        var slots: [SetSlot] = []
        let target = exercise.targetSpec?.sets ?? 0
        if exercise.unilateral {
            let left = data.sets(exerciseId: exercise.id, date: date, side: .left)
            let right = data.sets(exerciseId: exercise.id, date: date, side: .right)
            let complete = min(left.count, right.count)
            for i in 0..<complete {
                slots.append(SetSlot(index: i, state: .done, logged: left[i], loggedRight: right[i], previous: previousSet(i, side: .left)))
            }
            // A half-logged pair (left done, right not) is the current row.
            let current = max(left.count, right.count) > complete ? complete : nil
            if let current {
                slots.append(SetSlot(index: current, state: .current, logged: left.count > current ? left[current] : nil,
                                     loggedRight: right.count > current ? right[current] : nil, previous: previousSet(current, side: .left)))
            }
            let start = slots.count
            for i in start..<max(start + (current == nil ? 1 : 0), target) {
                slots.append(SetSlot(index: i, state: i == start && current == nil ? .current : .upcoming, previous: previousSet(i, side: .left)))
            }
        } else {
            let logged = data.sets(exerciseId: exercise.id, date: date, side: nil)
            for (i, set) in logged.enumerated() {
                slots.append(SetSlot(index: i, state: .done, logged: set, previous: previousSet(i, side: nil)))
            }
            let start = logged.count
            for i in start..<max(start + 1, target) {
                slots.append(SetSlot(index: i, state: i == start ? .current : .upcoming, previous: previousSet(i, side: nil)))
            }
        }
        return slots
    }

    /// What to pre-fill for the next set: the last set logged today on that side; else the progression target
    /// (`Scoring.nextTarget`); else the same set number last time; else the target's reps with no weight.
    public static func suggestion(_ data: GymData, exercise: Exercise, on date: DayKey, side: Side?) -> SetDraft {
        let spec = exercise.targetSpec
        let today = data.sets(exerciseId: exercise.id, date: date, side: side)
        if let last = today.last { return SetDraft(weightKg: last.weight, reps: last.reps) }
        if side == .right, let left = data.sets(exerciseId: exercise.id, date: date, side: .left).last {
            return SetDraft(weightKg: left.weight, reps: left.reps)
        }
        if let target = Scoring.nextTarget(data, exerciseId: exercise.id) {
            return SetDraft(weightKg: target.weightKg, reps: target.reps)
        }
        if let previousDate = data.previousSessionDate(exerciseId: exercise.id, before: date) {
            let sets = data.logs(exerciseId: exercise.id, date: previousDate).flatMap(\.sets)
            if let first = sets.first { return SetDraft(weightKg: first.weight, reps: first.reps) }
        }
        return SetDraft(weightKg: exercise.bodyweight ? nil : 0, reps: spec?.repsHigh ?? 8)
    }

    /// The best e1RM before `date` (for "vs best") and the previous session's score (for "vs last").
    public static func references(_ data: GymData, exerciseId: String, before date: DayKey) -> (last: Double?, best: Double?) {
        guard let history = Scoring.history(data, exerciseId: exerciseId) else { return (nil, nil) }
        let earlier = history.sessions.filter { $0.date < date }
        return (earlier.last?.score, earlier.map(\.score).max())
    }

    /// Progress line: one segment per target set, in session order; logged sets beyond a target are not drawn.
    public static func progress(_ data: GymData, items: [SessionExercise], on date: DayKey) -> SessionProgress {
        var segments: [SessionProgress.Segment] = []
        var logged = 0
        for item in items {
            let target = item.exercise.targetSpec?.sets ?? 0
            let count = loggedSetCount(data, exercise: item.exercise, on: date)
            logged += min(count, target)
            for i in 0..<target { segments.append(.init(exerciseId: item.id, done: i < count)) }
        }
        return SessionProgress(segments: segments, logged: logged, planned: segments.count)
    }

    /// True once an exercise has its target number of sets (exercises without a target are never "finished").
    public static func isFinished(_ data: GymData, exercise: Exercise, on date: DayKey) -> Bool {
        let target = exercise.targetSpec?.sets ?? 0
        return target > 0 && loggedSetCount(data, exercise: exercise, on: date) >= target
    }

    /// The exercise to log next after `current`: the first unfinished one after it (wrapping), nil when all are done.
    public static func nextExercise(_ data: GymData, items: [SessionExercise], after current: String?, on date: DayKey) -> SessionExercise? {
        guard !items.isEmpty else { return nil }
        let start = items.firstIndex { $0.id == current }.map { $0 + 1 } ?? 0
        for offset in 0..<items.count {
            let item = items[(start + offset) % items.count]
            if !isFinished(data, exercise: item.exercise, on: date) { return item }
        }
        return nil
    }
}

// MARK: - Rest countdown

/// The rest timer between sets, anchored to the wall clock so it keeps counting while the app is in the background.
public struct RestCountdown: Codable, Hashable, Sendable {
    public var endsAt: Date
    /// Length of the whole rest (grows when time is added past it).
    public var total: TimeInterval

    public init(seconds: Int, now: Date = Date()) {
        total = TimeInterval(max(0, seconds))
        endsAt = now.addingTimeInterval(total)
    }

    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
    public func isFinished(at now: Date) -> Bool { remaining(at: now) <= 0 }

    /// 0…1 of the rest still to go (the ring).
    public func fractionRemaining(at now: Date) -> Double {
        total > 0 ? min(1, remaining(at: now) / total) : 0
    }

    /// ±15 s: moves the end, never below now; the total grows when the remaining time exceeds it.
    public mutating func adjust(by seconds: TimeInterval, now: Date = Date()) {
        let remaining = max(0, self.remaining(at: now) + seconds)
        endsAt = now.addingTimeInterval(remaining)
        total = max(total, remaining)
    }
}
