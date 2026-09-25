import Foundation

// The domain, mirroring the Atlas gym plugin (atlas.gym.v1) plus the few fields the Thuban design adds
// (bodyweight flag, per-workout rest timer, override notes, the in-progress session). Every array is kept in
// display order — array position IS the order (Atlas's `ord`). All decoders are tolerant: missing keys take
// defaults so older files keep loading.

// MARK: - Workout

public enum WorkoutKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case training, rest, flex
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .training: return "Training"
        case .rest: return "Rest"
        case .flex: return "Flex"
        }
    }
}

public struct Workout: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Atlas `rest`: a rest day (no targets; auto-completes in a cycle when its day passes).
    public var rest: Bool
    /// Atlas `flex`: "log anything" day. Atlas's own data has rest+flex both true on its rest day — `kind` gives rest
    /// precedence, and both flags are kept verbatim so a re-import round-trips.
    public var flex: Bool
    /// Rest timer between sets, seconds. nil → `GymSettings.restSeconds`.
    public var restSeconds: Int?
    /// Sync: sort key that keeps the list order stable when two devices merge (see `GymMerge`). nil until stamped.
    public var order: Double?
    /// Sync: when this record last changed (last writer wins). nil = legacy / never stamped.
    public var updatedAt: Date?

    public init(id: String = GymID.make("gw"), name: String, rest: Bool = false, flex: Bool = false, restSeconds: Int? = nil) {
        self.id = id
        self.name = name
        self.rest = rest
        self.flex = flex
        self.restSeconds = restSeconds
    }

    public var kind: WorkoutKind {
        get { rest ? .rest : (flex ? .flex : .training) }
        set {
            rest = newValue == .rest
            flex = newValue == .flex
        }
    }

    public var isRest: Bool { rest }

    enum CodingKeys: String, CodingKey { case id, name, rest, flex, restSeconds, order, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        rest = try c.decodeIfPresent(Bool.self, forKey: .rest) ?? false
        flex = try c.decodeIfPresent(Bool.self, forKey: .flex) ?? false
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds)
        order = try c.decodeIfPresent(Double.self, forKey: .order)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Exercise

public struct Exercise: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var workoutId: String
    public var name: String
    /// Each set logs a left and a right side; e1RM uses the weaker side.
    public var unilateral: Bool
    /// Logged without weight; scored by reps and shown as "BW".
    public var bodyweight: Bool
    /// Free text like "3×8" or "4 × 6–8" (parse with `TargetSpec`).
    public var target: String
    /// Sync: sort key (see `Workout.order`).
    public var order: Double?
    /// Sync: last change (see `Workout.updatedAt`).
    public var updatedAt: Date?

    public init(id: String = GymID.make("ge"), workoutId: String, name: String, unilateral: Bool = false, bodyweight: Bool = false, target: String = "") {
        self.id = id
        self.workoutId = workoutId
        self.name = name
        self.unilateral = unilateral
        self.bodyweight = bodyweight
        self.target = target
    }

    public var targetSpec: TargetSpec? { TargetSpec(target) }

    enum CodingKeys: String, CodingKey { case id, workoutId, name, unilateral, bodyweight, target, order, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        workoutId = try c.decodeIfPresent(String.self, forKey: .workoutId) ?? ""
        name = try c.decode(String.self, forKey: .name)
        unilateral = try c.decodeIfPresent(Bool.self, forKey: .unilateral) ?? false
        bodyweight = try c.decodeIfPresent(Bool.self, forKey: .bodyweight) ?? false
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? ""
        order = try c.decodeIfPresent(Double.self, forKey: .order)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

// MARK: - Logs

/// nil side = a bilateral exercise; L / R = one side of a unilateral exercise.
public enum Side: String, Codable, CaseIterable, Sendable, Identifiable {
    case left = "L", right = "R"
    public var id: String { rawValue }
    public var label: String { self == .left ? "Left" : "Right" }
}

/// One set. `weight` is kilograms (canonical; never rounded on conversion). nil = bodyweight (scored by reps).
public struct SetEntry: Codable, Hashable, Sendable {
    public var weight: Double?
    public var reps: Int
    /// Sync: stable id (`gs-…`, or `<log id>~NNN` for sets written before sync existed). nil until the app stamps
    /// the document (`GymData.stamped(from:)`), so pure mutations and tests stay value-comparable.
    public var id: String?
    /// Sync: when the set was logged (orders the sets of a row after a merge).
    public var loggedAt: Date?
    /// Sync: last change (an edit of weight / reps).
    public var updatedAt: Date?

    public init(weight: Double?, reps: Int) {
        self.weight = weight.flatMap { $0 > 0 ? $0 : nil }
        self.reps = max(0, reps)
    }

    public var isBodyweight: Bool { weight == nil }
    /// kg × reps (0 for bodyweight).
    public var volume: Double { (weight ?? 0) * Double(reps) }
}

/// All sets of one exercise on one day for one side (Atlas `logs` row).
public struct LogEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var exerciseId: String
    public var date: DayKey
    public var side: Side?
    public var sets: [SetEntry]

    public init(id: String = GymID.make("gl"), exerciseId: String, date: DayKey, side: Side? = nil, sets: [SetEntry] = []) {
        self.id = id
        self.exerciseId = exerciseId
        self.date = date
        self.side = side
        self.sets = sets
    }
}

