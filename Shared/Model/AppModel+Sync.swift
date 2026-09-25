import Foundation
import ThubanGymCore

/// iCloud Sync, as the Settings rows on both apps use it (Mac: Settings ▸ Data & storage; iOS: Settings ▸ Data).
extension AppModel {
    /// What the status line shows (a smoke run may override it).
    var syncStatus: SyncStatus { sync.displayStatus }

    /// The per-device switch (preferences.json; never synced).
    var iCloudSyncEnabled: Bool {
        get { preferences.iCloudSync }
        set { preferences.iCloudSync = newValue }
    }

    /// "Sync now": re-checks iCloud when it was unavailable, otherwise merges with the shared copy.
    func syncNow() { sync.syncNow() }

    /// "Sync now" does something useful: on, and not already working / impossible for this build.
    var canSyncNow: Bool {
        guard preferences.iCloudSync else { return false }
        switch syncStatus {
        case .starting, .syncing, .off(.unsignedBuild), .off(.testHome), .off(.turnedOff), .off(.localUnreadable): return false
        default: return true
        }
    }
}

/// How the status dot / text is coloured.
enum SyncTone { case good, busy, idle, bad }

extension SyncStatus {
    var tone: SyncTone {
        switch self {
        case .upToDate: return .good
        case .starting, .syncing: return .busy
        case .off: return .idle
        case .failed: return .bad
        }
    }

    /// One more sentence under the status when there is something the user can do about it.
    func hint(device: String) -> String? {
        switch self {
        case .off(.unsignedBuild):
            return "This build of Thuban Gym was made without a signing team, so it has no iCloud access. Set your team in Config/Signing.xcconfig and reinstall (ARCHITECTURE.md ▸ iCloud sync)."
        case .off(.notSignedIn):
            return "Sign in to iCloud on this \(device), with iCloud Drive on, then tap Sync now."
        case .off(.containerUnavailable):
            return "Turn on iCloud Drive for this \(device) (and for Thuban Gym in the iCloud app list), then tap Sync now."
        case .off(.localUnreadable):
            return "Restore a backup first; nothing is synced until this device's log can be read."
        case .off(.testHome):
            return "THUBAN_GYM_HOME points at a test folder, so the real iCloud copy is left alone."
        default:
            return nil
        }
    }
}
