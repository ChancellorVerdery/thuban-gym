import XCTest
@testable import ThubanGymCore

/// Conflict versions as plain files (what `NSFileVersion` hands out on a real iCloud container).
final class FolderConflicts: ConflictVersionSource {
    var versions: [URL]
    private(set) var resolved: [URL] = []
    private(set) var removedOthers = false

    init(_ versions: [URL]) { self.versions = versions }

    func unresolvedVersions(of url: URL) -> [ConflictVersion] { versions.map { ConflictVersion(url: $0) } }

    func markResolved(_ versions: [ConflictVersion], of url: URL, removeOthers: Bool) throws {
        let done = Set(versions.map(\.url))
        resolved += versions.map(\.url)
        self.versions.removeAll { done.contains($0) }
        if removeOthers { removedOthers = true }
    }
}

/// iCloud's download state, scripted: the file is "in the cloud but not here" until `download` runs (after
/// `pollsBeforeDownload` checks; nil = never).
final class ScriptedItemStatus: CloudItemStatus, @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0
    private var downloaded = false
    let pollsBeforeDownload: Int?
    let download: () -> Void
    private(set) var downloadRequests = 0

    init(pollsBeforeDownload: Int?, download: @escaping () -> Void = {}) {
        self.pollsBeforeDownload = pollsBeforeDownload
        self.download = download
    }

    func state(of url: URL) -> CloudItemState {
        lock.lock(); defer { lock.unlock() }
        if downloaded { return .current }
        polls += 1
        if let limit = pollsBeforeDownload, polls > limit {
            download()
            downloaded = true
            return .current
        }
        return .downloading
    }

    func startDownloading(_ url: URL) {
        lock.lock(); downloadRequests += 1; lock.unlock()
    }
}

/// The shared file without iCloud: two "devices" (two stores / two sync controllers) on one temp folder.
final class SyncCloudTests: XCTestCase {
    var root: URL!
    var cloudFile: URL { root.appendingPathComponent("cloud/Documents/gym.json") }
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    var today: DayKey { TestWorld.today }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("thuban-cloud-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func base() -> GymData { TestWorld.make().stamped(from: .empty, now: t0) }

    func edit(_ data: GymData, at seconds: Double, _ change: (inout GymData) -> Void) -> GymData {
        var copy = data
        change(&copy)
        return copy.stamped(from: data, now: t0.addingTimeInterval(seconds))
    }

    func write(_ data: GymData, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONFile.encoder.encode(data).write(to: url)
    }

    // MARK: CloudDocumentStore

    func testTwoDevicesWritingTheSameFileConverge() throws {
        let start = base()
        let macStore = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions())
        let phoneStore = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions())

        // First enable on the Mac: no shared file yet → upload the local one.
        var mac = edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let first = try macStore.synchronize(with: mac)
        XCTAssertFalse(first.cloudExisted)
        XCTAssertTrue(first.wroteCloud)
        XCTAssertEqual(try macStore.read(), mac)

