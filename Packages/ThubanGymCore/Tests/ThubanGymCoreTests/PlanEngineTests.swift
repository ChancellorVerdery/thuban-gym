import XCTest
@testable import ThubanGymCore

final class PlanEngineTests: XCTestCase {
    let today = TestWorld.today
    func day(_ n: Int) -> DayKey { TestWorld.day(n) }
    func planned(_ data: GymData, _ n: Int) -> String? { PlanEngine.plannedWorkout(data, on: day(n), today: today)?.id }

    // MARK: Weekly

    func testWeeklyUsesWeekday() {
        let data = TestWorld.make(type: .weekly)
        XCTAssertEqual(today.weekday, .thu)
        XCTAssertEqual(planned(data, 0), "rest")         // Thu
        XCTAssertEqual(planned(data, 1), "upper")        // Fri
        XCTAssertNil(planned(data, 2))                   // Sat: nothing planned
        XCTAssertEqual(PlanEngine.day(data, on: day(2), today: today).status, .empty)
        XCTAssertEqual(planned(data, 4), "push")         // Mon
        XCTAssertEqual(PlanEngine.day(data, on: day(0), today: today).status, .rest)
    }

    func testWeeklyOverrideWins() {
        var data = TestWorld.make(type: .weekly)
        data.setOverride(date: day(4), workoutId: "legs")
        data.setOverride(date: day(5), workoutId: nil, note: "Travel")
        XCTAssertEqual(planned(data, 4), "legs")
        XCTAssertEqual(PlanEngine.day(data, on: day(4), today: today).status, .swapped)
        XCTAssertEqual(PlanEngine.day(data, on: day(4), today: today).plannedWorkout?.id, "push")
        XCTAssertNil(planned(data, 5))
        let skipped = PlanEngine.day(data, on: day(5), today: today)
        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertEqual(skipped.override?.note, "Travel")
        XCTAssertEqual(planned(data, 11), "push") // next Monday unaffected
    }

    // MARK: Cycle projection

    func testCycleProjectsFromPointer() {
        let data = TestWorld.make(position: 1)
        XCTAssertEqual((0..<6).map { planned(data, $0) }, ["pull", "legs", "rest", "push", "pull", "legs"])
        XCTAssertEqual(PlanEngine.cyclePosition(data, on: today, today: today)?.index, 1)
        XCTAssertEqual(PlanEngine.cyclePosition(data, on: today, today: today)?.count, 4)
    }

    func testSkipDoesNotConsumeSlotOrMovePointer() {
        var data = TestWorld.make(position: 1)
        data.setOverride(date: day(1), workoutId: nil)
        XCTAssertEqual(data.plan.position, 1)
        XCTAssertNil(planned(data, 1))
        let skipped = PlanEngine.day(data, on: day(1), today: today)
        XCTAssertEqual(skipped.status, .skipped)
        XCTAssertEqual(skipped.plannedWorkout?.id, "legs")
        // Legs moves to the day after.
        XCTAssertEqual(planned(data, 2), "legs")
        XCTAssertEqual(planned(data, 3), "rest")
        XCTAssertEqual(PlanEngine.nextDate(of: "legs", in: data, after: today, today: today), day(2))
    }

    func testSwapDoesNotConsumeSlotOrMovePointer() {
        var data = TestWorld.make(position: 1)
        data.setOverride(date: day(0), workoutId: "upper")
        XCTAssertEqual(planned(data, 0), "upper")
        XCTAssertEqual(PlanEngine.day(data, on: day(0), today: today).status, .swapped)
        XCTAssertEqual(PlanEngine.day(data, on: day(0), today: today).plannedWorkout?.id, "pull")
        XCTAssertEqual(planned(data, 1), "pull")
        XCTAssertEqual(data.plan.position, 1)
    }

    func testFourteenDayStripIncludesPastDays() {
        var data = TestWorld.make(position: 0)
        data.complete(workoutId: "legs", date: day(-3), start: "17:00", end: "18:00")
        let monday = day(-3)
        XCTAssertEqual(monday.weekday, .mon)
        let strip = PlanEngine.days(data, from: monday, count: 14, today: today)
        XCTAssertEqual(strip.count, 14)
        XCTAssertEqual(strip.map(\.date), (0..<14).map { monday.adding(days: $0) })
        XCTAssertEqual(strip[0].status, .done)
        XCTAssertEqual(strip[0].workout?.id, "legs")
        XCTAssertEqual(strip[1].status, .missed)
        XCTAssertTrue(strip[3].isToday)
    }

    // MARK: Completion and the pointer

