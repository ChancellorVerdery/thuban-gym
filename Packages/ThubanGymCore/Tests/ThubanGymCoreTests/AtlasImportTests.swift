import XCTest
@testable import ThubanGymCore

final class AtlasImportTests: XCTestCase {
    func fixture(_ name: String) throws -> Data { try Data(contentsOf: TestWorld.fixtureURL(name)) }

    // MARK: SQL

    func testSQLIsReadOnly() throws {
        let sql = try AtlasImporter.sql(email: "lifter@example.com")
        XCTAssertTrue(sql.contains("BEGIN TRANSACTION READ ONLY;"))
        XCTAssertTrue(sql.contains("ROLLBACK;"))
        XCTAssertTrue(sql.contains("\\set QUIET on"))
        let upper = sql.uppercased()
        for verb in ["INSERT", "UPDATE", "DELETE", "DROP", "ALTER", "TRUNCATE", "CREATE", "GRANT", "COPY", "COMMIT"] {
            XCTAssertFalse(upper.range(of: "\\b\(verb)\\b", options: .regularExpression) != nil, "SQL must not contain \(verb)")
        }
        for table in ["settings", "hours", "workouts", "exercises", "logs", "completions", "plan_weekly", "plan_cycle", "plan_overrides", "plan_extras"] {
            XCTAssertTrue(sql.contains("gym.\(table) t"), table)
        }
        XCTAssertTrue(sql.contains("lower('lifter@example.com')"))
    }

    func testRejectsUnsafeInput() {
        XCTAssertThrowsError(try AtlasImporter.sql(email: "x'); DROP TABLE gym.logs; --@a.b"))
        XCTAssertThrowsError(try AtlasImporter.sql(email: "not-an-email"))
        XCTAssertThrowsError(try AtlasImporter(host: "-oProxyCommand=evil").sshArguments())
        XCTAssertThrowsError(try AtlasImporter(host: "bee link").sshArguments())
        XCTAssertNoThrow(try AtlasImporter(host: "me@beelink.local").sshArguments())
    }

    // MARK: Fetch through a fixture runner

