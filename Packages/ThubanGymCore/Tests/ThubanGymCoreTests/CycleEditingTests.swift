import XCTest
@testable import ThubanGymCore

final class CycleEditingTests: XCTestCase {
    // Cycle: push, pull, legs, rest.

    func testMoveKeepsPointerOnItsSlot() {
        var data = TestWorld.make(position: 1) // pointer on pull
        data.moveCycleSlot(from: 1, to: 3)
        XCTAssertEqual(data.plan.cycle, ["push", "legs", "rest", "pull"])
        XCTAssertEqual(data.plan.position, 3)

        data.moveCycleSlot(from: 0, to: 3) // push to the end; pull shifts left
        XCTAssertEqual(data.plan.cycle, ["legs", "rest", "pull", "push"])
        XCTAssertEqual(data.plan.cycle[data.plan.position], "pull")
    }

    func testMoveWithDuplicatesTracksTheSlotNotTheName() {
        var data = TestWorld.make()
        data.plan.cycle = ["push", "rest", "pull", "rest"]
        data.plan.position = 3 // the SECOND rest
        data.moveCycleSlot(from: 3, to: 0)
        XCTAssertEqual(data.plan.cycle, ["rest", "push", "rest", "pull"])
        XCTAssertEqual(data.plan.position, 0)

        data.moveCycleSlot(from: 2, to: 3) // the other rest moves; the pointer slot does not
        XCTAssertEqual(data.plan.position, 0)
    }

    func testMoveOutOfRangeIsIgnoredOrClamped() {
        var data = TestWorld.make(position: 2)
        data.moveCycleSlot(from: 9, to: 0)
        XCTAssertEqual(data.plan.cycle, ["push", "pull", "legs", "rest"])
        data.moveCycleSlot(from: 0, to: 99)
        XCTAssertEqual(data.plan.cycle, ["pull", "legs", "rest", "push"])
        XCTAssertEqual(data.plan.cycle[data.plan.position], "legs")
    }

    func testInsert() {
        var data = TestWorld.make(position: 1)
        data.insertCycleSlot("upper") // end
        XCTAssertEqual(data.plan.cycle, ["push", "pull", "legs", "rest", "upper"])
        XCTAssertEqual(data.plan.position, 1)
        data.insertCycleSlot("legs", at: 0)
        XCTAssertEqual(data.plan.cycle.first, "legs")
        XCTAssertEqual(data.plan.cycle[data.plan.position], "pull")
        data.insertCycleSlot("rest", at: data.plan.position) // right before the pointer
        XCTAssertEqual(data.plan.cycle[data.plan.position], "pull")
    }

    func testInsertIntoEmptyCycle() {
        var data = TestWorld.make()
        data.plan.cycle = []
        data.plan.position = 0
        data.insertCycleSlot("push")
        XCTAssertEqual(data.plan.cycle, ["push"])
        XCTAssertEqual(data.plan.position, 0)
    }

    func testRemove() {
        var data = TestWorld.make(position: 2) // legs
        data.removeCycleSlot(at: 0)
        XCTAssertEqual(data.plan.cycle, ["pull", "legs", "rest"])
        XCTAssertEqual(data.plan.cycle[data.plan.position], "legs")

        data.removeCycleSlot(at: 2) // after the pointer
        XCTAssertEqual(data.plan.cycle[data.plan.position], "legs")

        data.removeCycleSlot(at: data.plan.position) // the pointer's own slot → the next one (wraps)
        XCTAssertEqual(data.plan.cycle, ["pull"])
        XCTAssertEqual(data.plan.position, 0)

        data.removeCycleSlot(at: 0)
        XCTAssertEqual(data.plan.cycle, [])
        XCTAssertEqual(data.plan.position, 0)
    }

    func testRemovingPointerSlotHandsNextUpToTheFollowingSlot() {
        var data = TestWorld.make(position: 1) // pull
        data.removeCycleSlot(at: 1)
        XCTAssertEqual(data.plan.cycle, ["push", "legs", "rest"])
        XCTAssertEqual(data.plan.cycle[data.plan.position], "legs")
    }

    func testEditsNeverTouchOverridesOrCompletions() {
        var data = TestWorld.make(position: 1)
        data.setOverride(date: TestWorld.day(1), workoutId: nil, note: "Travel")
        data.addExtra(exerciseId: "fly", date: TestWorld.today)
        let overrides = data.overrides, extras = data.extras, completions = data.completions
        data.moveCycleSlot(from: 0, to: 2)
        data.insertCycleSlot("upper", at: 1)
        data.removeCycleSlot(at: 3)
        XCTAssertEqual(data.overrides, overrides)
        XCTAssertEqual(data.extras, extras)
        XCTAssertEqual(data.completions, completions)
    }
}
