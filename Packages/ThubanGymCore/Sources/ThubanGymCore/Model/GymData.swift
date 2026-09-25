import Foundation

/// The whole local database: one Codable document (`gym.json`). Value type — the app holds one copy in `AppModel`,
/// mutates it through the `mutating` API in `GymData+Mutations.swift`, and `GymStore` writes it atomically.
public struct GymData: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var workouts: [Workout]
    public var exercises: [Exercise]
    public var logs: [LogEntry]
    public var completions: [Completion]
    public var plan: Plan
    public var overrides: [PlanOverride]
    public var extras: [PlanExtra]
    public var settings: GymSettings
    public var activeSession: ActiveSession?
    /// Last day the rest-slot auto-complete / expiry pass ran for (see `rollover(to:)`).
    public var lastRollover: DayKey?
    /// Provenance of the last Atlas import.
    public var importedAt: Date?
    public var importSource: String?

    public init(workouts: [Workout] = [], exercises: [Exercise] = [], logs: [LogEntry] = [], completions: [Completion] = [],
                plan: Plan = Plan(), overrides: [PlanOverride] = [], extras: [PlanExtra] = [], settings: GymSettings = GymSettings(),
                activeSession: ActiveSession? = nil, lastRollover: DayKey? = nil, importedAt: Date? = nil, importSource: String? = nil) {
        self.version = GymData.currentVersion
        self.workouts = workouts
        self.exercises = exercises
        self.logs = logs
        self.completions = completions
        self.plan = plan
        self.overrides = overrides
        self.extras = extras
        self.settings = settings
        self.activeSession = activeSession
        self.lastRollover = lastRollover
        self.importedAt = importedAt
        self.importSource = importSource
    }

    public static let empty = GymData()

    public var isEmpty: Bool { workouts.isEmpty && exercises.isEmpty && logs.isEmpty && completions.isEmpty }

    enum CodingKeys: String, CodingKey {
        case version, workouts, exercises, logs, completions, plan, overrides, extras, settings, activeSession, lastRollover, importedAt, importSource
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? GymData.currentVersion
        workouts = try c.decodeIfPresent([Workout].self, forKey: .workouts) ?? []
        exercises = try c.decodeIfPresent([Exercise].self, forKey: .exercises) ?? []
        logs = try c.decodeIfPresent([LogEntry].self, forKey: .logs) ?? []
        completions = try c.decodeIfPresent([Completion].self, forKey: .completions) ?? []
        plan = try c.decodeIfPresent(Plan.self, forKey: .plan) ?? Plan()
        overrides = try c.decodeIfPresent([PlanOverride].self, forKey: .overrides) ?? []
        extras = try c.decodeIfPresent([PlanExtra].self, forKey: .extras) ?? []
        settings = try c.decodeIfPresent(GymSettings.self, forKey: .settings) ?? GymSettings()
        activeSession = try c.decodeIfPresent(ActiveSession.self, forKey: .activeSession)
        lastRollover = try c.decodeIfPresent(DayKey.self, forKey: .lastRollover)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt)
        importSource = try c.decodeIfPresent(String.self, forKey: .importSource)
    }

    // MARK: - Lookups

    public func workout(_ id: String?) -> Workout? {
        guard let id else { return nil }
        return workouts.first { $0.id == id }
    }

    public func exercise(_ id: String?) -> Exercise? {
        guard let id else { return nil }
        return exercises.first { $0.id == id }
    }

    /// A workout's exercises in order.
    public func exercises(in workoutId: String) -> [Exercise] {
        exercises.filter { $0.workoutId == workoutId }
    }

    public func override(on date: DayKey) -> PlanOverride? {
        overrides.first { $0.date == date }
    }

    /// Exercise ids pulled into `date`, in add order.
    public func extraIds(on date: DayKey) -> [String] {
        extras.filter { $0.date == date }.map(\.exerciseId)
    }

    public func completions(on date: DayKey) -> [Completion] {
        completions.filter { $0.date == date }
    }

    /// The log row for exercise + day + side (nil side = bilateral).
    public func log(exerciseId: String, date: DayKey, side: Side?) -> LogEntry? {
        logs.first { $0.exerciseId == exerciseId && $0.date == date && $0.side == side }
    }

    /// Sets logged for exercise + day + side.
    public func sets(exerciseId: String, date: DayKey, side: Side? = nil) -> [SetEntry] {
        log(exerciseId: exerciseId, date: date, side: side)?.sets ?? []
    }

    /// Every log row of an exercise on a day (both sides for a unilateral exercise).
    public func logs(exerciseId: String, date: DayKey) -> [LogEntry] {
        logs.filter { $0.exerciseId == exerciseId && $0.date == date }
    }

    /// Dates with at least one set for this exercise, ascending.
    public func loggedDates(exerciseId: String) -> [DayKey] {
        Array(Set(logs.filter { $0.exerciseId == exerciseId && !$0.sets.isEmpty }.map(\.date))).sorted()
    }

    /// The most recent day before `date` with sets for this exercise ("Last time, Sun Sep 20 · …").
    public func previousSessionDate(exerciseId: String, before date: DayKey) -> DayKey? {
        loggedDates(exerciseId: exerciseId).last { $0 < date }
    }

    /// Rest timer for a workout (its own value or the global default).
    public func restSeconds(for workoutId: String?) -> Int {
        workout(workoutId)?.restSeconds ?? settings.restSeconds
    }
}
