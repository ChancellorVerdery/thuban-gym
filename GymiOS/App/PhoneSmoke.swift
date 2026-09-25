import Foundation
import SwiftUI
import ThubanGymCore
import UIKit

/// The visual smoke run (scripts/ios_smoke.sh). Launched with `THUBAN_GYM_SMOKE=phone` or `=ipad` (through
/// `SIMCTL_CHILD_`), the app moves its data to a fresh temporary home, seeds `SampleData`, then walks the screens.
/// For each one it writes `<name>.ready` into `tmp/smoke-shots/` of its container and waits for the script to take
/// the simulator screenshot and answer with `<name>.done`. `finished` marks the end. Never touches real data.
@MainActor
enum PhoneSmoke {
    static let variable = "THUBAN_GYM_SMOKE"
    static var mode: String? {
        let value = ProcessInfo.processInfo.environment[variable]?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value
    }
    static var isEnabled: Bool { mode != nil }

    static var shotsDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("smoke-shots", isDirectory: true)
    }

    /// Before anything reads `AppPaths`: a fresh, empty home in the container's tmp.
    static func prepareEnvironment() {
        guard isEnabled else { return }
        let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("smoke-home-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        setenv(AppPaths.homeVariable, home.path, 1)
        try? FileManager.default.removeItem(at: shotsDirectory)
        try? FileManager.default.createDirectory(at: shotsDirectory, withIntermediateDirectories: true)
    }

    private static var started = false

    static func startIfEnabled(app: AppModel) {
        guard let mode, !started else { return }
        started = true
        Task { @MainActor in
            await Task.yield()
            if mode == "ipad" { await runPad(app) } else { await runPhone(app) }
            try? Data().write(to: shotsDirectory.appendingPathComponent("finished"))
        }
    }

    // MARK: Steps

    private static func settle(_ seconds: Double = 1.2) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Signals the script and waits (up to 30 s) for the screenshot.
    private static func shot(_ name: String, settle seconds: Double = 1.2) async {
        await settle(seconds)
        let ready = shotsDirectory.appendingPathComponent("\(name).ready")
        let done = shotsDirectory.appendingPathComponent("\(name).done")
        try? Data().write(to: ready)
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: done.path) { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        AppModel.logger.error("smoke: no screenshot for \(name, privacy: .public)")
    }

    private static func exerciseId(_ app: AppModel, named name: String) -> String? {
        app.data.exercises.first { $0.name == name }?.id
    }

    private static func workoutId(_ app: AppModel, named name: String) -> String? {
        app.workouts.first { $0.name == name }?.id
    }

    private static func runPhone(_ app: AppModel) async {
        app.setAppearanceMode(.light)
        app.tab = .today
        await shot("10-today", settle: 2)
        app.tab = .plan
        await shot("11-plan")
        app.tab = .workouts
        await shot("12-workouts")
        app.tab = .progress
        await shot("13-progress")
        if let row = exerciseId(app, named: "Barbell Row") {
            app.progressPath = [.exercise(row)]
            await shot("14-exercise-history")
            app.progressPath = []
        }
        if let pull = workoutId(app, named: "Pull") {
            app.tab = .workouts
            app.workoutsPath = [.workout(pull)]
            await shot("15-workout-editor")
            app.workoutsPath = []
        }
        app.tab = .today
        await settle(0.6)
        app.showSettings = true
        await shot("16-settings")
        app.showSettings = false
        await settle(0.8)

        // At the gym: log Barbell Row set 3, type a weight on the number pad, rest.
        let row = exerciseId(app, named: "Barbell Row")
        app.openSession(exerciseId: row)
        await shot("20-logging", settle: 1.6)
        app.smokeFocus = "weight"
        await shot("21-logging-number-pad", settle: 1.8)
        app.smokeFocus = nil
        if let item = app.sessionExercise {
            app.logSet(item.exercise, draft: SessionLogic.suggestion(app.data, exercise: item.exercise, on: app.sessionDay, side: nil))
        }
        await shot("22-rest", settle: 3.2)

        // Dark Brass.
        app.setAppearanceMode(.dark)
        await shot("70-rest-dark", settle: 1.6)
        app.endRest()
        await shot("71-logging-dark", settle: 1.4)
        app.smokeFocus = "weight"
        await shot("72-logging-number-pad-dark", settle: 1.8)
        app.minimizeSession()
        await shot("73-today-dark", settle: 1.6)
        app.tab = .progress
        await shot("74-progress-dark")
        app.tab = .plan
        await shot("75-plan-dark")
        app.tab = .today
        app.setAppearanceMode(.light)
        await settle(1)

        // Finish the workout: a last, heavier Barbell Row set (a new best) and the Pull-up sets, for highlights.
        app.openSession()
        await settle(1.2)
        if let id = row, let exercise = app.exercise(id) {
            app.logSet(exercise, draft: SetDraft(weightKg: app.unit.toKilograms(145), reps: 8))
            app.cancelRest()
        }
        app.finishWorkout()
        await shot("30-finished", settle: 1.6)
        app.closeFinished()
        await shot("31-today-done", settle: 1.6)

        // First run (an empty phone).
        app.replaceData(.empty)
        await shot("40-first-run", settle: 1.4)
    }

    private static func runPad(_ app: AppModel) async {
        // The board is the landscape iPad (1180 × 820).
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeLeft.rawValue, forKey: "orientation")
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeLeft)) { error in
                AppModel.logger.error("smoke: rotation refused: \(error.localizedDescription, privacy: .public)")
            }
            scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        await settle(1.5)
        app.setAppearanceMode(.light)
        app.padSection = .today
        app.focusedExerciseId = exerciseId(app, named: "Barbell Row")
        app.sessionPresented = true
        await shot("80-ipad-session", settle: 2.4)
        if let item = app.sessionExercise {
            app.logSet(item.exercise, draft: SessionLogic.suggestion(app.data, exercise: item.exercise, on: app.sessionDay, side: nil))
        }
        await shot("81-ipad-rest", settle: 2)
        app.endRest()
        app.padSection = .plan
        await shot("82-ipad-plan")
        app.padSection = .progress
        await shot("83-ipad-progress")
        app.padSection = .workouts
        await shot("84-ipad-workouts")
        app.padSection = .today
        app.setAppearanceMode(.dark)
        await shot("85-ipad-session-dark", settle: 1.8)
        app.setAppearanceMode(.light)
    }
}
