import XCTest
@testable import ThubanGymCore

/// The merge rules (GymMerge): two devices editing copies of one document, conflicts, deletions, migration.
final class SyncMergeTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    var today: DayKey { TestWorld.today }

    /// The shared starting point both devices have: the test world with a few logged sets, stamped once.
    func base() -> GymData {
        var data = TestWorld.make()
        data.logSet(exerciseId: "row", date: today.adding(days: -2), weightKg: 60, reps: 8)
        data.logSet(exerciseId: "row", date: today.adding(days: -2), weightKg: 60, reps: 7)
        data.setOverride(date: today.adding(days: 3), workoutId: nil, note: "Trip")
        return data.stamped(from: .empty, now: t0)
    }

    /// A device's copy after `change`, stamped at `t0 + seconds`.
    func edit(_ data: GymData, at seconds: Double, _ change: (inout GymData) throws -> Void) rethrows -> GymData {
        var copy = data
        try change(&copy)
        return copy.stamped(from: data, now: t0.addingTimeInterval(seconds))
    }

    func sets(_ data: GymData, _ exerciseId: String, _ date: DayKey, _ side: Side? = nil) -> [SetEntry] {
        data.sets(exerciseId: exerciseId, date: date, side: side)
    }

    // MARK: Stamping

    func testStampingGivesSetsIdsAndRecordsDeletions() throws {
        let start = base()
        XCTAssertEqual(start.version, GymData.currentVersion)
        XCTAssertTrue(start.logs.flatMap(\.sets).allSatisfy { $0.id != nil && $0.loggedAt != nil })
        XCTAssertTrue(start.workouts.allSatisfy { $0.updatedAt == t0 && $0.order != nil })

        let logged = edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let set = try XCTUnwrap(sets(logged, "bench", today).first)
        XCTAssertNotNil(set.id)
        XCTAssertEqual(set.loggedAt, t0.addingTimeInterval(10))
        // Unchanged records keep their stamps.
        XCTAssertEqual(logged.workout("push")?.updatedAt, t0)

        let removed = edit(logged, at: 20) { $0.removeSet(exerciseId: "bench", date: today, index: 0) }
        XCTAssertEqual(removed.sync.deleted[SyncKey.set(set.id!)], t0.addingTimeInterval(20))

        let deleted = edit(removed, at: 30) { $0.deleteWorkout("upper") }
        XCTAssertNotNil(deleted.sync.deleted[SyncKey.workout("upper")])
        XCTAssertNotNil(deleted.sync.deleted[SyncKey.exercise("fly")])
    }

    func testEditingASetKeepsItsIdentity() throws {
        let start = base()
        let before = try XCTUnwrap(sets(start, "row", today.adding(days: -2)).first)
        let edited = try edit(start, at: 5) { try $0.updateSet(exerciseId: "row", date: today.adding(days: -2), index: 0, weightKg: 62.5, reps: 8) }
        let after = try XCTUnwrap(sets(edited, "row", today.adding(days: -2)).first)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.loggedAt, before.loggedAt)
        XCTAssertEqual(after.weight, 62.5)
        XCTAssertEqual(after.updatedAt, t0.addingTimeInterval(5))
        XCTAssertTrue(edited.sync.deleted.isEmpty)
    }

    func testStampingIsStableThroughTheFile() throws {
        // Whole-second stamps: a document written and read back compares equal (no endless re-sync).
        let data = edit(base(), at: 0.75) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let roundTrip = try JSONFile.decoder.decode(GymData.self, from: JSONFile.encoder.encode(data))
        XCTAssertEqual(roundTrip, data)
        XCTAssertEqual(GymMerge.merge(roundTrip, data), data)
    }

    // MARK: Two devices

    func testTwoDevicesMergeBothWaysToTheSameDocument() {
        let start = base()
        let mac = edit(start, at: 10) {
            $0.updateWorkout("push") { $0.name = "Push A" }
            $0.addExtra(exerciseId: "fly", date: today)
            $0.settings.address = "1 Gym St"
        }
        let phone = edit(start, at: 20) {
            $0.logSet(exerciseId: "row", date: today, weightKg: 70, reps: 8)
            $0.addWorkout(name: "Arms")
        }
        let ab = GymMerge.merge(mac, phone)
        let ba = GymMerge.merge(phone, mac)
        XCTAssertEqual(ab, ba, "commutative")
        XCTAssertEqual(GymMerge.merge(ab, ab), ab, "idempotent")
        XCTAssertEqual(GymMerge.merge(ab, mac), ab, "absorbs an input")
        XCTAssertEqual(GymMerge.merge(ab, phone), ab)

        XCTAssertEqual(ab.workout("push")?.name, "Push A")
        XCTAssertEqual(ab.workouts.last?.name, "Arms")
        XCTAssertEqual(ab.extraIds(on: today), ["fly"])
        XCTAssertEqual(sets(ab, "row", today).map(\.reps), [8])
        XCTAssertEqual(sets(ab, "row", today.adding(days: -2)).count, 2)
    }

    func testSameExerciseLoggedOnBothDevicesKeepsEverySet() {
        let start = base()
        // Neither device had a row for bench today: each creates its own (different row ids).
        let mac = edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let phone = edit(start, at: 12) {
            $0.logSet(exerciseId: "bench", date: today, weightKg: 82.5, reps: 5)
            $0.logSet(exerciseId: "bench", date: today, weightKg: 82.5, reps: 4)
        }
        let merged = GymMerge.merge(mac, phone)
        XCTAssertEqual(merged.logs(exerciseId: "bench", date: today).count, 1, "one row")
        XCTAssertEqual(sets(merged, "bench", today).map(\.weight), [80, 82.5, 82.5], "every set, in logged order")
        XCTAssertEqual(merged, GymMerge.merge(phone, mac))
    }

    func testConcurrentLogDuringAnEdit() {
        let start = base()
        let day = today.adding(days: -2)
        // The phone logs a third set into an existing row while the Mac corrects set 1 and renames the workout.
        let phone = edit(start, at: 30) { $0.logSet(exerciseId: "row", date: day, weightKg: 60, reps: 6) }
        let mac = edit(start, at: 31) {
            try? $0.updateSet(exerciseId: "row", date: day, index: 0, weightKg: 60, reps: 9)
            $0.updateWorkout("pull") { $0.name = "Pull (back)" }
        }
        let merged = GymMerge.merge(phone, mac)
        XCTAssertEqual(sets(merged, "row", day).map(\.reps), [9, 7, 6])
        XCTAssertEqual(merged.workout("pull")?.name, "Pull (back)")
    }

    func testSetsLoggedInTheSameSecondKeepTheirOrder() {
        // Many sets stamped in one change share `loggedAt`; their order must not depend on random id suffixes.
        let day = today.adding(days: -1)
        var data = TestWorld.make()
        for reps in 1...40 { data.logSet(exerciseId: "row", date: day, weightKg: 60, reps: reps) }
        let stamped = data.stamped(from: .empty, now: t0)
        XCTAssertEqual(sets(stamped, "row", day).map(\.reps), Array(1...40))
        // Two more quick taps within the same second, each its own change.
        var next = edit(stamped, at: 0) { $0.logSet(exerciseId: "row", date: day, weightKg: 60, reps: 41) }
        next = edit(next, at: 0) { $0.logSet(exerciseId: "row", date: day, weightKg: 60, reps: 42) }
        XCTAssertEqual(sets(next, "row", day).map(\.reps), Array(1...42))
        XCTAssertEqual(sets(GymMerge.merge(stamped, next), "row", day).map(\.reps), Array(1...42))
        XCTAssertEqual(sets(GymMerge.merge(next, stamped), "row", day).map(\.reps), Array(1...42))
    }

    func testIdsMadeInARowSortInTheOrderTheyWereMade() {
        let ids = (0..<500).map { _ in GymID.make("gs") }
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLaterEditWins() {
        let start = base()
        let early = edit(start, at: 10) { $0.updateWorkout("legs") { $0.name = "Legs early" } }
        let late = edit(start, at: 20) { $0.updateWorkout("legs") { $0.name = "Legs late" } }
        XCTAssertEqual(GymMerge.merge(early, late).workout("legs")?.name, "Legs late")
        XCTAssertEqual(GymMerge.merge(late, early).workout("legs")?.name, "Legs late")
        // Same second: a deterministic winner, the same on both devices.
        let other = edit(start, at: 10) { $0.updateWorkout("legs") { $0.name = "Legs other" } }
        XCTAssertEqual(GymMerge.merge(early, other), GymMerge.merge(other, early))
    }

    func testSingleValuesAreLastWriterWins() {
        let start = base()
        let mac = edit(start, at: 10) { $0.setCyclePosition(2); $0.settings.unit = .lbs }
        let phone = edit(start, at: 20) { _ = $0.startSession(workoutId: "push", date: today, at: t0, today: today) }
        let merged = GymMerge.merge(mac, phone)
        XCTAssertEqual(merged.plan.position, 2, "only the Mac changed the plan")
        XCTAssertEqual(merged.settings.unit, .lbs)
        XCTAssertEqual(merged.activeSession?.workoutId, "push")
        let later = edit(start, at: 30) { $0.setCyclePosition(1) }
        XCTAssertEqual(GymMerge.merge(mac, later).plan.position, 1)
    }

    // MARK: Deletions

    func testDeletedItemsDoNotResurrectFromAStaleCopy() throws {
        let start = base()
        let day = today.adding(days: -2)
        let removedSetId = try XCTUnwrap(sets(start, "row", day).last?.id)
        let mac = edit(start, at: 10) {
            $0.deleteWorkout("upper")
            $0.removeSet(exerciseId: "row", date: day, index: 1)
            $0.clearOverride(date: today.adding(days: 3))
        }
        // The phone never saw those deletions and logs something unrelated.
        let phone = edit(start, at: 20) { $0.logSet(exerciseId: "squat", date: today, weightKg: 100, reps: 5) }
        let merged = GymMerge.merge(phone, mac)
        XCTAssertNil(merged.workout("upper"))
        XCTAssertNil(merged.exercise("fly"))
        XCTAssertFalse(sets(merged, "row", day).contains { $0.id == removedSetId })
        XCTAssertEqual(sets(merged, "row", day).count, 1)
        XCTAssertNil(merged.override(on: today.adding(days: 3)))
        XCTAssertEqual(sets(merged, "squat", today).count, 1)
        // Merging the stale copy again changes nothing.
        XCTAssertEqual(GymMerge.merge(merged, start), merged)
        XCTAssertEqual(GymMerge.merge(start, merged), merged)
    }

    func testRecreatedAfterADeletionWins() {
        let start = base()
        let date = today.adding(days: 3)
        let cleared = edit(start, at: 10) { $0.clearOverride(date: date) }
        let recreated = edit(cleared, at: 20) { $0.setOverride(date: date, workoutId: "legs", note: "Moved") }
        // The other device only has the deletion.
        XCTAssertEqual(GymMerge.merge(cleared, recreated).override(on: date)?.workoutId, "legs")
        XCTAssertEqual(GymMerge.merge(recreated, cleared).override(on: date)?.workoutId, "legs")
    }

    func testDeletedWorkoutTakesAnEditedExerciseAndReferencesWithIt() {
        let start = base()
        let mac = edit(start, at: 10) { $0.deleteWorkout("legs") }
        let phone = edit(start, at: 20) {
            $0.updateExercise("squat") { $0.target = "5×5" }
            $0.setOverride(date: today.adding(days: 1), workoutId: "legs")
        }
        let merged = GymMerge.merge(mac, phone)
        XCTAssertNil(merged.workout("legs"))
        XCTAssertNil(merged.exercise("squat"), "an exercise of a deleted workout goes with it")
        XCTAssertFalse(merged.plan.cycle.contains("legs"))
        XCTAssertFalse(merged.plan.weekly.values.contains("legs"))
        XCTAssertNil(merged.override(on: today.adding(days: 1)))
        XCTAssertEqual(merged, GymMerge.merge(phone, mac))
    }

    func testUndoFinishStillFindsAStampedCompletion() throws {
        var data = base()
        data = edit(data, at: 5) { $0.startSession(workoutId: "push", date: today, at: t0, today: today) }
        var receipt: FinishReceipt?
        data = edit(data, at: 10) { receipt = $0.finishSession(at: t0.addingTimeInterval(3600)) }
        XCTAssertEqual(data.completions(on: today).count, 1)
        XCTAssertNotNil(data.completions(on: today).first?.updatedAt)
        let undone = edit(data, at: 15) { $0.undoFinish(try! XCTUnwrap(receipt)) }
        XCTAssertTrue(undone.completions(on: today).isEmpty)
        XCTAssertEqual(GymMerge.merge(undone, data).completions(on: today).count, 0, "the undo is a tombstone")
    }

    // MARK: Order

    func testMovesAndAdditionsMergeIntoOneOrder() {
        let start = base()
        let mac = edit(start, at: 10) { $0.moveWorkout("upper", to: 0) }
        let changedOrder = mac.workouts.filter { $0.updatedAt == t0.addingTimeInterval(10) }.map(\.id)
        XCTAssertEqual(changedOrder, ["upper"], "a move re-keys only the moved workout")
        let phone = edit(start, at: 20) { $0.addWorkout(name: "Arms"); $0.moveExercise("pullup", to: 0) }
        let merged = GymMerge.merge(mac, phone)
        XCTAssertEqual(merged.workouts.map(\.name), ["Upper", "Push", "Pull", "Legs", "Rest", "Arms"])
        XCTAssertEqual(merged.exercises(in: "pull").map(\.id), ["pullup", "row", "dbrow"])
        XCTAssertEqual(merged, GymMerge.merge(phone, mac))
    }

    func testDuplicateWorkoutKeepsTheListOrder() {
        let start = base()
        let copy = edit(start, at: 10) { _ = $0.duplicateWorkout("pull") }
        XCTAssertEqual(copy.workouts.map(\.name), ["Push", "Pull", "Pull copy", "Legs", "Rest", "Upper"])
        XCTAssertEqual(GymMerge.merge(copy, start).workouts.map(\.name), copy.workouts.map(\.name))
    }

    // MARK: Migration

    /// A format-1 gym.json as the app wrote it before sync (no version key, no ids, no stamps).
    static let legacyJSON = #"""
    {
      "workouts": [{"id": "gw-push", "name": "Push"}, {"id": "gw-pull", "name": "Pull"}],
      "exercises": [{"id": "ge-bench", "workoutId": "gw-push", "name": "Bench", "target": "3×5"},
                    {"id": "ge-row", "workoutId": "gw-pull", "name": "Row", "target": "3×8"}],
      "logs": [{"id": "gl-1", "exerciseId": "ge-bench", "date": "2026-09-20", "sets": [{"weight": 80, "reps": 5}, {"weight": 80, "reps": 5}]},
               {"id": "gl-2", "exerciseId": "ge-row", "date": "2026-09-21", "side": null, "sets": [{"weight": 60, "reps": 8}]}],
      "completions": [{"workoutId": "gw-push", "date": "2026-09-20", "ts": 1790000000000, "start": "17:00", "end": "18:00", "auto": false}],
      "plan": {"type": "cycle", "weekly": {}, "cycle": ["gw-push", "gw-pull"], "position": 1},
      "overrides": [], "extras": [],
      "settings": {"unit": "lbs", "address": "", "hours": {}, "defaultDuration": 75, "restSeconds": 120},
      "lastRollover": "2026-09-24"
    }
    """#

    func testOldFileLoadsWithDeterministicIdentity() throws {
        let data = try JSONFile.decoder.decode(GymData.self, from: Data(Self.legacyJSON.utf8))
        XCTAssertEqual(data.version, 1)
        XCTAssertEqual(data.workouts.count, 2)
        XCTAssertEqual(data.sets(exerciseId: "ge-bench", date: DayKey("2026-09-20")!).map(\.id), ["gl-1~000", "gl-1~001"])
        XCTAssertEqual(data.workouts.map(\.order), [0, 1])
        let again = try JSONFile.decoder.decode(GymData.self, from: Data(Self.legacyJSON.utf8))
        XCTAssertEqual(again, data, "every device derives the same ids")
    }

    func testMigrationSnapshotsTheOldFileOnceAndKeepsEverything() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-sync-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = GymStore(directory: directory)
        try Data(Self.legacyJSON.utf8).write(to: store.fileURL)

        let (loaded, migrated) = try store.loadMigrating()
        XCTAssertTrue(migrated)
        XCTAssertEqual(store.backups().map(\.label), ["before-sync-migration"])
        let snapshot = try String(contentsOf: store.backups()[0].url, encoding: .utf8)
        XCTAssertEqual(snapshot, Self.legacyJSON, "the snapshot is the untouched old file")

        let upgraded = loaded.stamped(from: loaded, now: t0)
        XCTAssertEqual(upgraded.version, GymData.currentVersion)
        XCTAssertEqual(upgraded.logs.flatMap(\.sets).count, 3)
        XCTAssertEqual(upgraded.completions.count, 1)
        XCTAssertEqual(upgraded.plan.position, 1)
        XCTAssertTrue(upgraded.sync.deleted.isEmpty)
        try store.save(upgraded, today: TestWorld.today)

        let (reloaded, again) = try store.loadMigrating()
        XCTAssertFalse(again)
        XCTAssertEqual(reloaded, upgraded)
        XCTAssertEqual(store.backups().filter { $0.label == "before-sync-migration" }.count, 1)
    }

    func testTwoMigratedCopiesOfTheSameOldFileDoNotDuplicate() throws {
        let old = try JSONFile.decoder.decode(GymData.self, from: Data(Self.legacyJSON.utf8))
        let day = DayKey("2026-09-20")!
        let mac = edit(old.stamped(from: old, now: t0), at: 10) { $0.logSet(exerciseId: "ge-bench", date: day, weightKg: 80, reps: 4) }
        let phone = edit(old.stamped(from: old, now: t0.addingTimeInterval(3)), at: 20) { $0.logSet(exerciseId: "ge-bench", date: day, weightKg: 85, reps: 3) }
        let merged = GymMerge.merge(mac, phone)
        XCTAssertEqual(merged.sets(exerciseId: "ge-bench", date: day).map(\.reps), [5, 5, 4, 3])
        XCTAssertEqual(merged.workouts.count, 2)
        XCTAssertEqual(merged.completions.count, 1)
    }

    func testMergingAnUnstampedImportIsDeterministic() {
        // Two devices importing the same Atlas data independently agree on set ids.
        var imported = TestWorld.make()
        imported.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5)
        var a = imported; a.assignLegacyIdentity()
        var b = imported; b.assignLegacyIdentity()
        XCTAssertEqual(GymMerge.merge(a.stamped(from: .empty, now: t0), b.stamped(from: .empty, now: t0.addingTimeInterval(9)))
                        .sets(exerciseId: "bench", date: today).count, 1)
    }

    // MARK: Status text

    func testStatusText() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = TestWorld.today.date(hour: 12, minute: 0, calendar: calendar)
        let synced = TestWorld.today.date(hour: 9, minute: 41, calendar: calendar)
        XCTAssertEqual(SyncStatus.upToDate(synced).text(now: now, calendar: calendar), "Up to date · last synced 9:41 AM")
        XCTAssertEqual(SyncStatus.upToDate(synced.addingTimeInterval(-86_400)).text(now: now, calendar: calendar), "Up to date · last synced Sep 23, 9:41 AM")
        XCTAssertEqual(SyncStatus.syncing.text(), "Syncing…")
        XCTAssertEqual(SyncStatus.off(.unsignedBuild).text(), "Off: iCloud needs a signed build")
        XCTAssertEqual(SyncStatus.off(.turnedOff).text(), "Off: turned off")
    }

    func testLocator() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cloud")
        XCTAssertEqual(CloudLocator.availability(environment: [CloudLocator.cloudDirVariable: dir.path, AppPaths.homeVariable: "/tmp/x"], info: nil),
                       .available(dir.appendingPathComponent("Documents/gym.json"), ubiquitous: false))
        XCTAssertEqual(CloudLocator.availability(environment: [AppPaths.homeVariable: "/tmp/x"], info: [CloudLocator.infoKey: "YES"]), .unavailable(.testHome))
        XCTAssertEqual(CloudLocator.availability(environment: [:], info: [CloudLocator.infoKey: "NO"]), .unavailable(.unsignedBuild))
        XCTAssertEqual(CloudLocator.availability(environment: [:], info: [:]), .unavailable(.unsignedBuild))
        XCTAssertTrue(CloudLocator.buildHasICloud(info: [CloudLocator.infoKey: "YES"]))
    }
}