// MARK: - Completions

/// A finished workout (append-only history). `start` / `end` are local `HH:mm` or "" when unknown.
public struct Completion: Codable, Hashable, Sendable, Identifiable {
    public var workoutId: String
    public var date: DayKey
    /// Epoch milliseconds when it was recorded (Atlas `ts`).
    public var ts: Double
    public var start: String
    public var end: String
    /// True for a rest slot the app completed by itself when its day passed.
    public var auto: Bool
    /// Sync: when this record was written (beats an older deletion of the same id, e.g. a restored backup).
    public var updatedAt: Date?

    public init(workoutId: String, date: DayKey, ts: Double, start: String = "", end: String = "", auto: Bool = false) {
        self.workoutId = workoutId
        self.date = date
        self.ts = ts
        self.start = start
        self.end = end
        self.auto = auto
    }

    public var id: String { "\(date.rawValue)|\(workoutId)|\(Int(ts))" }

    /// Minutes between start and end (wraps midnight), nil when unknown.
    public var durationMinutes: Int? { ClockTime.duration(start: start, end: end) }

    enum CodingKeys: String, CodingKey { case workoutId, date, ts, start, end, auto, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workoutId = try c.decode(String.self, forKey: .workoutId)
        date = try c.decode(DayKey.self, forKey: .date)
        ts = try c.decodeIfPresent(Double.self, forKey: .ts) ?? 0
        start = try c.decodeIfPresent(String.self, forKey: .start) ?? ""
        end = try c.decodeIfPresent(String.self, forKey: .end) ?? ""
        auto = try c.decodeIfPresent(Bool.self, forKey: .auto) ?? false
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// The session in progress (Today's "Pull in progress · 31:12"). Persisted so a relaunch resumes it.
public struct ActiveSession: Codable, Hashable, Sendable {
    public var workoutId: String
    public var date: DayKey
    public var startedAt: Date

    public init(workoutId: String, date: DayKey, startedAt: Date) {
        self.workoutId = workoutId
        self.date = date
        self.startedAt = startedAt
    }
}

// MARK: - Settings

public enum WeightUnit: String, Codable, CaseIterable, Sendable, Identifiable {
    case kg, lbs
    public var id: String { rawValue }
}

public enum PlanType: String, Codable, CaseIterable, Sendable, Identifiable {
    case weekly, cycle
    public var id: String { rawValue }
    public var label: String { self == .weekly ? "Weekly" : "Cycle" }
}

public struct OpeningHours: Codable, Hashable, Sendable {
    /// `HH:mm` or "" (unconstrained).
    public var open: String
    public var close: String

    public init(open: String = "", close: String = "") {
        self.open = open
        self.close = close
    }

    public var isSet: Bool { ClockTime.minutes(open) != nil && ClockTime.minutes(close) != nil }
}

public struct GymSettings: Codable, Hashable, Sendable {
    /// Display unit only. Storage is always kg.
    public var unit: WeightUnit
    public var address: String
    /// Keyed by `Weekday.rawValue`.
    public var hours: [String: OpeningHours]
    /// Minutes; the duration fallback when a workout has no timed history.
    public var defaultDuration: Int
    /// Default rest timer between sets, seconds.
    public var restSeconds: Int

    public init(unit: WeightUnit = .kg, address: String = "", hours: [String: OpeningHours] = [:], defaultDuration: Int = 75, restSeconds: Int = 120) {
        self.unit = unit
        self.address = address
        self.hours = hours
        self.defaultDuration = defaultDuration
        self.restSeconds = restSeconds
    }

