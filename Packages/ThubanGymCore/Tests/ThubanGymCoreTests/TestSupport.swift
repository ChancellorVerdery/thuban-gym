import Foundation
@testable import ThubanGymCore

/// A small fixed world: Push / Pull / Legs / Rest cycle + Upper (not in the cycle), one exercise each.
enum TestWorld {
    static let today = DayKey("2026-09-24")! // a Thursday

    static func make(type: PlanType = .cycle, position: Int = 0) -> GymData {
        var data = GymData()
        data.workouts = [
            Workout(id: "push", name: "Push"),
            Workout(id: "pull", name: "Pull"),
            Workout(id: "legs", name: "Legs"),
            Workout(id: "rest", name: "Rest", rest: true),
            Workout(id: "upper", name: "Upper"),
        ]
        data.exercises = [
            Exercise(id: "bench", workoutId: "push", name: "Bench Press", target: "4×5"),
            Exercise(id: "row", workoutId: "pull", name: "Barbell Row", target: "4×8"),
            Exercise(id: "pullup", workoutId: "pull", name: "Pull-up", bodyweight: true, target: "4×6–8"),
            Exercise(id: "dbrow", workoutId: "pull", name: "Single-arm DB Row", unilateral: true, target: "3×10"),
            Exercise(id: "squat", workoutId: "legs", name: "Back Squat", target: "4×5"),
            Exercise(id: "fly", workoutId: "upper", name: "Rear Delt Fly", target: "3×12"),
        ]
        data.plan = Plan(type: type,
                         weekly: ["mon": "push", "tue": "pull", "wed": "legs", "thu": "rest", "fri": "upper"],
                         cycle: ["push", "pull", "legs", "rest"], position: position)
        data.lastRollover = today
        return data
    }

    static func day(_ offset: Int) -> DayKey { today.adding(days: offset) }

    static func fixtureURL(_ name: String) -> URL {
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)
            ?? Bundle.module.resourceURL!.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }
}

/// Returns canned output; records what it was asked to run.
final class FixtureRunner: CommandRunner, @unchecked Sendable {
    var result: CommandResult
    private(set) var executable: String?
    private(set) var arguments: [String] = []
    private(set) var stdin = Data()

    init(result: CommandResult) { self.result = result }

    func run(executable: String, arguments: [String], stdin: Data, timeout: TimeInterval) async throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        self.stdin = stdin
        return result
    }
}
