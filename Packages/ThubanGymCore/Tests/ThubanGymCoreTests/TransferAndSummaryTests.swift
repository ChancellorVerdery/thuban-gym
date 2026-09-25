import XCTest
@testable import ThubanGymCore

final class TransferAndSummaryTests: XCTestCase {
    let today = TestWorld.today

    // MARK: GymTransfer

    func testRoundTripsTheStoreFormat() throws {
        var data = TestWorld.make()
        data.logSet(exerciseId: "row", date: today, weightKg: 63.50293180, reps: 8)
        data.complete(workoutId: "pull", date: today, start: "17:42", end: "18:40")
        let bytes = try GymTransfer.encode(data)
        let decoded = try GymTransfer.decode(bytes)
        XCTAssertEqual(decoded.format, "gym.json")
        XCTAssertEqual(decoded.data, data, "an export imports back unchanged (weights are never rounded)")
        let contents = GymTransfer.contents(decoded.data)
        XCTAssertEqual(contents.workouts, 5)
        XCTAssertEqual(contents.sets, 1)
        XCTAssertEqual(contents.sessions, 1)
        XCTAssertEqual(contents.lastDay, today)
    }

    func testRejectsJSONThatIsNotAnExport() {
        XCTAssertThrowsError(try GymTransfer.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try GymTransfer.decode(Data("[1,2]".utf8)))
        XCTAssertThrowsError(try GymTransfer.decode(Data("not json".utf8)))
        XCTAssertThrowsError(try GymTransfer.decode(Data(#"{"version": 99, "workouts": []}"#.utf8)), "newer format")
    }

    func testAcceptsAnAtlasExport() throws {
        let bytes = try Data(contentsOf: TestWorld.fixtureURL("atlas-export.json"))
        let decoded = try GymTransfer.decode(bytes)
        XCTAssertEqual(decoded.format, "atlas")
        XCTAssertFalse(decoded.data.workouts.isEmpty)
    }

    func testPreferencesDefaultTheRestSwitchesOnAndKeepThem() throws {
        let old = try JSONFile.decoder.decode(Preferences.self, from: Data(#"{"atlasHost": "beelink"}"#.utf8))
        XCTAssertTrue(old.restAutoStart && old.restAlert && old.keepScreenAwake, "older files get the defaults")
        var preferences = Preferences()
        preferences.restAlert = false
        let again = try JSONFile.decoder.decode(Preferences.self, from: JSONFile.encoder.encode(preferences))
        XCTAssertFalse(again.restAlert)
        XCTAssertTrue(again.restAutoStart)
    }

    // MARK: WorkoutSummary

    func testSummaryCountsVolumeBestsAndTheNextCycleDay() {
        var data = TestWorld.make(position: 1) // Pull is today's slot
        let last = today.adding(days: -4)
        for reps in [8, 8, 8, 7] { data.logSet(exerciseId: "row", date: last, weightKg: 60, reps: reps) }
        for reps in [6, 6, 6, 6] { data.logSet(exerciseId: "pullup", date: last, weightKg: nil, reps: reps) }
        data.complete(workoutId: "pull", date: last, start: "17:00", end: "18:00")
        data.plan.position = 1

        for _ in 0..<4 { data.logSet(exerciseId: "row", date: today, weightKg: 62.5, reps: 8) }
        for reps in [8, 8, 7, 7] { data.logSet(exerciseId: "pullup", date: today, weightKg: nil, reps: reps) }
        data.startSession(workoutId: "pull", date: today, at: today.date(hour: 17, minute: 42), today: today)
        let receipt = data.finishSession(at: today.date(hour: 18, minute: 40))!

        let summary = WorkoutSummary.make(data, completion: receipt.completion)
        XCTAssertEqual(summary.minutes, 58)
        XCTAssertEqual(summary.setsLogged, 8)
        XCTAssertEqual(summary.setsPlanned, 11)
        XCTAssertEqual(summary.volume, 4 * 62.5 * 8, accuracy: 1e-9)
        XCTAssertEqual(summary.previousVolume!, 60 * 31, accuracy: 1e-9)
        XCTAssertEqual(summary.bestLift?.exercise.id, "row")
        XCTAssertEqual(summary.nextWorkout?.id, "legs")
        XCTAssertEqual(summary.nextDate, today.adding(days: 1))

        guard summary.highlights.count >= 2 else { return XCTFail("expected highlights, got \(summary.highlights)") }
        if case .newBest(let exercise, _, _, let gain) = summary.highlights[0] {
            XCTAssertEqual(exercise.id, "row")
            XCTAssertEqual(gain!, 62.5 * (1 + 8.0 / 30) - 60 * (1 + 8.0 / 30), accuracy: 1e-9)
        } else { XCTFail("first highlight should be the new best") }
        if case .moreReps(let exercise, _, let total, let gain) = summary.highlights[1] {
            XCTAssertEqual(exercise.id, "pullup")
            XCTAssertEqual(total, 30)
            XCTAssertEqual(gain, 6)
        } else { XCTFail("second highlight should be the rep gain") }
        // Row hit 4 × 8 at its top weight → its target goes up, but it is already named as a new best.
        XCTAssertFalse(summary.highlights.dropFirst(2).contains { $0.exerciseId == "row" })
    }
}