    public func hours(for day: Weekday) -> OpeningHours { hours[day.rawValue] ?? OpeningHours() }

    enum CodingKeys: String, CodingKey { case unit, address, hours, defaultDuration, restSeconds }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = try c.decodeIfPresent(WeightUnit.self, forKey: .unit) ?? .kg
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        hours = try c.decodeIfPresent([String: OpeningHours].self, forKey: .hours) ?? [:]
        defaultDuration = try c.decodeIfPresent(Int.self, forKey: .defaultDuration) ?? 75
        restSeconds = try c.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 120
    }
}

// MARK: - Plan

public struct Plan: Codable, Hashable, Sendable {
    public var type: PlanType
    /// `Weekday.rawValue` → workout id. A missing key = nothing planned (a rest day in weekly mode).
    public var weekly: [String: String]
    /// Ordered workout ids; duplicates allowed.
    public var cycle: [String]
    /// Index into `cycle` of the NEXT workout to do. Only a completion moves it (or rest auto-complete).
    public var position: Int

    public init(type: PlanType = .weekly, weekly: [String: String] = [:], cycle: [String] = [], position: Int = 0) {
        self.type = type
        self.weekly = weekly
        self.cycle = cycle
        self.position = position
    }

    public func weeklyWorkoutId(_ day: Weekday) -> String? { weekly[day.rawValue] }

    /// `position` wrapped into the cycle (0 when the cycle is empty).
    public var normalizedPosition: Int {
        guard !cycle.isEmpty else { return 0 }
        return ((position % cycle.count) + cycle.count) % cycle.count
    }

    enum CodingKeys: String, CodingKey { case type, weekly, cycle, position }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(PlanType.self, forKey: .type) ?? .weekly
        weekly = try c.decodeIfPresent([String: String].self, forKey: .weekly) ?? [:]
        cycle = try c.decodeIfPresent([String].self, forKey: .cycle) ?? []
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
    }
}

/// A one-day deviation: skip the day, or do another workout. Never moves the cycle pointer. Expires 90 days after
/// its date.
public struct PlanOverride: Codable, Hashable, Sendable, Identifiable {
    public static let skipValue = "skip"

    public var date: DayKey
    /// nil = skip.
    public var workoutId: String?
    /// Optional reason shown on the Plan screen ("Career fair, 10–3").
    public var note: String?
    /// Sync: last change (an override re-made after a deletion wins when it is newer).
    public var updatedAt: Date?

    public init(date: DayKey, workoutId: String?, note: String? = nil) {
        self.date = date
        self.workoutId = workoutId
        self.note = note
    }

    public var id: String { date.rawValue }
    public var isSkip: Bool { workoutId == nil }
}

/// An exercise pulled from another workout into one day's session.
public struct PlanExtra: Codable, Hashable, Sendable, Identifiable {
    public var date: DayKey
    public var exerciseId: String
    /// Sync: when it was added (also orders a day's extras after a merge).
    public var updatedAt: Date?

    public init(date: DayKey, exerciseId: String) {
        self.date = date
        self.exerciseId = exerciseId
    }

    public var id: String { "\(date.rawValue)|\(exerciseId)" }
}

// MARK: - IDs

public enum GymID {
    /// Atlas-style ids: `gw-…` workouts, `ge-…` exercises, `gl-…` logs, `gs-…` sets: `<prefix>-<ms><random>`,
    /// the milliseconds in base 36.
    ///
    /// The millisecond part is strictly increasing within the process (two ids made in the same millisecond get
    /// consecutive values), so ids made one after another sort in the order they were made. Sets rely on this: a
    /// row's sets are ordered by `(loggedAt, id)` and `loggedAt` is whole seconds, so sets logged in the same second
    /// (quick taps, several sets stamped in one change) keep their logged order instead of an order decided by the
    /// random suffix. (Base 36 of today's milliseconds is 8 digits until 2059, so string order is numeric order.)
    public static func make(_ prefix: String) -> String {
        let time = String(clock.next(), radix: 36)
        let random = String(UInt32.random(in: 0...UInt32.max), radix: 36)
        return "\(prefix)-\(time)\(random)"
    }

    private static let clock = MonotonicMillis()

    private final class MonotonicMillis: @unchecked Sendable {
        private let lock = NSLock()
        private var last: UInt64 = 0

        func next() -> UInt64 {
            lock.lock(); defer { lock.unlock() }
            last = max(UInt64(Date().timeIntervalSince1970 * 1000), last + 1)
            return last
        }
    }
}
