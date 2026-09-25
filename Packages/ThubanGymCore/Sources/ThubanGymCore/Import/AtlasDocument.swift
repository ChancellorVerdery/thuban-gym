import Foundation

/// The single JSON document the Atlas import SQL returns (see `AtlasImporter.sql(email:)`), or that a user saved
/// to a file. Rows mirror Atlas's `gym.*` tables in `ord` order, without `user_id`. Decoding is tolerant: null /
/// missing columns take defaults, numbers may arrive as strings, and unknown keys are ignored.
public struct AtlasDocument: Decodable, Sendable, Equatable {
    public static let format = "thuban.atlas-gym.v1"

    public struct SettingsRow: Decodable, Sendable, Equatable {
        public var unit: String?
        public var address: String?
        /// jsonb in Atlas: a number of minutes (tolerates a numeric string).
        public var defaultDuration: Int?
        public var planType: String?
        public var cyclePosition: Int?

        enum CodingKeys: String, CodingKey { case unit, address, defaultDuration = "default_duration", planType = "plan_type", cyclePosition = "cycle_position" }

        public init(unit: String? = nil, address: String? = nil, defaultDuration: Int? = nil, planType: String? = nil, cyclePosition: Int? = nil) {
            self.unit = unit
            self.address = address
            self.defaultDuration = defaultDuration
            self.planType = planType
            self.cyclePosition = cyclePosition
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            unit = try c.decodeIfPresent(String.self, forKey: .unit)
            address = try c.decodeIfPresent(String.self, forKey: .address)
            defaultDuration = c.lenientDouble(.defaultDuration).map { Int($0.rounded()) }
            planType = try c.decodeIfPresent(String.self, forKey: .planType)
            cyclePosition = c.lenientDouble(.cyclePosition).map { Int($0) }
        }
    }

    public struct HoursRow: Decodable, Sendable, Equatable {
        public var day: String
        public var open: String?
        public var close: String?
    }

    public struct WorkoutRow: Decodable, Sendable, Equatable {
        public var id: String
        public var name: String?
        public var rest: Bool?
        public var flex: Bool?
    }

    public struct ExerciseRow: Decodable, Sendable, Equatable {
        public var id: String
        public var workoutId: String?
        public var name: String?
        public var unilateral: Bool?
        public var target: String?
        enum CodingKeys: String, CodingKey { case id, workoutId = "workout_id", name, unilateral, target }
    }

    public struct SetRow: Decodable, Sendable, Equatable {
        /// kg; nil / 0 = bodyweight.
        public var weight: Double?
        public var reps: Int

        enum CodingKeys: String, CodingKey { case weight, reps }

        public init(weight: Double?, reps: Int) {
            self.weight = weight
            self.reps = reps
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            weight = c.lenientDouble(.weight)
            reps = c.lenientDouble(.reps).map { Int($0.rounded()) } ?? 0
        }
    }

    public struct LogRow: Decodable, Sendable, Equatable {
        public var id: String?
        public var exerciseId: String
        public var date: String
        public var side: String?
        public var sets: [SetRow]