    func testFetchRunsSSHWithBatchModeAndDecodes() async throws {
        let runner = FixtureRunner(result: CommandResult(status: 0, stdout: try fixture("atlas-psql-output.txt"), stderr: Data()))
        let importer = AtlasImporter(host: "beelink", email: "lifter@example.com", runner: runner)
        let result = try await importer.dryRun(now: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(runner.executable, "/usr/bin/ssh")
        XCTAssertEqual(Array(runner.arguments.prefix(5)), ["-o", "BatchMode=yes", "-o", "ConnectTimeout=10", "beelink"])
        XCTAssertEqual(Array(runner.arguments.dropFirst(5)), ["docker", "exec", "-i", "stack-postgres-1", "psql", "-U", "atlas_user", "-d", "atlas", "-At"])
        XCTAssertEqual(runner.arguments.last, "-At")
        XCTAssertTrue(String(decoding: runner.stdin, as: UTF8.self).contains("READ ONLY"))
        XCTAssertEqual(result.summary.workouts, 5)
        XCTAssertEqual(result.data.importSource, "atlas:beelink")
    }

    func testFetchFailureCarriesStderr() async {
        let runner = FixtureRunner(result: CommandResult(status: 255, stdout: Data(), stderr: Data("ssh: Could not resolve hostname beelink".utf8)))
        do {
            _ = try await AtlasImporter(runner: runner).fetch()
            XCTFail("expected an error")
        } catch let error as ThubanError {
            guard case .importFailed(let message) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(message.contains("Could not resolve hostname"))
        } catch { XCTFail("\(error)") }
    }

    func testUnknownAccount() async {
        let json = #"{"format":"thuban.atlas-gym.v1","email":"nobody@example.com","user_found":false,"settings":null,"workouts":[]}"#
        let runner = FixtureRunner(result: CommandResult(status: 0, stdout: Data((json + "\n").utf8), stderr: Data()))
        do {
            _ = try await AtlasImporter(email: "nobody@example.com", runner: runner).fetch()
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no account"))
        }
    }

    func testGarbageOutput() {
        XCTAssertThrowsError(try AtlasDocument.decode(Data("psql: error: connection refused\n".utf8)))
        XCTAssertThrowsError(try AtlasDocument.decode(Data()))
    }

    // MARK: Conversion

    func testConvertRealisticFixture() throws {
        let document = try AtlasDocument.decode(try fixture("atlas-export.json"))
        let result = try AtlasImporter.convert(document, source: "file:atlas-export.json")
        let data = result.data, summary = result.summary

        XCTAssertEqual(data.workouts.map(\.id), ["gw-import1", "gw-import2", "gw-import3", "gw-import4", "gw-import5"])
        XCTAssertEqual(data.workout("gw-import1")?.rest, false) // null → false
        XCTAssertEqual(data.workout("gw-import4")?.isRest, true)
        XCTAssertEqual(data.workout("gw-import4")?.flex, true) // kept verbatim
        XCTAssertEqual(data.workout("gw-import4")?.kind, .rest)

        XCTAssertEqual(data.exercises.count, 7)
        XCTAssertNil(data.exercise("ge-orphan"))
        XCTAssertEqual(data.exercise("ge-import2")?.unilateral, true)
        XCTAssertEqual(data.exercise("ge-import5")?.unilateral, false)
        XCTAssertEqual(data.exercise("ge-import3")?.bodyweight, true)  // inferred: no weights logged
        XCTAssertEqual(data.exercise("ge-import1")?.bodyweight, false)
        XCTAssertEqual(data.exercises(in: "gw-import1").map(\.id), ["ge-import1", "ge-import2", "ge-import3"])

        let sep14 = DayKey("2026-09-14")!, sep18 = DayKey("2026-09-18")!
        XCTAssertEqual(data.sets(exerciseId: "ge-import2", date: sep14, side: .left).count, 2)
        XCTAssertEqual(data.sets(exerciseId: "ge-import2", date: sep14, side: .right).first?.weight, 29.483504) // exact kg
        XCTAssertEqual(data.sets(exerciseId: "ge-import3", date: sep14).map(\.weight), [nil, nil, nil])
        XCTAssertEqual(data.sets(exerciseId: "ge-import1", date: sep18).map(\.reps), [8, 8, 7]) // "" side + duplicate merged, "8" parsed
        XCTAssertEqual(summary.logRows, 6)
        XCTAssertEqual(summary.sets, 16)

        XCTAssertEqual(data.completions.count, 5)
        XCTAssertEqual(data.completions[1].ts, 1789516000000.5)
        XCTAssertEqual(data.completions[4].start, "07:30")
        XCTAssertEqual(data.completions[0].durationMinutes, 57)
        XCTAssertEqual(summary.firstSession, sep14)
        XCTAssertEqual(summary.lastSession, sep18)

        XCTAssertEqual(data.settings.unit, .lbs)
        XCTAssertEqual(data.settings.defaultDuration, 75)
        XCTAssertEqual(data.settings.address, "100 Example St")
        XCTAssertEqual(data.settings.hours(for: .sat), OpeningHours(open: "07:00", close: "19:00"))
        XCTAssertFalse(data.settings.hours(for: .sun).isSet)

        XCTAssertEqual(data.plan.type, .cycle)
        XCTAssertEqual(data.plan.cycle, ["gw-import1", "gw-import2", "gw-import3", "gw-import4", "gw-import5"])
        XCTAssertEqual(data.plan.position, 2)
        XCTAssertEqual(summary.pointerWorkout, "Shoulders, Traps, Calves, & Abs")
        XCTAssertEqual(data.plan.weekly, ["sun": "gw-import4"])

        XCTAssertEqual(data.overrides.map(\.date.rawValue), ["2026-09-25", "2026-09-29", "2026-10-01"])
        XCTAssertEqual(data.overrides.map(\.workoutId), [nil, "gw-import5", nil])
        XCTAssertEqual(data.extras.map(\.exerciseId), ["ge-import6"])

        XCTAssertNil(data.activeSession)
        XCTAssertNil(data.lastRollover)
        XCTAssertEqual(summary.workoutNames.count, 5)
        XCTAssertEqual(summary.unilateralExercises, 1)
        XCTAssertEqual(summary.bodyweightExercises, 1)
        XCTAssertEqual(summary.warnings.count, 5, "\(summary.warnings)")
        XCTAssertEqual(summary.email, "lifter@example.com")

        // The converted document plans and scores.
        let today = DayKey("2026-09-24")!
        XCTAssertEqual(PlanEngine.plannedWorkout(data, on: today, today: today)?.id, "gw-import3")
        XCTAssertNotNil(Scoring.strengthScore(data, on: today))
    }

    func testConvertedDataRoundTripsThroughStore() throws {
        let document = try AtlasDocument.decode(try fixture("atlas-export.json"))
        let data = try AtlasImporter.convert(document, source: "test", now: Date(timeIntervalSince1970: 1_790_000_000)).data
        let encoded = try JSONFile.encoder.encode(data)
        XCTAssertEqual(try JSONFile.decoder.decode(GymData.self, from: encoded), data)
    }

    // MARK: Live (read-only) dry run — opt in with THUBAN_GYM_LIVE_ATLAS=1

    func testLiveDryRunAgainstAtlas() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["THUBAN_GYM_LIVE_ATLAS"] == "1" else { throw XCTSkip("set THUBAN_GYM_LIVE_ATLAS=1 to read the real Atlas (read-only)") }
        let importer = AtlasImporter(host: env["THUBAN_GYM_ATLAS_HOST"] ?? Preferences.defaultAtlasHost,
                                     email: env["THUBAN_GYM_ATLAS_EMAIL"] ?? Preferences.defaultAtlasEmail)
        let result = try await importer.dryRun()
        let s = result.summary
        // Counts and workout names only — nothing personal is printed or stored.
        print("LIVE ATLAS DRY RUN: workouts=\(s.workouts) exercises=\(s.exercises) unilateral=\(s.unilateralExercises) logRows=\(s.logRows) sets=\(s.sets) completions=\(s.completions) overrides=\(s.overrides) extras=\(s.extras) plan=\(s.planType.rawValue) cycle=\(s.cycleLength) pointer=\(s.pointerIndex) unit=\(s.unit.rawValue) weeklyDays=\(s.weeklyDays) warnings=\(s.warnings)")
        print("LIVE ATLAS WORKOUTS: \(s.workoutNames.joined(separator: " | "))")
        XCTAssertGreaterThan(s.workouts, 0)
        XCTAssertGreaterThan(s.exercises, 0)
        let encoded = try JSONFile.encoder.encode(result.data)
        XCTAssertEqual(try JSONFile.decoder.decode(GymData.self, from: encoded), result.data)
    }
}
