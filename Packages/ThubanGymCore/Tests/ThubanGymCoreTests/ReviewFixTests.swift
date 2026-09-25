import XCTest
@testable import ThubanGymCore

/// Regressions from the review pass: sessions after a completion, nullable Atlas columns, cycle pointer alignment.
final class ReviewFixTests: XCTestCase {
    let today = TestWorld.today
    let noon = TestWorld.today.date(hour: 12)

    // MARK: A running session wins over an earlier completion today

    func testRestDoneThenTrainAnyway() {
        var data = TestWorld.make(position: 3) // pointer on Rest
        data.complete(workoutId: "rest", date: today)
        XCTAssertEqual(PlanEngine.day(data, on: today, today: today).status, .restDone)
        data.startSession(workoutId: "upper", date: today, at: noon, today: today)
        let day = PlanEngine.day(data, on: today, today: today)
        XCTAssertEqual(day.status, .inProgress)
        XCTAssertEqual(day.workout?.id, "upper")
        XCTAssertEqual(day.source, .session)
        XCTAssertEqual(PlanEngine.sessionExercises(data, workoutId: day.workout?.id, on: today).map(\.id), ["fly"])
        // Tomorrow still continues from the pointer (already past Rest): Push.
        XCTAssertEqual(PlanEngine.plannedWorkout(data, on: today.adding(days: 1), today: today)?.id, "push")
        _ = data.finishSession(at: noon.addingTimeInterval(3600))
        XCTAssertEqual(PlanEngine.day(data, on: today, today: today).status, .done)
        XCTAssertEqual(PlanEngine.day(data, on: today, today: today).workout?.id, "upper")
    }

    func testSecondSessionSameDay() {
        var data = TestWorld.make(position: 0) // Push
        data.startSession(workoutId: "push", date: today, at: noon, today: today)
        _ = data.finishSession(at: noon.addingTimeInterval(3600))
        XCTAssertEqual(data.plan.position, 1)
        XCTAssertEqual(PlanEngine.day(data, on: today, today: today).workout?.id, "push")
        data.startSession(workoutId: "upper", date: today, at: noon.addingTimeInterval(7200), today: today)
        let day = PlanEngine.day(data, on: today, today: today)
        XCTAssertEqual(day.status, .inProgress)
        XCTAssertEqual(day.workout?.id, "upper")
        XCTAssertNil(day.cycleIndex)
        // Pull (the next slot) is still tomorrow: the second session consumed nothing.
        XCTAssertEqual(PlanEngine.plannedWorkout(data, on: today.adding(days: 1), today: today)?.id, "pull")
    }

    func testSessionFromYesterdayProjectsAsItsOwnDay() {
        // The app shows a session that ran past midnight on its own date (today = session date).
        var data = TestWorld.make(position: 1)
        let yesterday = today.adding(days: -1)
        data.startSession(workoutId: "pull", date: yesterday, at: yesterday.date(hour: 22), today: yesterday)
        data.rollover(to: today)
        let day = PlanEngine.day(data, on: yesterday, today: yesterday)
        XCTAssertEqual(day.status, .inProgress)
        XCTAssertEqual(day.workout?.id, "pull")
        _ = data.finishSession(at: today.date(hour: 0, minute: 30))
        XCTAssertEqual(data.completions.last?.date, yesterday)
        XCTAssertEqual(PlanEngine.plannedWorkout(data, on: today, today: today)?.id, "legs")
    }

    // MARK: Atlas nullable columns

    func testNullLogAndCompletionColumnsAreSkippedWithWarning() throws {
        let json = #"""
        {"format":"thuban.atlas-gym.v1","email":"a@b.co","user_found":true,
         "workouts":[{"id":"w1","name":"Push"}],
         "exercises":[{"id":"e1","workout_id":"w1","name":"Bench","target":"3×5"}],
         "logs":[{"id":"l1","exercise_id":"e1","date":null,"side":null,"sets":[{"weight":100,"reps":5}]},
                 {"id":"l2","exercise_id":null,"date":"2026-09-20","sets":[{"weight":100,"reps":5}]},
                 {"id":"l3","exercise_id":"e1","date":"2026-09-21","sets":[{"weight":100,"reps":5}]}],
         "completions":[{"workout_id":null,"date":"2026-09-21","ts":1790000000000},
                        {"workout_id":"w1","date":null},
                        {"workout_id":"w1","date":"2026-09-21","start_time":"17:00","end_time":"18:00"}]}
        """#
        let document = try AtlasDocument.decode(Data(json.utf8))
        XCTAssertNil(document.logs[0].date)
        XCTAssertNil(document.completions[0].workoutId)
        let result = try AtlasImporter.convert(document, source: "test")
        XCTAssertEqual(result.data.logs.map(\.id), ["l3"])
        XCTAssertEqual(result.data.completions.count, 1)
        XCTAssertTrue(result.summary.warnings.contains { $0.hasPrefix("2 log rows") }, "\(result.summary.warnings)")
        XCTAssertTrue(result.summary.warnings.contains { $0.hasPrefix("2 completions") }, "\(result.summary.warnings)")
    }

    // MARK: Atlas cycle pointer with dropped slots

    func testCyclePointerSurvivesDroppedSlots() throws {
        func convert(cycle: String, position: Int) throws -> (ids: [String], position: Int, warnings: [String]) {
            let json = """
            {"format":"thuban.atlas-gym.v1","user_found":true,
             "settings":{"plan_type":"cycle","cycle_position":\(position)},
             "workouts":[{"id":"a","name":"A"},{"id":"b","name":"B"},{"id":"c","name":"C"}],
             "plan_cycle":\(cycle)}
            """
            let result = try AtlasImporter.convert(try AtlasDocument.decode(Data(json.utf8)), source: "test")
            return (result.data.plan.cycle, result.data.plan.position, result.summary.warnings)
        }
        let slots = #"[{"position":0,"workout_id":null},{"position":1,"workout_id":"a"},{"position":2,"workout_id":"b"},{"position":3,"workout_id":"c"}]"#
        let onB = try convert(cycle: slots, position: 2)
        XCTAssertEqual(onB.ids, ["a", "b", "c"])
        XCTAssertEqual(onB.ids[onB.position], "b")
        XCTAssertTrue(onB.warnings.contains { $0.hasPrefix("1 cycle slots") }, "\(onB.warnings)")
        // Pointer on the empty slot → the next surviving slot.
        XCTAssertEqual(try convert(cycle: slots, position: 0).position, 0)
        // Dangling id at the end with the pointer on it → wraps to the first slot.
        let dangling = #"[{"workout_id":"a"},{"workout_id":"b"},{"workout_id":"gone"}]"#
        let wrapped = try convert(cycle: dangling, position: 2)
        XCTAssertEqual(wrapped.ids, ["a", "b"])
        XCTAssertEqual(wrapped.position, 0)
        XCTAssertEqual(try convert(cycle: dangling, position: 1).position, 1)
    }
}
