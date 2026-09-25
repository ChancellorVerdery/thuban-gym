import XCTest
@testable import ThubanGymCore

final class ScoringTests: XCTestCase {
    let today = TestWorld.today
    let lb = WeightUnit.lbs

    func testEpley() {
        XCTAssertEqual(Scoring.e1RM(weightKg: 100, reps: 10), 133.333, accuracy: 0.001)
        XCTAssertEqual(Scoring.e1RM(weightKg: 100, reps: 0), 100, accuracy: 0.001)
        XCTAssertEqual(Scoring.e1RM(weightKg: nil, reps: 8), 8)   // bodyweight scores by reps
        XCTAssertEqual(Scoring.e1RM(weightKg: 0, reps: 7), 7)
        // Design: 140 lb × 8 = 177.3 lb e1RM.
        XCTAssertEqual(lb.fromKilograms(Scoring.e1RM(weightKg: lb.toKilograms(140), reps: 8)), 177.333, accuracy: 0.001)
    }

    func testSessionScoreIsBestSet() {
        var data = TestWorld.make()
        for (w, r) in [(60.0, 8), (62.5, 6), (60.0, 9)] { data.logSet(exerciseId: "row", date: today, weightKg: w, reps: r) }
        let score = Scoring.sessionScore(data.logs(exerciseId: "row", date: today), unilateral: false)
        XCTAssertEqual(score!, 60 * (1 + 9.0 / 30), accuracy: 1e-9)
    }

    func testUnilateralUsesWeakerSide() {
        var data = TestWorld.make()
        data.logSet(exerciseId: "dbrow", date: today, side: .left, weightKg: 25, reps: 10)
        data.logSet(exerciseId: "dbrow", date: today, side: .right, weightKg: 30, reps: 10)
        let score = Scoring.sessionScore(data.logs(exerciseId: "dbrow", date: today), unilateral: true)!
        XCTAssertEqual(score, 25 * (1 + 10.0 / 30), accuracy: 1e-9)
        let session = Scoring.session(data, exerciseId: "dbrow", on: today)!
        XCTAssertEqual(session.bestSet?.weight, 25)
        XCTAssertEqual(session.left.count, 1)
        XCTAssertEqual(session.right.count, 1)
    }

    func testIndexAndStrengthScore() {
        var data = TestWorld.make()
        let d0 = today.adding(days: -14), d1 = today.adding(days: -7)
        data.logSet(exerciseId: "bench", date: d0, weightKg: 100, reps: 5)
        data.logSet(exerciseId: "bench", date: d1, weightKg: 110, reps: 5)   // index 110
        data.logSet(exerciseId: "pullup", date: d0, weightKg: nil, reps: 6)
        data.logSet(exerciseId: "pullup", date: d1, weightKg: nil, reps: 9)  // index 150
        let benchSeries = Scoring.scoreSeries(data, exerciseId: "bench")
        XCTAssertEqual(Scoring.index(benchSeries, at: d1)!, 110, accuracy: 1e-9)
        XCTAssertNil(Scoring.index(benchSeries, at: d0.adding(days: -1)))
        XCTAssertEqual(Scoring.strengthScore(data, on: d0)!, 100, accuracy: 1e-9)
        XCTAssertEqual(Scoring.strengthScore(data, on: today)!, 130, accuracy: 1e-9) // equal weight
        XCTAssertNil(Scoring.strengthScore(TestWorld.make(), on: today))

        let series = Scoring.strengthSeries(data)
        XCTAssertEqual(series.map(\.date), [d0, d1])
        XCTAssertEqual(series.map(\.score), [100, 130])

        // An exercise first logged later joins at 100 and pulls the mean toward it.
        data.logSet(exerciseId: "squat", date: today, weightKg: 140, reps: 5)
        XCTAssertEqual(Scoring.strengthScore(data, on: today)!, (110 + 150 + 100) / 3, accuracy: 1e-9)

        let sampled = Scoring.sampledStrengthSeries(data, from: d0, through: today, stepDays: 7)
        XCTAssertEqual(sampled.map(\.date), [d0, d1, today])
    }

    func testHistoryFlagsBestsAndChanges() throws {
        var data = TestWorld.make()
        let days = [-21, -14, -7, 0].map { today.adding(days: $0) }
        let sessions: [[(Double, Int)]] = [[(60, 8), (60, 8)], [(62.5, 8)], [(60, 8)], [(65, 8), (65, 7)]]
        for (day, sets) in zip(days, sessions) {
            for (w, r) in sets { data.logSet(exerciseId: "row", date: day, weightKg: w, reps: r) }
        }
        let history = try XCTUnwrap(Scoring.history(data, exerciseId: "row"))
        XCTAssertEqual(history.sessions.map(\.isBest), [false, true, false, true])
        XCTAssertEqual(history.sessions[1].topWeightChange, 2.5)
        XCTAssertEqual(history.sessions[3].index, 100 * 65 / 60, accuracy: 1e-9)
        XCTAssertEqual(history.sessions[0].volume, 960)
        XCTAssertEqual(history.best?.date, days[3])
        XCTAssertFalse(history.isBodyweight)
    }

