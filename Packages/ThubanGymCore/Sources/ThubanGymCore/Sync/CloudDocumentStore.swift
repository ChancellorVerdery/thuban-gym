import Foundation

/// One conflicting copy of the shared file (iCloud keeps these when two devices wrote before seeing each other).
public struct ConflictVersion {
    public var url: URL
    /// The `NSFileVersion` behind it (nil in tests).
    public var reference: AnyObject?

    public init(url: URL, reference: AnyObject? = nil) {
        self.url = url
        self.reference = reference
    }
}

/// Where conflict versions come from. Real iCloud: `NSFileVersion`. Tests: plain files in a temp folder.
public protocol ConflictVersionSource: AnyObject {
    func unresolvedVersions(of url: URL) -> [ConflictVersion]
    /// Marks `versions` resolved. `removeOthers` is true when EVERY unresolved version was merged, so the old
    /// versions can be deleted; otherwise the unreadable ones are left for a later run (never discarded).
    func markResolved(_ versions: [ConflictVersion], of url: URL, removeOthers: Bool) throws
}

/// `NSFileVersion` conflict versions of an iCloud document.
public final class FileVersionConflicts: ConflictVersionSource {
    public init() {}

    public func unresolvedVersions(of url: URL) -> [ConflictVersion] {
        (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { ConflictVersion(url: $0.url, reference: $0) }
    }

    public func markResolved(_ versions: [ConflictVersion], of url: URL, removeOthers: Bool) throws {
        for version in versions { (version.reference as? NSFileVersion)?.isResolved = true }
        if removeOthers { try NSFileVersion.removeOtherVersionsOfItem(at: url) }
    }
}

/// No conflict versions (a plain folder standing in for iCloud: `THUBAN_GYM_CLOUD_DIR`).
public final class NoConflictVersions: ConflictVersionSource {
    public init() {}
    public func unresolvedVersions(of url: URL) -> [ConflictVersion] { [] }
    public func markResolved(_ versions: [ConflictVersion], of url: URL, removeOthers: Bool) throws {}
}

/// What one synchronization did.
public struct SyncOutcome: Sendable {
    /// The shared document after the merge (what the device should now hold).
    public var merged: GymData
    /// The shared file was (re)written.
    public var wroteCloud: Bool
    /// There was a shared file before (false = first upload).
    public var cloudExisted: Bool
    /// Conflict versions merged and resolved.
    public var resolvedConflicts: Int
    /// Conflict versions that could not be read (left in place).
    public var unreadableConflicts: Int
}

/// The shared `gym.json` in the iCloud container (`<container>/Documents/gym.json`), read and written with
/// `NSFileCoordinator` so the iCloud daemon and other processes never see a half-written file. It is also the
/// file's `NSFilePresenter`: changes written by another device (the daemon applies them through file coordination)
/// arrive as `onChange`.
///
/// There is no blind overwrite: `synchronize(with:)` reads the shared copy and every unresolved conflict version,
/// merges them with the local document (`GymMerge`), writes the result only when it differs, and resolves the
/// conflict versions it merged. Runs on a background queue (coordination can wait on the daemon).
///
/// A shared file that iCloud has but this device has not downloaded yet (a placeholder, a dataless file, a stale
/// copy, or a file only the metadata query knows about) is waited for, never read as "no shared file": after
/// `downloadTimeout` the sync fails and writes nothing, so a new or reconnecting device cannot upload its own copy
/// over the shared one.
public final class CloudDocumentStore: NSObject, NSFilePresenter, @unchecked Sendable {
    public let fileURL: URL
    public let conflicts: ConflictVersionSource
    /// Whether the shared file is on this device (see `CloudItemState`).
    public let itemStatus: CloudItemStatus
    /// How long `synchronize(with:)` waits for iCloud to finish downloading the shared file before giving up.
    public var downloadTimeout: TimeInterval = 30
    /// How often the download state is checked while waiting.
    public var downloadPollInterval: TimeInterval = 0.25
    /// Called on the presenter queue when another writer changed / replaced / deleted the file.
    public var onChange: (() -> Void)?

    public let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "org.thuban.gym.cloud-presenter"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    public var presentedItemURL: URL? { fileURL }

    private let lock = NSLock()
    private var presenting = false

    public init(fileURL: URL, conflicts: ConflictVersionSource = FileVersionConflicts(),
                itemStatus: CloudItemStatus = UbiquitousItemStatus()) {
        self.fileURL = fileURL
        self.conflicts = conflicts
        self.itemStatus = itemStatus
        super.init()
    }

    deinit { stopPresenting() }

    public func startPresenting() {
        lock.lock(); defer { lock.unlock() }
        guard !presenting else { return }
        presenting = true
        NSFileCoordinator.addFilePresenter(self)
    }