        // The phone had its own copy with other changes: both exist → merged, nothing discarded.
        var phone = edit(start, at: 20) {
            $0.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8)
            $0.updateWorkout("legs") { $0.name = "Legs (phone)" }
        }
        let second = try phoneStore.synchronize(with: phone)
        XCTAssertTrue(second.cloudExisted)
        XCTAssertTrue(second.wroteCloud)
        phone = GymMerge.merge(phone, second.merged)
        XCTAssertEqual(phone.sets(exerciseId: "bench", date: today).count, 1)
        XCTAssertEqual(phone.sets(exerciseId: "row", date: today).count, 1)

        // The Mac logs again, then syncs: it gets the phone's changes and keeps its own.
        mac = edit(mac, at: 30) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let third = try macStore.synchronize(with: mac)
        mac = GymMerge.merge(mac, third.merged)
        XCTAssertEqual(mac.sets(exerciseId: "bench", date: today).count, 2)
        XCTAssertEqual(mac.workout("legs")?.name, "Legs (phone)")

        // The phone catches up; everyone holds the same document and nobody needs to write again.
        let fourth = try phoneStore.synchronize(with: phone)
        phone = GymMerge.merge(phone, fourth.merged)
        XCTAssertFalse(fourth.wroteCloud, "the phone's copy was already contained in the shared one")
        XCTAssertEqual(phone, mac)
        XCTAssertEqual(try macStore.read(), mac)
        XCTAssertFalse(try macStore.synchronize(with: mac).wroteCloud)
    }

    func testConflictVersionsAreMergedAndResolved() throws {
        let start = base()
        let current = edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let conflictA = edit(start, at: 11) { $0.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) }
        let conflictB = edit(start, at: 12) { $0.deleteWorkout("upper") }
        try write(current, to: cloudFile)
        let a = root.appendingPathComponent("versions/a.json"), b = root.appendingPathComponent("versions/b.json")
        try write(conflictA, to: a)
        try write(conflictB, to: b)
        let conflicts = FolderConflicts([a, b])
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: conflicts)

        let local = edit(start, at: 13) { $0.logSet(exerciseId: "squat", date: today, weightKg: 100, reps: 5) }
        let outcome = try store.synchronize(with: local)
        XCTAssertEqual(outcome.resolvedConflicts, 2)
        XCTAssertTrue(conflicts.removedOthers)
        XCTAssertTrue(conflicts.versions.isEmpty)
        let merged = try XCTUnwrap(try store.read())
        XCTAssertEqual(merged.sets(exerciseId: "bench", date: today).count, 1)
        XCTAssertEqual(merged.sets(exerciseId: "row", date: today).count, 1)
        XCTAssertEqual(merged.sets(exerciseId: "squat", date: today).count, 1)
        XCTAssertNil(merged.workout("upper"))
    }

    func testAnUnreadableConflictVersionIsLeftInPlace() throws {
        let start = base()
        try write(start, to: cloudFile)
        let bad = root.appendingPathComponent("versions/bad.json")
        try FileManager.default.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ torn".utf8).write(to: bad)
        let good = root.appendingPathComponent("versions/good.json")
        try write(edit(start, at: 5) { $0.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) }, to: good)
        let conflicts = FolderConflicts([bad, good])
        let outcome = try CloudDocumentStore(fileURL: cloudFile, conflicts: conflicts).synchronize(with: start)
        XCTAssertEqual(outcome.unreadableConflicts, 1)
        XCTAssertEqual(outcome.resolvedConflicts, 1)
        XCTAssertFalse(conflicts.removedOthers, "never delete a version that was not merged")
        XCTAssertEqual(conflicts.versions, [bad])
        XCTAssertEqual(outcome.merged.sets(exerciseId: "row", date: today).count, 1)
    }

    func testAnUnreadableSharedFileIsNeverOverwritten() throws {
        try FileManager.default.createDirectory(at: cloudFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: cloudFile)
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions())
        XCTAssertThrowsError(try store.synchronize(with: base()))
        XCTAssertEqual(try String(contentsOf: cloudFile, encoding: .utf8), "{ not json")

        var newer = base()
        newer.version = GymData.currentVersion + 1
        try JSONFile.encoder.encode(newer).write(to: cloudFile)
        XCTAssertThrowsError(try store.synchronize(with: base())) { error in
            XCTAssertTrue(error.localizedDescription.contains("newer"))
        }
    }

    // MARK: Not-yet-downloaded shared file (placeholder race)

    func testASharedFileStillDownloadingIsWaitedForNotOverwritten() throws {
        // The Mac's data is in iCloud; the phone was just installed and iCloud is still downloading gym.json.
        let start = base()
        let shared = edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        let phoneLocal = edit(start, at: 20) { $0.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) }
        let status = ScriptedItemStatus(pollsBeforeDownload: 3) { [cloudFile, weak self] in
            try? self?.write(shared, to: cloudFile)
        }
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions(), itemStatus: status)
        store.downloadPollInterval = 0.01

        let outcome = try store.synchronize(with: phoneLocal)
        XCTAssertTrue(outcome.cloudExisted, "the downloaded copy was merged, not treated as missing")
        XCTAssertGreaterThan(status.downloadRequests, 0)
        let merged = try XCTUnwrap(try store.read())
        XCTAssertEqual(merged.sets(exerciseId: "bench", date: today).count, 1, "the Mac's set survives")
        XCTAssertEqual(merged.sets(exerciseId: "row", date: today).count, 1, "the phone's set is added")
    }

    func testADownloadThatNeverFinishesFailsWithoutWriting() throws {
        let status = ScriptedItemStatus(pollsBeforeDownload: nil)
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions(), itemStatus: status)
        store.downloadTimeout = 0.1
        store.downloadPollInterval = 0.01
        XCTAssertThrowsError(try store.synchronize(with: base())) { error in
            XCTAssertTrue(error.localizedDescription.contains("still downloading"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFile.path), "nothing uploaded over the cloud's copy")
    }

    func testALegacyPlaceholderIsNotAMissingFile() throws {
        // Pre-FileProvider iCloud: `.gym.json.icloud` stands where gym.json will be.
        let placeholder = UbiquitousItemStatus.placeholderURL(for: cloudFile)
        XCTAssertEqual(placeholder.lastPathComponent, ".gym.json.icloud")
        try FileManager.default.createDirectory(at: placeholder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: placeholder)
        let status = UbiquitousItemStatus()
        XCTAssertEqual(status.state(of: cloudFile), .downloading)
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions(), itemStatus: status)
        store.downloadTimeout = 0.1
        store.downloadPollInterval = 0.01
        XCTAssertThrowsError(try store.synchronize(with: base()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFile.path))
    }

    func testAFileOnlyTheICloudListingKnowsIsNotAMissingFile() throws {
        let status = UbiquitousItemStatus()
        XCTAssertEqual(status.state(of: cloudFile), .absent, "unknown listing, nothing on disk: a real first upload")
        status.cloudListed = true
        XCTAssertEqual(status.state(of: cloudFile), .downloading)
        let store = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions(), itemStatus: status)
        store.downloadTimeout = 0.1
        store.downloadPollInterval = 0.01
        XCTAssertThrowsError(try store.synchronize(with: base()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFile.path))

        status.cloudListed = false
        XCTAssertTrue(try store.synchronize(with: base()).wroteCloud, "iCloud lists no file: upload")
        XCTAssertEqual(status.state(of: cloudFile), .current, "a local, non-ubiquitous file is current")
    }

    func testThePresenterHearsAnotherWriter() throws {
        let start = base()
        try write(start, to: cloudFile)
        let watching = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions())
        let heard = expectation(description: "presentedItemDidChange")
        heard.assertForOverFulfill = false
        watching.onChange = { heard.fulfill() }
        watching.startPresenting()
        defer { watching.stopPresenting() }

        let writer = CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions())
        let changed = edit(start, at: 5) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) }
        XCTAssertTrue(try writer.synchronize(with: changed).wroteCloud)
        wait(for: [heard], timeout: 5)
    }

    // MARK: GymSync (the controller the apps use)

    @MainActor
    final class Device {
        let store: GymStore
        let sync: GymSync
        var data: GymData

        init(home: URL, cloudFile: URL, data: GymData) throws {
            store = GymStore(directory: home)
            self.data = data
            try store.save(data, today: TestWorld.today)
            sync = GymSync(local: store, locate: { .available(cloudFile, ubiquitous: false) })
            sync.currentData = { [unowned self] in self.data }
            sync.onMerged = { [unowned self] merged in
                // What AppModel.adoptSynced does: keep anything changed meanwhile, push again only if needed.
                let combined = GymMerge.merge(self.data, merged)
                if combined != self.data { self.data = combined }
                if combined != merged { self.sync.requestSync(combined) }
            }
        }

        func change(at date: Date, _ edit: (inout GymData) -> Void) {
            var copy = data
            edit(&copy)
            data = copy.stamped(from: data, now: date)
            sync.requestSync(data)
        }
    }

    @MainActor
    func waitUntil(_ what: String, timeout: TimeInterval = 10, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out waiting for \(what)"); return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    func testSyncControllersOnTwoDevicesConverge() async throws {
        let start = base()
        let mac = try Device(home: root.appendingPathComponent("mac"), cloudFile: cloudFile,
                             data: edit(start, at: 10) { $0.logSet(exerciseId: "bench", date: today, weightKg: 80, reps: 5) })
        let phone = try Device(home: root.appendingPathComponent("phone"), cloudFile: cloudFile,
                               data: edit(start, at: 20) { $0.logSet(exerciseId: "row", date: today, weightKg: 60, reps: 8) })
        defer { mac.sync.stop(); phone.sync.stop() }

        mac.sync.setEnabled(true)
        try await waitUntil("mac up to date") { if case .upToDate = mac.sync.status { return true } else { return false } }
        XCTAssertEqual(mac.store.backups().map(\.label), ["before-icloud"], "the local file is snapshotted before the first sync")
        XCTAssertTrue(SyncState.load(from: mac.store.directory).linked)

        phone.sync.setEnabled(true)
        try await waitUntil("phone has both") { phone.data.sets(exerciseId: "bench", date: self.today).count == 1 }
        XCTAssertEqual(phone.data.sets(exerciseId: "row", date: today).count, 1)

        // A set logged while a sync is in flight is kept (merged into what comes back).
        phone.change(at: t0.addingTimeInterval(40)) { $0.logSet(exerciseId: "row", date: today, weightKg: 62.5, reps: 8) }
        phone.change(at: t0.addingTimeInterval(41)) { $0.logSet(exerciseId: "row", date: today, weightKg: 62.5, reps: 7) }
        try await waitUntil("phone idle") { if case .upToDate = phone.sync.status { return true } else { return false } }

        mac.sync.syncNow()
        try await waitUntil("mac has the phone's sets") { mac.data.sets(exerciseId: "row", date: self.today).count == 3 }
        try await waitUntil("mac idle") { if case .upToDate = mac.sync.status { return true } else { return false } }
        XCTAssertEqual(mac.data, phone.data)
        XCTAssertEqual(try CloudDocumentStore(fileURL: cloudFile, conflicts: NoConflictVersions()).read(), mac.data)
    }

    @MainActor
    func testSyncOffReasons() async throws {
        let store = GymStore(directory: root.appendingPathComponent("home"))
        let unsigned = GymSync(local: store, locate: { .unavailable(.unsignedBuild) })
        XCTAssertEqual(unsigned.status, .off(.turnedOff))
        unsigned.currentData = { .empty }
        unsigned.setEnabled(true)
        try await waitUntil("located") { unsigned.status != .starting }
        XCTAssertEqual(unsigned.status, .off(.unsignedBuild))
        unsigned.setEnabled(false)
        XCTAssertEqual(unsigned.status, .off(.turnedOff))

        let blocked = GymSync(local: store, locate: { .available(self.cloudFile, ubiquitous: false) })
        blocked.currentData = { .empty }
        blocked.block(.localUnreadable)
        blocked.setEnabled(true)
        XCTAssertEqual(blocked.status, .off(.localUnreadable))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cloudFile.path))
    }
}