    func testBodyweightHistory() throws {
        var data = TestWorld.make()
        data.logSet(exerciseId: "pullup", date: today, weightKg: nil, reps: 8)
        let history = try XCTUnwrap(Scoring.history(data, exerciseId: "pullup"))
        XCTAssertTrue(history.isBodyweight)
        XCTAssertEqual(GymFormat.score(history.latest!.score, bodyweight: true, unit: lb), "8 reps")
        XCTAssertEqual(GymFormat.set(SetEntry(weight: nil, reps: 8), unit: lb), "BW × 8")
    }

    func testNextTarget() throws {
        var data = TestWorld.make()
        data.settings.unit = .lbs
        for _ in 0..<4 { data.logSet(exerciseId: "row", date: today, weightKg: lb.toKilograms(140), reps: 8) }
        let up = try XCTUnwrap(Scoring.nextTarget(data, exerciseId: "row"))
        XCTAssertTrue(up.increase)
        XCTAssertEqual(lb.fromKilograms(up.weightKg!), 145, accuracy: 1e-9)
        data.removeSet(exerciseId: "row", date: today, index: 3)
        data.logSet(exerciseId: "row", date: today, weightKg: lb.toKilograms(140), reps: 7)
        let stay = try XCTUnwrap(Scoring.nextTarget(data, exerciseId: "row"))
        XCTAssertFalse(stay.increase)
        XCTAssertEqual(lb.fromKilograms(stay.weightKg!), 140, accuracy: 1e-9)
    }

    // MARK: Units

    func testUnitConversionNeverRounds() {
        let kg = lb.toKilograms(140)
        XCTAssertEqual(kg, 63.5029318, accuracy: 1e-7)
        XCTAssertEqual(lb.fromKilograms(kg), 140, accuracy: 1e-9)
        XCTAssertEqual(GymFormat.weight(kg, unit: .lbs), "140")
        XCTAssertEqual(GymFormat.weight(kg, unit: .kg), "63.5")
        XCTAssertEqual(GymFormat.weightWithUnit(kg, unit: .lbs), "140 lb")
        var data = TestWorld.make()
        data.logSet(exerciseId: "row", date: today, weightKg: kg, reps: 8)
        data.settings.unit = .kg
        data.settings.unit = .lbs
        XCTAssertEqual(data.sets(exerciseId: "row", date: today).first?.weight, kg) // stored value untouched
    }

    func testTargetSpec() {
        XCTAssertEqual(TargetSpec("3×8"), TargetSpec(sets: 3, repsLow: 8, repsHigh: 8))
        XCTAssertEqual(TargetSpec("4 × 6–8"), TargetSpec(sets: 4, repsLow: 6, repsHigh: 8))
        XCTAssertEqual(TargetSpec("3x10")?.display, "3 × 10")
        XCTAssertNil(TargetSpec("AMRAP"))
    }

    func testFormatting() {
        XCTAssertEqual(GymFormat.grouped(2240), "2,240")
        XCTAssertEqual(GymFormat.delta(6.3), "+6.3")
        XCTAssertEqual(GymFormat.delta(-1.2), "−1.2")
        XCTAssertEqual(GymFormat.clock("17:42"), "5:42 PM")
        XCTAssertEqual(GymFormat.clockRange(start: "17:40", end: "18:44"), "5:40 – 6:44 PM")
        XCTAssertEqual(GymFormat.elapsed(1872), "31:12")
        XCTAssertEqual(GymFormat.shortDay(today), "Thu Sep 24")
        XCTAssertEqual(GymFormat.minutes(65), "1 h 5 min")
    }

    func testStats() {
        var data = TestWorld.make(position: 0)
        data.complete(workoutId: "push", date: today.adding(days: -3), start: "17:00", end: "18:00")
        data.complete(workoutId: "rest", date: today.adding(days: -2), auto: true)
        data.logSet(exerciseId: "bench", date: today.adding(days: -3), weightKg: 100, reps: 5)
        XCTAssertEqual(Stats.sessionCount(data), 1)
        XCTAssertEqual(Stats.averageDuration(data), 60)
        let recent = Stats.recentSessions(data)
        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.setCount, 1)
        XCTAssertEqual(recent.first?.topExercise?.id, "bench")
        XCTAssertEqual(Stats.exerciseProgress(data).map(\.exercise.id), ["bench"])
    }
}
