import Foundation
import Observation

/// What Settings shows for iCloud Sync.
public enum SyncStatus: Equatable, Sendable {
    case off(CloudOffReason)
    /// Looking for iCloud (just enabled / launched).
    case starting
    case syncing
    case upToDate(Date)
    case failed(String)

    /// "Up to date · last synced 9:41 AM", "Syncing…", "Off: iCloud needs a signed build", "Sync failed: …".
    public func text(now: Date = Date(), calendar: Calendar = .current) -> String {
        switch self {
        case .off(let reason): return "Off: \(reason.message)"
        case .starting: return "Checking iCloud…"
        case .syncing: return "Syncing…"
        case .upToDate(let date): return "Up to date · last synced \(Self.when(date, now: now, calendar: calendar))"
        case .failed(let message): return "Sync failed: \(message)"
        }
    }

    public var isOn: Bool {
        switch self {
        case .off: return false
        default: return true
        }
    }

    static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        formatter.dateFormat = calendar.isDate(date, inSameDayAs: now) ? "h:mm a" : "MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

/// Per-device sync bookkeeping (`sync-state.json` next to the local gym.json; never synced).
public struct SyncState: Codable, Equatable, Sendable {
    /// A first sync with iCloud has completed on this device (the "before icloud" snapshot was taken before it).
    public var linked = false
    public var lastSynced: Date?

    public init() {}

    public static func url(in directory: URL) -> URL { directory.appendingPathComponent("sync-state.json") }

    public static func load(from directory: URL) -> SyncState {
        (try? JSONFile.read(SyncState.self, from: url(in: directory))) ?? SyncState()
    }

    public func save(to directory: URL) {
        try? JSONFile.write(self, to: SyncState.url(in: directory), permissions: 0o600)
    }
}

/// iCloud sync for the app model. The local `GymStore` (Application Support gym.json + backups) stays the working
/// copy and offline cache; this keeps the shared iCloud copy merged with it:
///
/// - `requestSync(data)` after every local save: a coordinated read-merge-write of the shared file on a background
///   queue (coalesced — only the newest pending document is sent). The merged result comes back through
///   `onMerged` on the main actor; the app merges it into what it holds now (so a set logged meanwhile is kept),
///   saves locally, and asks again only if its copy still differs.
/// - Remote changes (the file presenter, the iCloud metadata query, app activation, "Sync now") trigger the same
///   operation with the app's current document.
/// - First enable on a device: a "before icloud" snapshot of the local file, then the same merge — a missing shared
///   file is created from the local one; when both exist they are merged, never replaced.
@MainActor
@Observable
public final class GymSync {
    public private(set) var status: SyncStatus = .off(.turnedOff)
    public private(set) var lastSynced: Date?
    /// The shared file (nil while off).
    public private(set) var cloudFileURL: URL?
    /// Smoke / preview only: shown in place of the real status.
    public var statusOverride: SyncStatus?
    public var displayStatus: SyncStatus { statusOverride ?? status }

    /// Receives each merged shared document (main actor).
    @ObservationIgnored public var onMerged: ((GymData) -> Void)?
    /// The app's current document, or nil when it must not be synced (unreadable local file).
    @ObservationIgnored public var currentData: (() -> GymData?)?

    @ObservationIgnored private let local: GymStore
    @ObservationIgnored private let locate: @Sendable () -> CloudAvailability
    @ObservationIgnored private let worker = DispatchQueue(label: "org.thuban.gym.sync", qos: .utility)
    @ObservationIgnored private var document: CloudDocumentStore?
    @ObservationIgnored private var watcher: CloudMetadataWatcher?
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var blocked: CloudOffReason?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var running = false
    @ObservationIgnored private var queued: GymData?
    @ObservationIgnored private var state: SyncState
    @ObservationIgnored private var identityObserver: NSObjectProtocol?

    public init(local: GymStore, locate: @escaping @Sendable () -> CloudAvailability = { CloudLocator.availability() }) {
        self.local = local
        self.locate = locate
        state = SyncState.load(from: local.directory)
        lastSynced = state.lastSynced
    }