    public func stopPresenting() {
        lock.lock(); defer { lock.unlock() }
        guard presenting else { return }
        presenting = false
        NSFileCoordinator.removeFilePresenter(self)
    }

    // MARK: Reading and synchronizing

    /// The shared document (coordinated read), nil when there is none yet.
    public func read() throws -> GymData? {
        var coordinationError: NSError?
        var result: Result<GymData?, Error> = .success(nil)
        NSFileCoordinator(filePresenter: self).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try Self.readFile(at: url) }
        }
        if let coordinationError { throw ThubanError.store("iCloud: \(coordinationError.localizedDescription)") }
        return try result.get()
    }

    /// Merges `local` into the shared file (coordinated read-merge-write, conflict versions included) and returns
    /// the merged document. Throws — and writes nothing — when the shared copy exists but cannot be read, was
    /// written by a newer app version, or is still downloading from iCloud after `downloadTimeout`.
    public func synchronize(with local: GymData) throws -> SyncOutcome {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw ThubanError.store("iCloud folder unavailable: \(error.localizedDescription)")
        }
        try waitUntilDownloaded()
        var coordinationError: NSError?
        var result: Result<SyncOutcome, Error> = .failure(ThubanError.store("iCloud sync did not run."))
        // A coordinated write "for merging" is also a coordinated read: iCloud downloads the latest copy first.
        NSFileCoordinator(filePresenter: self).coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            result = Result { try self.mergeCoordinated(at: url, local: local) }
        }
        if let coordinationError { throw ThubanError.store("iCloud: \(coordinationError.localizedDescription)") }
        return try result.get()
    }

    /// Blocks (background queue) until the shared file is absent or current here. Throws when it is still
    /// downloading at the deadline — the caller must not merge, since the cloud's copy is not readable yet.
    func waitUntilDownloaded() throws {
        let deadline = Date().addingTimeInterval(downloadTimeout)
        var asked = false
        while itemStatus.state(of: fileURL) == .downloading {
            if !asked || Date() >= deadline { itemStatus.startDownloading(fileURL); asked = true }
            guard Date() < deadline else { throw Self.stillDownloading }
            Thread.sleep(forTimeInterval: downloadPollInterval)
        }
    }

    static let stillDownloading = ThubanError.store(
        "gym.json is still downloading from iCloud, so nothing was synced yet (this device's log is untouched). It syncs once the download finishes.")

    private func mergeCoordinated(at url: URL, local: GymData) throws -> SyncOutcome {
        let cloud = try Self.readFile(at: url)
        // Nothing readable, yet iCloud has the file (it went back to the cloud since the wait): never "first upload".
        if cloud == nil, itemStatus.state(of: fileURL) == .downloading {
            itemStatus.startDownloading(fileURL)
            throw Self.stillDownloading
        }
        var merged = GymMerge.merge(local, local) // normal form
        if let cloud { merged = GymMerge.merge(merged, cloud) }

        var resolved: [ConflictVersion] = []
        var unreadable = 0
        for version in conflicts.unresolvedVersions(of: url) {
            do {
                guard let other = try Self.readFile(at: version.url) else { resolved.append(version); continue }
                merged = GymMerge.merge(merged, other)
                resolved.append(version)
            } catch {
                unreadable += 1
            }
        }

        let write = cloud != merged
        if write {
            do {
                try JSONFile.encoder.encode(merged).write(to: url, options: .atomic)
            } catch {
                throw ThubanError.store("gym.json could not be written to iCloud: \(error.localizedDescription)")
            }
        }
        if !resolved.isEmpty {
            try conflicts.markResolved(resolved, of: url, removeOthers: unreadable == 0)
        }
        return SyncOutcome(merged: merged, wroteCloud: write, cloudExisted: cloud != nil,
                           resolvedConflicts: resolved.count, unreadableConflicts: unreadable)
    }

    /// nil for a missing or empty file.
    static func readFile(at url: URL) throws -> GymData? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes: Data
        do { bytes = try Data(contentsOf: url) } catch {
            throw ThubanError.store("The iCloud copy of gym.json could not be opened: \(error.localizedDescription)")
        }
        guard !bytes.isEmpty else { return nil }
        let data: GymData
        do { data = try JSONFile.decoder.decode(GymData.self, from: bytes) } catch {
            throw ThubanError.store("The iCloud copy of gym.json could not be read, so nothing was synced (this device's log is untouched).")
        }
        guard data.version <= GymData.currentVersion else {
            throw ThubanError.store("The iCloud copy was written by a newer Thuban Gym. Update this app to sync.")
        }
        return data
    }

    // MARK: NSFilePresenter

    public func presentedItemDidChange() { onChange?() }

    public func presentedItemDidGain(_ version: NSFileVersion) { onChange?() }

    public func presentedItemDidResolveConflict(_ version: NSFileVersion) { onChange?() }

    public func accommodatePresentedItemDeletion(completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)
        onChange?()
    }
}