        enum CodingKeys: String, CodingKey { case id, exerciseId = "exercise_id", date, side, sets }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            exerciseId = try c.decode(String.self, forKey: .exerciseId)
            date = try c.decode(String.self, forKey: .date)
            side = try c.decodeIfPresent(String.self, forKey: .side)
            // jsonb: normally an array of {weight, reps}; tolerate null or a JSON-encoded string.
            if let sets = try? c.decodeIfPresent([SetRow].self, forKey: .sets) {
                self.sets = sets
            } else if let text = try? c.decodeIfPresent(String.self, forKey: .sets), let data = text.data(using: .utf8),
                      let sets = try? JSONDecoder().decode([SetRow].self, from: data) {
                self.sets = sets
            } else {
                self.sets = []
            }
        }
    }

    public struct CompletionRow: Decodable, Sendable, Equatable {
        public var workoutId: String
        public var date: String
        /// Epoch milliseconds (numeric in Atlas).
        public var ts: Double?
        public var startTime: String?
        public var endTime: String?

        enum CodingKeys: String, CodingKey { case workoutId = "workout_id", date, ts, startTime = "start_time", endTime = "end_time" }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            workoutId = try c.decode(String.self, forKey: .workoutId)
            date = try c.decode(String.self, forKey: .date)
            ts = c.lenientDouble(.ts)
            startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
            endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        }
    }

    public struct WeeklyRow: Decodable, Sendable, Equatable {
        public var day: String
        public var workoutId: String?
        enum CodingKeys: String, CodingKey { case day, workoutId = "workout_id" }
    }

    public struct CycleRow: Decodable, Sendable, Equatable {
        public var position: Int?
        public var workoutId: String?
        enum CodingKeys: String, CodingKey { case position, workoutId = "workout_id" }
    }

    public struct OverrideRow: Decodable, Sendable, Equatable {
        public var date: String
        /// A workout id, or "skip" (null is read as skip too).
        public var workoutId: String?
        enum CodingKeys: String, CodingKey { case date, workoutId = "workout_id" }
    }

    public struct ExtraRow: Decodable, Sendable, Equatable {
        public var date: String
        public var exerciseId: String
        enum CodingKeys: String, CodingKey { case date, exerciseId = "exercise_id" }
    }

    public var format: String?
    /// The account the rows belong to (echoed back by the SQL; nil when the email matched no user).
    public var email: String?
    public var userFound: Bool
    public var exportedAt: String?
    public var settings: SettingsRow?
    public var hours: [HoursRow]
    public var workouts: [WorkoutRow]
    public var exercises: [ExerciseRow]
    public var logs: [LogRow]
    public var completions: [CompletionRow]
    public var planWeekly: [WeeklyRow]
    public var planCycle: [CycleRow]
    public var planOverrides: [OverrideRow]
    public var planExtras: [ExtraRow]

    enum CodingKeys: String, CodingKey {
        case format, email, userFound = "user_found", exportedAt = "exported_at", settings, hours, workouts, exercises, logs, completions,
             planWeekly = "plan_weekly", planCycle = "plan_cycle", planOverrides = "plan_overrides", planExtras = "plan_extras"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        userFound = try c.decodeIfPresent(Bool.self, forKey: .userFound) ?? true
        exportedAt = try c.decodeIfPresent(String.self, forKey: .exportedAt)
        // `settings` is one row; accept an array of rows too (first wins).
        if let row = try? c.decodeIfPresent(SettingsRow.self, forKey: .settings) {
            settings = row
        } else {
            settings = (try? c.decodeIfPresent([SettingsRow].self, forKey: .settings))?.first
        }
        hours = try c.decodeIfPresent([HoursRow].self, forKey: .hours) ?? []
        workouts = try c.decodeIfPresent([WorkoutRow].self, forKey: .workouts) ?? []
        exercises = try c.decodeIfPresent([ExerciseRow].self, forKey: .exercises) ?? []
        logs = try c.decodeIfPresent([LogRow].self, forKey: .logs) ?? []
        completions = try c.decodeIfPresent([CompletionRow].self, forKey: .completions) ?? []
        planWeekly = try c.decodeIfPresent([WeeklyRow].self, forKey: .planWeekly) ?? []
        planCycle = try c.decodeIfPresent([CycleRow].self, forKey: .planCycle) ?? []
        planOverrides = try c.decodeIfPresent([OverrideRow].self, forKey: .planOverrides) ?? []
        planExtras = try c.decodeIfPresent([ExtraRow].self, forKey: .planExtras) ?? []
    }

    /// Decodes psql output or a saved file: the first line that parses as a JSON object wins (psql may print
    /// notices around it).
    public static func decode(_ data: Data) throws -> AtlasDocument {
        let decoder = JSONDecoder()
        if let document = try? decoder.decode(AtlasDocument.self, from: data) { return document }
        let text = String(decoding: data, as: UTF8.self)
        var lastError: Error?
        for line in text.split(whereSeparator: \.isNewline) where line.first == "{" {
            do {
                return try decoder.decode(AtlasDocument.self, from: Data(line.utf8))
            } catch {
                lastError = error
            }
        }
        if let lastError { throw ThubanError.decoding("The Atlas document could not be read: \(describe(lastError))") }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        throw ThubanError.decoding(trimmed.isEmpty ? "Atlas returned nothing." : "Atlas did not return a JSON document.")
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .keyNotFound(let key, let context): return "missing \(key.stringValue) at \(path(context))"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default: return error.localizedDescription
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
    }
}

extension KeyedDecodingContainer {
    /// A number, a numeric string, or nil (null / missing / anything else).
    func lenientDouble(_ key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