    func testCompletingPlannedWorkoutAdvancesPointer() {
        var data = TestWorld.make(position: 1)
        data.complete(workoutId: "pull", date: today, start: "17:42", end: "18:40")
        XCTAssertEqual(data.plan.position, 2)
        let todayEntry = PlanEngine.day(data, on: today, today: today)
        XCTAssertEqual(todayEntry.status, .done)
        XCTAssertEqual(todayEntry.workout?.id, "pull")
        XCTAssertEqual(planned(data, 1), "legs") // tomorrow starts at the new pointer
        XCTAssertEqual(planned(data, 2), "rest")
    }

    func testOutOfCycleWorkoutLeavesPointer() {
        var data = TestWorld.make(position: 1)
        data.complete(workoutId: "upper", date: today)
        XCTAssertEqual(data.plan.position, 1)
        XCTAssertEqual(planned(data, 1), "pull")
    }

    func testDoingAnotherCycleWorkoutJumpsPointerPastIt() {
        // "Did Legs on a Pull day? The pointer jumps to Rest, after the workout you actually did."
        var data = TestWorld.make(position: 1)
        data.complete(workoutId: "legs", date: today)
        XCTAssertEqual(data.plan.position, 3)
        XCTAssertEqual(planned(data, 1), "rest")
    }

    func testPointerWrapsAround() {
        var data = TestWorld.make(position: 3)
        data.complete(workoutId: "rest", date: today)
        XCTAssertEqual(data.plan.position, 0)
        data.complete(workoutId: "rest", date: day(1)) // nearest Rest at/after 0 is slot 3
        XCTAssertEqual(data.plan.position, 0)
    }

    func testWeeklyCompletionDoesNotTouchCyclePosition() {
        var data = TestWorld.make(type: .weekly, position: 2)
        data.complete(workoutId: "legs", date: today)
        XCTAssertEqual(data.plan.position, 2)
    }

    func testStartSessionOnADifferentWorkoutRecordsSwap() {
        var data = TestWorld.make(position: 1)
        data.startSession(workoutId: "legs", date: today, at: Date(), today: today)
        XCTAssertEqual(data.override(on: today)?.workoutId, "legs")
        XCTAssertEqual(PlanEngine.day(data, on: today, today: today).status, .inProgress)
        XCTAssertEqual(data.plan.position, 1)
        // The planned session needs no override.
        var planned = TestWorld.make(position: 1)
        planned.startSession(workoutId: "pull", date: today, at: Date(), today: today)
        XCTAssertNil(planned.override(on: today))
        XCTAssertEqual(PlanEngine.day(planned, on: day(1), today: today).workout?.id, "legs")
    }

