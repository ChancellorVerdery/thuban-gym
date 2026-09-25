import XCTest
@testable import ThubanGymCore

final class SessionLogicTests: XCTestCase {
    let today = TestWorld.today

    private func exercise(_ data: GymData, _ id: String) -> Exercise { data.exercise(id)! }

    // MARK: Slots

    func testSlotsMarkDoneCurrentAndUpcomingWithLastTime() {
        var data = TestWorld.make()
        let last = today.adding(days: -4)
        for reps in [8, 8, 8, 7] { data.logSet(exerciseId: "row", date: last, weightKg: 61.2, reps: reps) }
        data.logSet(exerciseId: "row", date: today, weightKg: 63.5, reps: 8)
        data.logSet(exerciseId: "row", date: today, weightKg: 63.5, reps: 8)

        let slots = SessionLogic.slots(data, exercise: exercise(data, "row"), on: today)
        XCTAssertEqual(slots.map(\.state), [.done, .done, .current, .upcoming])
        XCTAssertEqual(slots[0].logged?.reps, 8)
        XCTAssertEqual(slots[3].previous?.reps, 7, "row 4 shows the fourth set of last time")
    }

    func testSlotsAlwaysOfferOneMoreSetPastTheTarget() {
        var data = TestWorld.make()
        for _ in 0..<4 { data.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) }
        let slots = SessionLogic.slots(data, exercise: exercise(data, "row"), on: today)
        XCTAssertEqual(slots.count, 5)
        XCTAssertEqual(slots.last?.state, .current)
    }

    func testUnilateralPairsAndNextSide() {
        var data = TestWorld.make()
        let row = exercise(data, "dbrow")
        XCTAssertEqual(SessionLogic.nextSide(data, exercise: row, on: today), .left)
        data.logSet(exerciseId: "dbrow", date: today, side: .left, weightKg: 25, reps: 10)
        XCTAssertEqual(SessionLogic.nextSide(data, exercise: row, on: today), .right)
        var slots = SessionLogic.slots(data, exercise: row, on: today)
        XCTAssertEqual(slots.map(\.state), [.current, .upcoming, .upcoming])
        XCTAssertEqual(slots[0].logged?.weight, 25)
        XCTAssertNil(slots[0].loggedRight)
        XCTAssertEqual(SessionLogic.loggedSetCount(data, exercise: row, on: today), 1)

        data.logSet(exerciseId: "dbrow", date: today, side: .right, weightKg: 25, reps: 9)
        XCTAssertEqual(SessionLogic.nextSide(data, exercise: row, on: today), .left)
        slots = SessionLogic.slots(data, exercise: row, on: today)
        XCTAssertEqual(slots.map(\.state), [.done, .current, .upcoming])
        XCTAssertEqual(slots[0].loggedRight?.reps, 9)
    }

    // MARK: Suggestions

    func testSuggestionRepeatsTodaysLastSetThenTargetThenHistory() {
        var data = TestWorld.make()
        let row = exercise(data, "row")
        // No history: target reps, no weight yet.
        XCTAssertEqual(SessionLogic.suggestion(data, exercise: row, on: today, side: nil), SetDraft(weightKg: 0, reps: 8))
        // History that hit every target set → the progression target (one plate step up).
        let last = today.adding(days: -4)
        for _ in 0..<4 { data.logSet(exerciseId: "row", date: last, weightKg: 60, reps: 8) }
        let suggestion = SessionLogic.suggestion(data, exercise: row, on: today, side: nil)
        XCTAssertEqual(suggestion.weightKg!, 62.5, accuracy: 1e-9)
        XCTAssertEqual(suggestion.reps, 8)
        // Once a set is logged today, repeat it.
        data.logSet(exerciseId: "row", date: today, weightKg: 61, reps: 7)
        XCTAssertEqual(SessionLogic.suggestion(data, exercise: row, on: today, side: nil), SetDraft(weightKg: 61, reps: 7))
    }

    func testSuggestionForBodyweightAndRightSide() {
        var data = TestWorld.make()
        XCTAssertNil(SessionLogic.suggestion(data, exercise: exercise(data, "pullup"), on: today, side: nil).weightKg)
        data.logSet(exerciseId: "dbrow", date: today, side: .left, weightKg: 22.5, reps: 10)
        XCTAssertEqual(SessionLogic.suggestion(data, exercise: exercise(data, "dbrow"), on: today, side: .right),
                       SetDraft(weightKg: 22.5, reps: 10), "the right side starts from the left side's set")
    }

    func testDraftStoresZeroWeightAsBodyweight() {
        XCTAssertNil(SetDraft(weightKg: 0, reps: 8).entry.weight)
        XCTAssertEqual(SetDraft(weightKg: 60, reps: 8).e1RM, 76, accuracy: 1e-9)
    }

    // MARK: Progress

    func testProgressCountsTargetSetsAndPairs() {
        var data = TestWorld.make()
        let items = PlanEngine.sessionExercises(data, workoutId: "pull", on: today)
        XCTAssertEqual(SessionLogic.progress(data, items: items, on: today).planned, 11) // 4 + 4 + 3
        for _ in 0..<5 { data.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) } // one past target
        data.logSet(exerciseId: "dbrow", date: today, side: .left, weightKg: 25, reps: 10)
        let progress = SessionLogic.progress(data, items: items, on: today)
        XCTAssertEqual(progress.logged, 5, "4 row sets (the fifth is past the target) + one half pair")
        XCTAssertEqual(progress.segments.filter(\.done).count, 5)
        XCTAssertTrue(SessionLogic.isFinished(data, exercise: exercise(data, "row"), on: today))
        XCTAssertEqual(SessionLogic.nextExercise(data, items: items, after: "row", on: today)?.id, "pullup")
        XCTAssertEqual(SessionLogic.nextExercise(data, items: items, after: "dbrow", on: today)?.id, "pullup", "wraps around")
    }

    func testReferencesUseOnlyEarlierSessions() {
        var data = TestWorld.make()
        data.logSet(exerciseId: "row", date: today.adding(days: -8), weightKg: 70, reps: 5)
        data.logSet(exerciseId: "row", date: today.adding(days: -4), weightKg: 60, reps: 8)
        data.logSet(exerciseId: "row", date: today, weightKg: 100, reps: 8)
        let refs = SessionLogic.references(data, exerciseId: "row", before: today)
        XCTAssertEqual(refs.last!, 60 * (1 + 8.0 / 30), accuracy: 1e-9)
        XCTAssertEqual(refs.best!, 70 * (1 + 5.0 / 30), accuracy: 1e-9, "today's 100 × 8 is not its own reference")
    }

    // MARK: Rest countdown

    func testRestCountdownAdjustsAndFinishes() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var rest = RestCountdown(seconds: 120, now: start)
        XCTAssertEqual(rest.remaining(at: start.addingTimeInterval(36)), 84)
        XCTAssertEqual(rest.fractionRemaining(at: start.addingTimeInterval(60)), 0.5, accuracy: 1e-9)
        rest.adjust(by: 15, now: start.addingTimeInterval(36))
        XCTAssertEqual(rest.remaining(at: start.addingTimeInterval(36)), 99)
        XCTAssertEqual(rest.total, 120, "adding inside the total keeps it")
        rest.adjust(by: 60, now: start.addingTimeInterval(36))
        XCTAssertEqual(rest.total, 159, "the ring grows when the rest outlasts it")
        rest.adjust(by: -500, now: start.addingTimeInterval(40))
        XCTAssertTrue(rest.isFinished(at: start.addingTimeInterval(40)))
        XCTAssertEqual(rest.fractionRemaining(at: start.addingTimeInterval(40)), 0)
    }
}