    /// The user's switch (Settings ▸ iCloud Sync). Turning it on looks for iCloud and syncs.
    public func setEnabled(_ on: Bool) {
        guard on != enabled || document == nil else { return }
        enabled = on
        restart()
    }

    /// Keeps sync off for a reason the app knows about (e.g. the local file cannot be read).
    public func block(_ reason: CloudOffReason?) {
        blocked = reason
        restart()
    }

    /// Queues a merge of `data` with the shared copy (no-op while off).
    public func requestSync(_ data: GymData) {
        guard document != nil else { return }
        queued = data
        runIfIdle()
    }

    /// "Sync now", app activation: re-checks iCloud when it was unavailable, otherwise merges the current document.
    public func syncNow() {
        guard enabled, blocked == nil else { return }
        guard document != nil else {
            restart()
            return
        }
        if let data = currentData?() { requestSync(data) }
    }

    /// Stops presenting / watching (app teardown, tests).
    public func stop() {
        generation += 1
        teardown()
    }

    // MARK: Internals

    private func restart() {
        generation += 1
        teardown()
        if let blocked {
            status = .off(blocked)
            return
        }
        guard enabled else {
            status = .off(.turnedOff)
            return
        }
        status = .starting
        let token = generation
        let locate = self.locate
        worker.async { [weak self] in
            let availability = locate()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.didLocate(availability, generation: token) }
            }
        }
    }

    private func didLocate(_ availability: CloudAvailability, generation token: Int) {
        guard token == generation, enabled, blocked == nil else { return }
        observeIdentity()
        switch availability {
        case .unavailable(let reason):
            status = .off(reason)
        case .available(let url, let ubiquitous):
            cloudFileURL = url
            let store = CloudDocumentStore(fileURL: url, conflicts: ubiquitous ? FileVersionConflicts() : NoConflictVersions())
            store.onChange = { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.remoteChanged() } }
            }
            store.startPresenting()
            document = store
            if ubiquitous {
                watcher = CloudMetadataWatcher(fileName: url.lastPathComponent) { [weak self] in self?.remoteChanged() }
            }
            if let data = currentData?() {
                requestSync(data)
            } else {
                status = .off(.localUnreadable)
            }
        }
    }

    private func remoteChanged() {
        guard document != nil, let data = currentData?() else { return }
        requestSync(data)
    }

    private func runIfIdle() {
        guard !running, let payload = queued, let store = document else { return }
        queued = nil
        running = true
        status = .syncing
        let token = generation
        let snapshotFirst = !state.linked
        let local = self.local
        worker.async { [weak self] in
            if snapshotFirst { _ = try? local.snapshot(label: "before icloud") }
            let result = Result { try store.synchronize(with: payload) }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finish(result, generation: token) }
            }
        }
    }

    private func finish(_ result: Result<SyncOutcome, Error>, generation token: Int) {
        running = false
        guard token == generation else {
            runIfIdle()
            return
        }
        switch result {
        case .success(let outcome):
            let now = Date()
            lastSynced = now
            state.linked = true
            state.lastSynced = now
            state.save(to: local.directory)
            if queued == nil { status = .upToDate(now) }
            onMerged?(outcome.merged)
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
        runIfIdle()
    }

    private func teardown() {
        document?.stopPresenting()
        document = nil
        watcher?.stop()
        watcher = nil
        cloudFileURL = nil
        queued = nil
    }

    private func observeIdentity() {
        guard identityObserver == nil else { return }
        identityObserver = NotificationCenter.default.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.enabled else { return }
                self.restart()
            }
        }
    }
}

/// Watches the shared file through Spotlight's iCloud index: asks iCloud to download a newer copy when one
/// appears, and reports every change (downloaded, uploaded, replaced) so the app merges it.
final class CloudMetadataWatcher: NSObject, @unchecked Sendable {
    private let query = NSMetadataQuery()
    private let onChange: @MainActor () -> Void
    private var observers: [NSObjectProtocol] = []

    @MainActor
    init(fileName: String, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, fileName)
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle() }
            })
        }
        query.start()
    }

    @MainActor
    private func handle() {
        query.disableUpdates()
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if status != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
        }
        query.enableUpdates()
        onChange()
    }

    func stop() {
        query.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
}
