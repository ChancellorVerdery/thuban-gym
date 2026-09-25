import Foundation
import ThubanGymCore
import UIKit

/// The at-the-gym flow: open the logger, log a set (which starts the session and the rest timer), rest, undo,
/// finish, review. Every write goes through the shared mutations (`logSet`, `startSession`, `finishSession` …).
extension AppModel {
    // MARK: Reading the session

    /// The exercises the logger walks through (the day's workout, then extras).
    var sessionItems: [SessionExercise] { todayVisibleItems() }

    /// The exercise on screen: the focused one, else the first unfinished, else the first.
    var sessionExercise: SessionExercise? {
        let items = sessionItems
        if let id = focusedExerciseId, let item = items.first(where: { $0.id == id }) { return item }
        return items.first { !SessionLogic.isFinished(data, exercise: $0.exercise, on: sessionDay) } ?? items.first
    }

    var sessionProgress: SessionProgress { SessionLogic.progress(data, items: sessionItems, on: sessionDay) }

    /// The workout the logger is for: the running session's, else today's.
    var sessionWorkout: Workout? { activeWorkout ?? todayPlan.workout }

    /// Today is done (a training completion exists and nothing is running).
    var todayIsDone: Bool { activeSession == nil && todayPlan.status == .done }

    // MARK: Opening

    /// "Start Pull": starts today's planned session (when none is running) and opens the logger.
    func beginSession(workoutId: String? = nil) {
        if activeSession == nil { startSession(workoutId: workoutId) }
        openSession()
    }

    /// Opens the logger on an exercise (a Today row). Nothing is recorded until a set is logged.
    func openSession(exerciseId: String? = nil) {
        if let exerciseId { focusedExerciseId = exerciseId }
        editingSet = nil
        if case .finished = sessionStage { sessionStage = .logging }
        if rest != nil { sessionStage = .resting }
        sessionPresented = true
        if tab != .today { tab = .today }
        if padSection != .today { padSection = .today }
    }

    /// The chevron: the logger goes away; the session and any rest keep running.
    func minimizeSession() {
        sessionPresented = false
        editingSet = nil
    }

    // MARK: Logging

    /// Logs the draft for `exercise` (the side is chosen by the core: left, then right). Starts today's session
    /// when nothing is running, then the rest timer (or, for a left side, waits for the right).
    func logSet(_ exercise: Exercise, draft: SetDraft) {
        let date = sessionDay
        if let editing = editingSet, editing.exerciseId == exercise.id {
            updateSet(exerciseId: exercise.id, date: editing.date, side: editing.side, index: editing.index,
                      weightKg: draft.entry.weight, reps: draft.reps)
            editingSet = nil
            return
        }
        let side = SessionLogic.nextSide(data, exercise: exercise, on: date)
        if activeSession == nil, !todayIsDone, let planned = todayPlan.workout, !planned.isRest {
            startSession(workoutId: planned.id)
        }
        let index = logSet(exerciseId: exercise.id, date: date, side: side, weightKg: draft.entry.weight, reps: draft.reps)
        lastLogged = LoggedSet(exerciseId: exercise.id, date: date, side: side, index: index, set: draft.entry)
        focusedExerciseId = exercise.id
        if side == .left { return } // the right side of the pair comes next, without a rest
        if SessionLogic.isFinished(data, exercise: exercise, on: date),
           let next = SessionLogic.nextExercise(data, items: sessionItems, after: exercise.id, on: date) {
            focusedExerciseId = next.id
        }
        if preferences.restAutoStart { startRest() }
    }

    /// Removes the set the rest screen reports and returns to it.
    func undoLastSet() {
        guard let last = lastLogged else { return }
        let sets = data.sets(exerciseId: last.exerciseId, date: last.date, side: last.side)
        if last.index < sets.count, sets[last.index] == last.set {
            removeSet(exerciseId: last.exerciseId, date: last.date, side: last.side, index: last.index)
        }
        focusedExerciseId = last.exerciseId
        lastLogged = nil
        cancelRest()
    }

    func deleteSet(_ set: LoggedSet) {
        removeSet(exerciseId: set.exerciseId, date: set.date, side: set.side, index: set.index)
        if editingSet == set { editingSet = nil }
        if lastLogged == set { lastLogged = nil }
    }

    // MARK: Rest

    func startRest(seconds: Int? = nil) {
        let length = seconds ?? restSeconds(for: sessionWorkout?.id)
        rest = RestCountdown(seconds: length)
        sessionStage = .resting
        scheduleRestAlert()
        restTick()
    }

    func adjustRest(by seconds: TimeInterval) {
        guard var countdown = rest else { return }
        countdown.adjust(by: seconds)
        rest = countdown
        scheduleRestAlert()
        restTick()
    }

    /// "Skip rest, start set 4" (also the end of a finished rest).
    func endRest() {
        cancelRest()
    }

    func cancelRest() {
        rest = nil
        restTask?.cancel()
        restTask = nil
        alerts.cancel()
        if sessionStage == .resting { sessionStage = .logging }
    }

    /// Fires the haptic at 0:00 while the app is on screen (the notification covers the background).
    func restTick() {
        restTask?.cancel()
        guard let countdown = rest else { return }
        let wait = countdown.remaining(at: Date())
        guard wait > 0 else { return }
        restTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self, self.rest == countdown else { return }
            if self.preferences.restAlert, UIApplication.shared.applicationState == .active { self.alerts.restFinishedInForeground() }
        }
    }

    private func scheduleRestAlert() {
        guard let countdown = rest, preferences.restAlert else { alerts.cancel(); return }
        let next = sessionExercise.map { "Next: \($0.exercise.name)." } ?? "Time for the next set."
        alerts.schedule(at: countdown.endsAt, title: "Rest is over", body: next)
    }

    // MARK: Finishing

    func finishWorkout() {
        cancelRest()
        editingSet = nil
        guard let receipt = finishSession() else { return }
        lastLogged = nil
        sessionStage = .finished(WorkoutSummary.make(data, completion: receipt.completion))
    }

    /// "Review and edit sets": undoes the finish so the sets can be changed; Finish records it again.
    func reviewFinishedSets() {
        undoFinish()
        sessionStage = .logging
    }

    /// "Done" on the summary.
    func closeFinished() {
        sessionPresented = false
        sessionStage = .logging
        focusedExerciseId = nil
    }
}
