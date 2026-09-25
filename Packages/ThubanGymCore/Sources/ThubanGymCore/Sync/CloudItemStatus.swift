import Foundation

/// What this device holds of the shared file. The difference between `.absent` and `.downloading` is the whole
/// point: an iCloud file that exists in the cloud but has not reached this device yet must never be read as
/// "no shared file" (that would upload this device's copy over everyone else's).
public enum CloudItemState: Equatable, Sendable {
    /// Nothing here, and iCloud does not list the file either: a real first upload.
    case absent
    /// The local copy is the latest one iCloud knows of (or a plain folder standing in for iCloud).
    case current
    /// iCloud has the file but this device's copy is missing, a placeholder, or older than the cloud's.
    case downloading
}

/// Reports `CloudItemState` for the shared file and asks iCloud to download it. Real iCloud:
/// `UbiquitousItemStatus`. Tests: a scripted fake.
public protocol CloudItemStatus: AnyObject, Sendable {
    func state(of url: URL) -> CloudItemState
    func startDownloading(_ url: URL)
}

/// The iCloud download state of a file, from three sources (any one of them saying "in the cloud, not here" wins):
/// - the file's own resource values (`ubiquitousItemDownloadingStatus` is not `.current`: a dataless file or a
///   stale copy),
/// - a legacy placeholder (`.gym.json.icloud` next to where `gym.json` will be),
/// - the iCloud metadata listing (`cloudListed`, fed by the `NSMetadataQuery` in `GymSync`): the file exists in the
///   container even though nothing is on disk yet (a fresh install before iCloud created the placeholder).
public final class UbiquitousItemStatus: CloudItemStatus, @unchecked Sendable {
    private let lock = NSLock()
    private var listed: Bool?

    public init() {}

    /// What the iCloud metadata query last said: true = iCloud lists the file, false = it does not, nil = unknown.
    public var cloudListed: Bool? {
        get { lock.lock(); defer { lock.unlock() }; return listed }
        set { lock.lock(); listed = newValue; lock.unlock() }
    }

    public func state(of url: URL) -> CloudItemState {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        // (`resourceValues` does not throw for a missing file on every OS, so check existence first.)
        if FileManager.default.fileExists(atPath: url.path),
           let values = try? fresh.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) {
            guard values.isUbiquitousItem == true else { return .current }
            return values.ubiquitousItemDownloadingStatus == .current ? .current : .downloading
        }
        if FileManager.default.fileExists(atPath: Self.placeholderURL(for: url).path) { return .downloading }
        if cloudListed == true { return .downloading }
        return .absent
    }

    public func startDownloading(_ url: URL) {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    /// The pre-FileProvider iCloud placeholder for `url`: `.<name>.icloud` in the same folder.
    public static func placeholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }
}