    func testFinishAndUndo() throws {
        var data = TestWorld.make(position: 1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = today.date(hour: 17, minute: 42, calendar: calendar)
        data.startSession(workoutId: "pull", date: today, at: start, today: today)
        let receipt = try XCTUnwrap(data.finishSession(at: start.addingTimeInterval(58 * 60), calendar: calendar))
        XCTAssertNil(data.activeSession)
        XCTAssertEqual(receipt.completion.start, "17:42")
        XCTAssertEqual(receipt.completion.end, "18:40")
        XCTAssertEqual(receipt.completion.durationMinutes, 58)
        XCTAssertEqual(data.plan.position, 2)
        data.undoFinish(receipt)
        XCTAssertEqual(data.plan.position, 1)
        XCTAssertTrue(data.completions.isEmpty)
        XCTAssertEqual(data.activeSession?.workoutId, "pull")
    }

    // MARK: Rest slots and rollover

    func testRestSlotAutoCompletesWhenItsDayPasses() {
        var data = TestWorld.make(position: 3) // Rest is today's slot
        data.lastRollover = today
        data.rollover(to: day(1))
        XCTAssertEqual(data.completions.count, 1)
        XCTAssertEqual(data.completions.first?.workoutId, "rest")
        XCTAssertEqual(data.completions.first?.date, today)
        XCTAssertTrue(data.completions.first?.auto ?? false)
        XCTAssertEqual(data.plan.position, 0)
        XCTAssertEqual(data.lastRollover, day(1))
        // Running it again the same day changes nothing.
        data.rollover(to: day(1))
        XCTAssertEqual(data.completions.count, 1)
    }

    func testMissedTrainingDayDoesNotAdvance() {
        var data = TestWorld.make(position: 1)
        data.lastRollover = day(-2)
        data.rollover(to: today)
        XCTAssertTrue(data.completions.isEmpty)
        XCTAssertEqual(data.plan.position, 1)
    }

    func testRolloverCatchesUpRestAfterTrainingDoneThatDay() {
        // Legs done two days ago (pointer → Rest), app not opened yesterday: yesterday's Rest completes itself.
        var data = TestWorld.make(position: 2)
        data.lastRollover = day(-2)
        data.complete(workoutId: "legs", date: day(-2))
        data.rollover(to: today)
        XCTAssertEqual(data.completions.map(\.workoutId), ["legs", "rest"])
        XCTAssertEqual(data.completions.last?.date, day(-1))
        XCTAssertEqual(data.plan.position, 0)
    }

    func testSkippedRestDayDoesNotAutoComplete() {
        var data = TestWorld.make(position: 3)
        data.lastRollover = today
        data.setOverride(date: today, workoutId: nil)
        data.rollover(to: day(1))
        XCTAssertTrue(data.completions.isEmpty)
        XCTAssertEqual(data.plan.position, 3)
    }

    func testFirstRolloverDoesNotBackfill() {
        var data = TestWorld.make(position: 3)
        data.lastRollover = nil
        data.rollover(to: today)
        XCTAssertTrue(data.completions.isEmpty)
        XCTAssertEqual(data.lastRollover, today)
    }

    func testOverridesAndExtrasExpireAfter90Days() {
        var data = TestWorld.make(position: 0)
        data.setOverride(date: day(-91), workoutId: nil)
        data.setOverride(date: day(-90), workoutId: "upper")
        data.setOverride(date: day(3), workoutId: nil)
        data.addExtra(exerciseId: "fly", date: day(-120))
        data.addExtra(exerciseId: "fly", date: today)
        data.rollover(to: today)
        XCTAssertEqual(data.overrides.map(\.date), [day(-90), day(3)])
        XCTAssertEqual(data.extras.map(\.date), [today])
        XCTAssertEqual(data.plan.position, 0)
    }

    // MARK: Extras and sessions

    func testExtrasJoinTheSession() {
        var data = TestWorld.make(position: 1)
        data.addExtra(exerciseId: "fly", date: today)
        data.addExtra(exerciseId: "fly", date: today) // no duplicates
        data.addExtra(exerciseId: "row", date: today) // already in Pull: not listed twice
        let session = PlanEngine.sessionExercises(data, workoutId: "pull", on: today)
        XCTAssertEqual(session.map(\.exercise.id), ["row", "pullup", "dbrow", "fly"])
        XCTAssertEqual(session.last?.isExtra, true)
        XCTAssertEqual(session.last?.sourceWorkout?.id, "upper")
        XCTAssertEqual(PlanEngine.plannedSetCount(session), 4 + 4 + 3 + 3)
        XCTAssertEqual(data.plan.position, 1)
        data.removeExtra(exerciseId: "fly", date: today)
        XCTAssertEqual(PlanEngine.sessionExercises(data, workoutId: "pull", on: today).count, 3)
    }

    func testWorkoutDurationAveragesTimedCompletions() {
        var data = TestWorld.make()
        data.settings.defaultDuration = 70
        XCTAssertEqual(PlanEngine.workoutDuration(data, workoutId: "pull"), 70)
        data.complete(workoutId: "pull", date: day(-8), start: "17:00", end: "18:00")
        data.complete(workoutId: "pull", date: day(-4), start: "23:30", end: "00:20") // crosses midnight: 50
        data.complete(workoutId: "pull", date: day(-2)) // untimed: ignored
        XCTAssertEqual(PlanEngine.workoutDuration(data, workoutId: "pull"), 55)
    }

    // MARK: Editing the plan

    func testSetCycleKeepsPointerOnSameWorkout() {
        var data = TestWorld.make(position: 1) // Pull
        data.setCycle(["legs", "push", "pull", "rest"])
        XCTAssertEqual(data.plan.position, 2)
        XCTAssertEqual(planned(data, 0), "pull")
    }

    func testDeleteWorkoutCleansPlan() {
        var data = TestWorld.make(position: 2) // Legs
        data.setOverride(date: day(2), workoutId: "push")
        data.deleteWorkout("push")
        XCTAssertEqual(data.plan.cycle, ["pull", "legs", "rest"])
        XCTAssertEqual(data.plan.position, 1)
        XCTAssertEqual(planned(data, 0), "legs")
        XCTAssertNil(data.plan.weekly["mon"])
        XCTAssertNil(data.override(on: day(2)))
        XCTAssertNil(data.exercise("bench"))
    }

    func testUsages() {
        var data = TestWorld.make()
        data.setOverride(date: day(5), workoutId: "pull")
        let usages = PlanEngine.usages(of: "pull", in: data, today: today)
        XCTAssertEqual(usages, [.cycle(index: 1), .weekly(.tue), .override(day(5))])
    }
}
