import Foundation
import ThubanGymCore

/// Extra Settings smoke screens (every pane is already captured by the standard walk). OWNER: Engineer C.
/// The import states are built from the sample world: it is written out as the Atlas JSON document the SQL
/// returns, decoded and converted exactly like a real import (no ssh).
extension SmokeScenes {
    @MainActor private static var settingsSavedData: GymData?

    static var settings: [SmokeScene] {
        [
            // First run: nothing local yet, Atlas checked → the counts preview (the design's welcome).
            SmokeScene(name: "settings-import-first-run", window: .settings, settle: 1.5) { app in
                let sample = app.data
                settingsSavedData = sample
                app.replaceData(.empty)
                app.importPhase = SettingsSmokeFixtures.preview(of: sample, app: app)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
                if let saved = settingsSavedData { app.replaceData(saved) }
                settingsSavedData = nil
            },
            // Re-import over existing data: the preview says what it replaces.
            SmokeScene(name: "settings-import-preview", window: .settings) { app in
                app.importPhase = SettingsSmokeFixtures.preview(of: app.data, app: app)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-fetching", window: .settings) { app in
                app.importPhase = .fetching
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-done", window: .settings) { app in
                if case .preview(let preview) = SettingsSmokeFixtures.preview(of: app.data, app: app) {
                    app.importPhase = .done(preview.summary, backup: app.dataFolder.appendingPathComponent("backups/gym-before-import-20260924-181200.json"))
                }
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-failed", window: .settings) { app in
                app.importPhase = .failed("ssh: Could not resolve hostname beelink: nodename nor servname provided, or not known")
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
            },
            SmokeScene(name: "settings-import-dark", window: .settings) { app in
                app.setAppearanceMode(.dark)
                app.importPhase = SettingsSmokeFixtures.preview(of: app.data, app: app)
                app.openSettings(.importAtlas)
            } cleanup: { app in
                app.importPhase = .idle
                app.setAppearanceMode(.light)
            },
            SmokeScene(name: "settings-plan-dark", window: .settings) { app in
                app.setAppearanceMode(.dark)
                app.openSettings(.plan)
            } cleanup: { app in
                app.setAppearanceMode(.light)
            },
        ]
    }
}

@MainActor
enum SettingsSmokeFixtures {
    /// `.preview` for `data` round-tripped through the Atlas JSON format and `AtlasImporter.convert`.
    static func preview(of data: GymData, app: AppModel) -> ImportPhase {
        do {
            let json = try JSONSerialization.data(withJSONObject: atlasDocument(from: data))
            let document = try AtlasDocument.decode(json)
            let source = "atlas:\(app.preferences.atlasHost)"
            let converted = try AtlasImporter.convert(document, source: source)
            return .preview(ImportPreview(
                summary: converted.summary, data: converted.data, source: source,
                replacesExisting: !app.data.isEmpty,
                localWorkouts: app.data.workouts.count,
                localSets: app.data.logs.reduce(0) { $0 + $1.sets.count },
                localSessions: Stats.sessionCount(app.data)))
        } catch {
            return .failed("smoke fixture: \(error.localizedDescription)")
        }
    }

    /// The document `AtlasImporter.sql` returns, built from a local `GymData` (snake_case rows, kg weights).
    static func atlasDocument(from data: GymData) -> [String: Any] {
        func nullable(_ value: Any?) -> Any { value ?? NSNull() }
        return [
            "format": AtlasDocument.format,
            "email": Preferences.defaultAtlasEmail,
            "user_found": true,
            "settings": [
                "unit": data.settings.unit.rawValue,
                "address": data.settings.address,
                "default_duration": data.settings.defaultDuration,
                "plan_type": data.plan.type.rawValue,
                "cycle_position": data.plan.position,
            ] as [String: Any],
            "hours": Weekday.allCases.map { day -> [String: Any] in
                let hours = data.settings.hours(for: day)
                return ["day": day.rawValue, "open": hours.open, "close": hours.close]
            },
            "workouts": data.workouts.map { ["id": $0.id, "name": $0.name, "rest": $0.rest, "flex": $0.flex] as [String: Any] },
            "exercises": data.exercises.map {
                ["id": $0.id, "workout_id": $0.workoutId, "name": $0.name, "unilateral": $0.unilateral, "target": $0.target] as [String: Any]
            },
            "logs": data.logs.map { log -> [String: Any] in
                ["id": log.id, "exercise_id": log.exerciseId, "date": log.date.rawValue, "side": nullable(log.side?.rawValue),
                 "sets": log.sets.map { ["weight": nullable($0.weight), "reps": $0.reps] as [String: Any] }]
            },
            "completions": data.completions.filter { !$0.auto }.map {
                ["workout_id": $0.workoutId, "date": $0.date.rawValue, "ts": $0.ts, "start_time": $0.start, "end_time": $0.end] as [String: Any]
            },
            "plan_weekly": data.plan.weekly.sorted { $0.key < $1.key }.map { ["day": $0.key, "workout_id": $0.value] },
            "plan_cycle": data.plan.cycle.enumerated().map { ["position": $0.offset, "workout_id": $0.element] as [String: Any] },
            "plan_overrides": data.overrides.map { ["date": $0.date.rawValue, "workout_id": $0.workoutId ?? "skip"] },
            "plan_extras": data.extras.map { ["date": $0.date.rawValue, "exercise_id": $0.exerciseId] },
        ]
    }
}
