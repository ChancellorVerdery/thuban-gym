import Foundation

/// What an import would bring in — shown BEFORE anything is replaced (Settings → Import from Atlas).
public struct ImportSummary: Hashable, Sendable {
    public var email: String?
    public var workoutNames: [String]
    public var workouts: Int
    public var exercises: Int
    public var unilateralExercises: Int
    public var bodyweightExercises: Int
    /// Log rows (exercise + day + side) and the sets inside them.
    public var logRows: Int
    public var sets: Int
    public var completions: Int
    public var firstSession: DayKey?
    public var lastSession: DayKey?
    public var overrides: Int
    public var extras: Int
    public var planType: PlanType
    public var cycleLength: Int
    /// Name of the workout the cycle pointer is on ("pointer on Pull (day 2)").
    public var pointerWorkout: String?
    public var pointerIndex: Int
    public var weeklyDays: Int
    public var unit: WeightUnit
    /// Rows that were dropped or repaired, in plain words ("2 exercises point at a missing workout").
    public var warnings: [String]

    public var isEmpty: Bool { workouts == 0 && exercises == 0 && logRows == 0 && completions == 0 }
}

/// A decoded, converted import that has not been applied yet.
public struct AtlasImport: Sendable {
    public var data: GymData
    public var summary: ImportSummary
}

/// One-time (re-runnable) import of the Atlas gym plugin. READ-ONLY by construction: the SQL is a single SELECT
/// inside a `BEGIN READ ONLY … ROLLBACK` transaction, sent over `ssh -o BatchMode=yes <host> docker exec -i
/// stack-postgres-1 psql … -At` on stdin. The whole account comes back as ONE JSON document (`AtlasDocument`).
/// The same document can be imported from a file. Nothing here writes local data — see `AppModel.applyImport`.
public struct AtlasImporter: Sendable {
    public static let sshPath = "/usr/bin/ssh"
    public static let container = "stack-postgres-1"
    public static let databaseUser = "atlas_user"
    public static let database = "atlas"
    public static let defaultTimeout: TimeInterval = 60

    public var host: String
    public var email: String
    public var runner: CommandRunner
    public var timeout: TimeInterval

    public init(host: String = Preferences.defaultAtlasHost, email: String = Preferences.defaultAtlasEmail,
                runner: CommandRunner = ProcessRunner(), timeout: TimeInterval = AtlasImporter.defaultTimeout) {
        self.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.runner = runner
        self.timeout = timeout
    }

    // MARK: Command

