import XCTest
@testable import ThubanGymCore

final class StoreAndSampleTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-gym-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLoadEmptySaveAndReload() throws {
        let store = GymStore(directory: directory)
        XCTAssertFalse(store.exists)
        XCTAssertEqual(try store.load(), .empty)
        let data = TestWorld.make()
        try store.save(data, today: TestWorld.today)
        XCTAssertEqual(try store.load(), data)
        XCTAssertTrue(store.backups().isEmpty) // nothing to back up on the first write
    }

    func testDailyBackupOncePerDay() throws {
        let store = GymStore(directory: directory)
        var data = TestWorld.make()
        try store.save(data, today: TestWorld.today)
        data.logSet(exerciseId: "row", date: TestWorld.today, weightKg: 60, reps: 8)
        try store.save(data, today: TestWorld.today)
        try store.save(data, today: TestWorld.today)
        XCTAssertEqual(store.backups().filter { $0.label == "daily" }.count, 1)
        // The daily backup holds the state before the day's first write.
        let backup = try store.read(backup: store.backups()[0].url)
        XCTAssertTrue(backup.logs.isEmpty)
        try store.save(data, today: TestWorld.today.adding(days: 1))
        XCTAssertEqual(store.backups().filter { $0.label == "daily" }.count, 2)
    }

    func testSnapshotAndPrune() throws {
        let store = GymStore(directory: directory)
        XCTAssertNil(try store.snapshot(label: "before import"))
        try store.save(TestWorld.make(), today: TestWorld.today)
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        for i in 0..<(GymStore.snapshotsKept + 3) {
            try store.snapshot(label: "before import", now: base.addingTimeInterval(Double(i)))
        }
        let snapshots = store.backups().filter { $0.label == "before-import" }
        XCTAssertEqual(snapshots.count, GymStore.snapshotsKept)
    }

    func testCorruptFileThrows() throws {
        let store = GymStore(directory: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
    }

    func testPreferencesDecodeTolerantly() throws {
        let prefs = try JSONFile.decoder.decode(Preferences.self, from: Data(#"{"atlasHost":"nas"}"#.utf8))
        XCTAssertEqual(prefs.atlasHost, "nas")
        XCTAssertEqual(prefs.atlasEmail, Preferences.defaultAtlasEmail)
        XCTAssertEqual(prefs.theme, .default)
    }

    func testSampleDataIsCoherent() throws {
        let today = TestWorld.today
        let now = today.date(hour: 18, minute: 13)
        let data = SampleData.make(today: today, now: now)
        XCTAssertEqual(data, SampleData.make(today: today, now: now)) // deterministic
        XCTAssertEqual(data.workouts.map(\.name), ["Push", "Pull", "Legs", "Rest", "Upper", "Lower", "Flex"])
        XCTAssertEqual(data.settings.unit, .lbs)
        let todayPlan = PlanEngine.day(data, on: today, today: today)
        XCTAssertEqual(todayPlan.status, .inProgress)
        XCTAssertEqual(todayPlan.workout?.name, "Pull")
        XCTAssertEqual(PlanEngine.day(data, on: today.adding(days: 1), today: today).status, .skipped)
        XCTAssertEqual(PlanEngine.sessionExercises(data, workoutId: todayPlan.workout?.id, on: today).filter(\.isExtra).count, 1)
        XCTAssertGreaterThan(Stats.sessionCount(data), 100)
        let score = try XCTUnwrap(Scoring.strengthScore(data, on: today))
        XCTAssertGreaterThan(score, 105)
        XCTAssertLessThan(score, 140)
        XCTAssertGreaterThan(Scoring.strengthSeries(data).count, 100)
        XCTAssertTrue(data.completions.contains { $0.auto })
    }
}
