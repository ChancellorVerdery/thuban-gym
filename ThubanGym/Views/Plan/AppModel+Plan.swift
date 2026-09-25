import Foundation
import ThubanGymCore

/// Plan + Workouts queries and writes (Engineer B). Built only from `data` / `today`, the core's public functions and
/// `mutate`, so nothing shared changes.
extension AppModel {
    // MARK: Cycle editing (slot-precise; the pointer stays on its slot)

    func moveCycleSlot(from: Int, to: Int) { mutate { $0.moveCycleSlot(from: from, to: to) } }
    func insertCycleSlot(_ workoutId: String, at index: Int? = nil) { mutate { $0.insertCycleSlot(workoutId, at: index) } }
    func removeCycleSlot(at index: Int) { mutate { $0.removeCycleSlot(at: index) } }

    // MARK: Plan reads

    /// Extras on today and later, date order (Plan → "Extras").
    var upcomingExtras: [PlanExtra] {
        data.extras.enumerated()
            .filter { $0.element.date >= today }
            .sorted { $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date }
            .map(\.element)
    }

    /// Workout completions (manual ones; the midnight auto-completes of rest days are left out), oldest first.
    func completions(of workoutId: String) -> [Completion] {
        data.completions.filter { $0.workoutId == workoutId && !$0.auto }.sorted { $0.date < $1.date }
    }

    /// The most recent day (on or before today) the workout was completed, if within `days` days.
    func lastDone(_ workoutId: String, within days: Int? = nil) -> DayKey? {
        let last = data.completions.filter { $0.workoutId == workoutId && $0.date <= today }.map(\.date).max()
        guard let last else { return nil }
        if let days, last.days(to: today) >= days { return nil }
        return last
    }

    /// Σ target sets of a workout's exercises.
    func plannedSets(in workoutId: String) -> Int {
        exercises(in: workoutId).reduce(0) { $0 + ($1.targetSpec?.sets ?? 0) }
    }

    /// Whether any session has been timed for the workout (so "avg 62 min" is real, not the default).
    func hasTimedSessions(_ workoutId: String) -> Bool {
        data.completions.contains { $0.workoutId == workoutId && $0.durationMinutes != nil }
    }

    /// "5 exercises · 16 sets · avg 62 min" / "Rest day · completes itself at midnight" / "Log anything".
    func workoutSummary(_ workout: Workout, includeDuration: Bool = true) -> String {
        switch workout.kind {
        case .rest: return "Rest day · completes itself at midnight"
        case .flex:
            let count = exercises(in: workout.id).count
            return count == 0 ? "Log anything" : "\(Self.plural(count, "exercise")) · log anything"
        case .training:
            let count = exercises(in: workout.id).count
            var parts = [Self.plural(count, "exercise")]
            let sets = plannedSets(in: workout.id)
            if sets > 0 { parts.append(Self.plural(sets, "set")) }
            if includeDuration, hasTimedSessions(workout.id) { parts.append("avg \(workoutDuration(workout.id)) min") }
            return parts.joined(separator: " · ")
        }
    }

    static func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    /// The latest session's e1RM of an exercise with its unit ("177.3 lb" / "8 reps"), or nil before any log.
    func currentScoreText(_ exercise: Exercise) -> String? {
        guard let history = history(exerciseId: exercise.id), let score = history.score else { return nil }
        let text = self.score(score, bodyweight: history.isBodyweight)
        return history.isBodyweight ? text : "\(text) \(unit.label)"
    }
}