    /// `ssh` arguments (the executable is `sshPath`). The remote command is fixed; only the host varies.
    public func sshArguments() throws -> [String] {
        try AtlasImporter.validateHost(host)
        return ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host,
                "docker", "exec", "-i", AtlasImporter.container,
                "psql", "-U", AtlasImporter.databaseUser, "-d", AtlasImporter.database, "-At"]
    }

    /// Human-readable command for the Settings pane ("ssh beelink docker exec …").
    public var commandDescription: String {
        "ssh \(host.isEmpty ? "<host>" : host) docker exec -i \(AtlasImporter.container) psql -U \(AtlasImporter.databaseUser) -d \(AtlasImporter.database) -At"
    }

    public static func validateHost(_ host: String) throws {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_@:[]"))
        guard !host.isEmpty, !host.hasPrefix("-"), host.unicodeScalars.allSatisfy(allowed.contains) else {
            throw ThubanError.invalid("“\(host)” is not a valid ssh host.")
        }
    }

    public static func validateEmail(_ email: String) throws {
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        let forbidden = CharacterSet(charactersIn: "'\"\\;`$").union(.whitespacesAndNewlines).union(.controlCharacters)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."),
              email.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else {
            throw ThubanError.invalid("“\(email)” is not a valid email address.")
        }
    }

    /// The psql script: quiet, stop on error, one read-only transaction, one SELECT returning one JSON line.
    public static func sql(email: String) throws -> String {
        try validateEmail(email)
        let literal = "'" + email.replacingOccurrences(of: "'", with: "''") + "'"
        func rows(_ table: String, _ columns: [String]) -> String {
            let fields = columns.map { "'\($0)', t.\($0)" }.joined(separator: ", ")
            return "COALESCE((SELECT json_agg(json_build_object(\(fields)) ORDER BY t.ord) FROM gym.\(table) t WHERE t.user_id = (SELECT id FROM u)), '[]'::json)"
        }
        return """
        \\set QUIET on
        \\set ON_ERROR_STOP on
        BEGIN TRANSACTION READ ONLY;
        WITH u AS (SELECT id FROM auth.users WHERE lower(email) = lower(\(literal)) ORDER BY created_at LIMIT 1)
        SELECT json_build_object(
          'format', '\(AtlasDocument.format)',
          'email', \(literal),
          'user_found', EXISTS (SELECT 1 FROM u),
          'exported_at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
          'settings', (SELECT json_build_object('unit', t.unit, 'address', t.address, 'default_duration', t.default_duration, 'plan_type', t.plan_type, 'cycle_position', t.cycle_position) FROM gym.settings t WHERE t.user_id = (SELECT id FROM u) ORDER BY t.ord LIMIT 1),
          'hours', \(rows("hours", ["day", "open", "close"])),
          'workouts', \(rows("workouts", ["id", "name", "rest", "flex"])),
          'exercises', \(rows("exercises", ["id", "workout_id", "name", "unilateral", "target"])),
          'logs', \(rows("logs", ["id", "exercise_id", "date", "side", "sets"])),
          'completions', \(rows("completions", ["workout_id", "date", "ts", "start_time", "end_time"])),
          'plan_weekly', \(rows("plan_weekly", ["day", "workout_id"])),
          'plan_cycle', \(rows("plan_cycle", ["position", "workout_id"])),
          'plan_overrides', \(rows("plan_overrides", ["date", "workout_id"])),
          'plan_extras', \(rows("plan_extras", ["date", "exercise_id"]))
        )::text;
        ROLLBACK;

        """
    }

    // MARK: Fetch

    /// Runs the SQL over ssh and decodes the document. Throws `ThubanError.importFailed` for ssh / docker / psql
    /// failures (with their stderr) and `ThubanError.decoding` for unreadable output.
    public func fetch() async throws -> AtlasDocument {
        let arguments = try sshArguments()
        let script = try AtlasImporter.sql(email: email)
        let result = try await runner.run(executable: AtlasImporter.sshPath, arguments: arguments, stdin: Data(script.utf8), timeout: timeout)
        guard result.status == 0 else {
            let detail = result.stderrText.isEmpty ? "exit status \(result.status)" : result.stderrText
            throw ThubanError.importFailed("Atlas could not be read (\(detail)).")
        }
        let document = try AtlasDocument.decode(result.stdout)
        guard document.userFound else { throw ThubanError.importFailed("Atlas has no account with the email \(email).") }
        return document
    }

    /// Reads a saved document (the same JSON the SQL returns).
    public static func document(fromFile url: URL) throws -> AtlasDocument {
        let data: Data
        do { data = try Data(contentsOf: url) } catch { throw ThubanError.importFailed("\(url.lastPathComponent) could not be opened: \(error.localizedDescription)") }
        let document = try AtlasDocument.decode(data)
        guard document.userFound else { throw ThubanError.importFailed("That file has no Atlas account in it.") }
        return document
    }

    /// fetch + convert: the dry run. Nothing is written anywhere.
    public func dryRun(now: Date = Date()) async throws -> AtlasImport {
        try AtlasImporter.convert(try await fetch(), source: "atlas:\(host)", now: now)
    }

    // MARK: Convert

    /// Maps Atlas's cycle pointer (an index into its full slot list, empty slots included) onto the list of slots
    /// that survived the import: the first surviving slot at or after it, wrapping around.
    static func alignedCyclePosition(atlasPosition: Int, atlasCount: Int, survivingIndexes: [Int]) -> Int {
        guard !survivingIndexes.isEmpty, atlasCount > 0 else { return 0 }
        let pointer = ((atlasPosition % atlasCount) + atlasCount) % atlasCount
        return survivingIndexes.firstIndex { $0 >= pointer } ?? 0
    }

    /// Builds a fresh `GymData` from the document (arrays in Atlas `ord` order). Orphans are dropped with a warning,
    /// duplicate log rows merged, bodyweight inferred from sets without weight. Weights are kept exactly (kg).
    public static func convert(_ document: AtlasDocument, source: String, now: Date = Date()) throws -> AtlasImport {
        var warnings: [String] = []
        func warn(_ count: Int, _ text: String) { if count > 0 { warnings.append("\(count) \(text)") } }

        // Workouts
        var seenWorkouts = Set<String>()
        var workouts: [Workout] = []
        for row in document.workouts where seenWorkouts.insert(row.id).inserted {
            let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            workouts.append(Workout(id: row.id, name: name.isEmpty ? "Untitled" : name, rest: row.rest ?? false, flex: row.flex ?? false))
        }
        warn(document.workouts.count - workouts.count, "duplicate workout rows skipped")

        // Exercises
        var exercises: [Exercise] = []
        var seenExercises = Set<String>()
        var orphanExercises = 0
        for row in document.exercises {
            guard let workoutId = row.workoutId, seenWorkouts.contains(workoutId) else { orphanExercises += 1; continue }
            guard seenExercises.insert(row.id).inserted else { continue }
            let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            exercises.append(Exercise(id: row.id, workoutId: workoutId, name: name.isEmpty ? "Untitled" : name,
                                      unilateral: row.unilateral ?? false, bodyweight: false, target: row.target ?? ""))
        }
        warn(orphanExercises, "exercises point at a missing workout and were skipped")

        // Logs (merge duplicate exercise + date + side rows, keep row order)
        var logs: [LogEntry] = []
        var logIndex: [String: Int] = [:]
        var badLogs = 0
        for row in document.logs {
            guard let exerciseId = row.exerciseId, !exerciseId.isEmpty, let date = row.date.flatMap(DayKey.init) else { badLogs += 1; continue }
            let rawSide = row.side?.trimmingCharacters(in: .whitespaces).uppercased() ?? ""
            let side: Side? = rawSide.isEmpty ? nil : Side(rawValue: rawSide)
            if !rawSide.isEmpty && side == nil { badLogs += 1; continue }
            let sets = row.sets.filter { $0.reps > 0 || ($0.weight ?? 0) > 0 }.map { SetEntry(weight: $0.weight, reps: $0.reps) }
            guard !sets.isEmpty else { continue }
            let key = "\(exerciseId)|\(date.rawValue)|\(side?.rawValue ?? "")"
            if let index = logIndex[key] {
                logs[index].sets.append(contentsOf: sets)
            } else {
                logIndex[key] = logs.count
                logs.append(LogEntry(id: row.id ?? GymID.make("gl"), exerciseId: exerciseId, date: date, side: side, sets: sets))
            }
        }
        warn(badLogs, "log rows with a missing exercise or an unreadable date or side were skipped")

        // Bodyweight: an exercise whose every logged set has no weight.
        let weightedIds = Set(logs.filter { $0.sets.contains { $0.weight != nil } }.map(\.exerciseId))
        let loggedIds = Set(logs.map(\.exerciseId))
        for index in exercises.indices where loggedIds.contains(exercises[index].id) && !weightedIds.contains(exercises[index].id) {
            exercises[index].bodyweight = true
        }

        // Completions (append-only history; unknown workouts kept as history)
        var completions: [Completion] = []
        var badCompletions = 0
        for row in document.completions {
            guard let workoutId = row.workoutId, !workoutId.isEmpty, let date = row.date.flatMap(DayKey.init) else { badCompletions += 1; continue }
            let start = ClockTime.minutes(row.startTime).map(ClockTime.string(minutes:)) ?? ""
            let end = ClockTime.minutes(row.endTime).map(ClockTime.string(minutes:)) ?? ""
            let ts = row.ts ?? date.date(hour: 12).timeIntervalSince1970 * 1000
            completions.append(Completion(workoutId: workoutId, date: date, ts: ts, start: start, end: end))
        }
        warn(badCompletions, "completions with a missing workout or an unreadable date were skipped")

        // Settings
        let settingsRow = document.settings ?? AtlasDocument.SettingsRow()
        var hours: [String: OpeningHours] = [:]
        for row in document.hours {
            guard let day = Weekday(rawValue: row.day.lowercased()) else { continue }
            hours[day.rawValue] = OpeningHours(open: row.open ?? "", close: row.close ?? "")
        }
        let unit: WeightUnit = settingsRow.unit?.lowercased().hasPrefix("lb") == true ? .lbs : .kg
        let settings = GymSettings(unit: unit, address: settingsRow.address ?? "", hours: hours,
                                   defaultDuration: max(1, settingsRow.defaultDuration ?? 75))

        // Plan
        var weekly: [String: String] = [:]
        for row in document.planWeekly {
            guard let day = Weekday(rawValue: row.day.lowercased()), let id = row.workoutId, seenWorkouts.contains(id) else { continue }
            weekly[day.rawValue] = id
        }
        // Cycle: Atlas keeps empty (NULL) slots and its pointer indexes the full list, so remember each surviving
        // slot's Atlas index and re-aim the pointer at the first survivor at or after Atlas's (wrapping).
        var cycle: [String] = []
        var atlasIndexes: [Int] = []
        for (index, row) in document.planCycle.enumerated() {
            guard let id = row.workoutId, seenWorkouts.contains(id) else { continue }
            cycle.append(id)
            atlasIndexes.append(index)
        }
        warn(document.planCycle.count - cycle.count, "cycle slots are empty or point at a missing workout and were dropped")
        let planType: PlanType = settingsRow.planType?.lowercased() == "weekly" ? .weekly : (settingsRow.planType == nil && cycle.isEmpty ? .weekly : .cycle)
        var plan = Plan(type: planType, weekly: weekly, cycle: cycle, position: 0)
        plan.position = alignedCyclePosition(atlasPosition: settingsRow.cyclePosition ?? 0, atlasCount: document.planCycle.count,
                                             survivingIndexes: atlasIndexes)

        // Overrides and extras
        var overrides: [PlanOverride] = []
        var droppedOverrides = 0
        for row in document.planOverrides {
            guard let date = DayKey(row.date) else { droppedOverrides += 1; continue }
            let id = row.workoutId?.trimmingCharacters(in: .whitespaces)
            if id == nil || id == PlanOverride.skipValue || id == "" {
                overrides.removeAll { $0.date == date }
                overrides.append(PlanOverride(date: date, workoutId: nil))
            } else if let id, seenWorkouts.contains(id) {
                overrides.removeAll { $0.date == date }
                overrides.append(PlanOverride(date: date, workoutId: id))
            } else {
                droppedOverrides += 1
            }
        }
        overrides.sort { $0.date < $1.date }
        warn(droppedOverrides, "overrides point at a missing workout or date and were dropped")

        var extras: [PlanExtra] = []
        var droppedExtras = 0
        for row in document.planExtras {
            guard let date = DayKey(row.date), seenExercises.contains(row.exerciseId) else { droppedExtras += 1; continue }
            if !extras.contains(where: { $0.date == date && $0.exerciseId == row.exerciseId }) {
                extras.append(PlanExtra(date: date, exerciseId: row.exerciseId))
            }
        }
        warn(droppedExtras, "extras point at a missing exercise or date and were dropped")

        let data = GymData(workouts: workouts, exercises: exercises, logs: logs, completions: completions, plan: plan,
                           overrides: overrides, extras: extras, settings: settings, activeSession: nil, lastRollover: nil,
                           importedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)), importSource: source) // whole seconds: stored as ISO 8601
        let sessionDates = completions.filter { id in !(data.workout(id.workoutId)?.isRest ?? false) }.map(\.date)
        let summary = ImportSummary(
            email: document.email,
            workoutNames: workouts.map(\.name),
            workouts: workouts.count,
            exercises: exercises.count,
            unilateralExercises: exercises.filter(\.unilateral).count,
            bodyweightExercises: exercises.filter(\.bodyweight).count,
            logRows: logs.count,
            sets: logs.reduce(0) { $0 + $1.sets.count },
            completions: completions.count,
            firstSession: sessionDates.min(),
            lastSession: sessionDates.max(),
            overrides: overrides.count,
            extras: extras.count,
            planType: plan.type,
            cycleLength: cycle.count,
            pointerWorkout: cycle.isEmpty ? nil : data.workout(cycle[plan.position])?.name,
            pointerIndex: plan.position,
            weeklyDays: weekly.count,
            unit: unit,
            warnings: warnings
        )
        return AtlasImport(data: data, summary: summary)
    }
}
