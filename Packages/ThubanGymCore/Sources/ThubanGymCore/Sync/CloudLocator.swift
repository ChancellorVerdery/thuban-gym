import Foundation

/// Why sync is off (shown after "Off:" in Settings).
public enum CloudOffReason: String, Equatable, Sendable {
    /// The user switched iCloud Sync off.
    case turnedOff
    /// The build carries no iCloud entitlement (ad-hoc Mac build, unsigned simulator build).
    case unsignedBuild
    /// No iCloud account on this device.
    case notSignedIn
    /// Signed in, but the container cannot be reached (iCloud Drive off, or the app is not allowed to use it).
    case containerUnavailable
    /// `THUBAN_GYM_HOME` points at a test / smoke folder: never mix that data into the real iCloud.
    case testHome
    /// This device's gym.json exists but cannot be read; nothing is synced until it is fixed or restored.
    case localUnreadable

    public var message: String {
        switch self {
        case .turnedOff: return "turned off"
        case .unsignedBuild: return "iCloud needs a signed build"
        case .notSignedIn: return "iCloud Drive is off or you’re not signed in to iCloud"
        case .containerUnavailable: return "iCloud Drive is not available to Thuban Gym"
        case .testHome: return "test data folder in use"
        case .localUnreadable: return "this device's gym.json could not be read"
        }
    }
}

public enum CloudAvailability: Equatable, Sendable {
    /// The shared file's URL. `ubiquitous` is false for a plain folder standing in for iCloud.
    case available(URL, ubiquitous: Bool)
    case unavailable(CloudOffReason)
}

/// Finds the shared file: `<iCloud container iCloud.org.thuban.gym>/Documents/gym.json` (a hidden container:
/// `NSUbiquitousContainerIsDocumentScopePublic` is false, so it never shows in the Files app / Finder).
///
/// Order of checks: `THUBAN_GYM_CLOUD_DIR` (a plain folder used as the container; smoke runs and two-instance
/// testing) → `THUBAN_GYM_HOME` set (test data: off) → the build's `ThubanICloud` Info.plist flag (YES only when
/// built with a team and the iCloud entitlements) → an iCloud account (`ubiquityIdentityToken`) → the container.
/// Call off the main thread: resolving the container can block.
public enum CloudLocator {
    public static let containerIdentifier = "iCloud.org.thuban.gym"
    public static let cloudDirVariable = "THUBAN_GYM_CLOUD_DIR"
    public static let infoKey = "ThubanICloud"
    public static let fileName = "gym.json"

    public static func fileURL(inContainer root: URL) -> URL {
        root.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(fileName)
    }

    /// True when the running build was signed with the iCloud entitlements (see project.yml / Config/*.xcconfig).
    public static func buildHasICloud(info: [String: Any]? = Bundle.main.infoDictionary) -> Bool {
        let value = info?[infoKey]
        if let flag = value as? String { return flag.uppercased() == "YES" }
        if let flag = value as? Bool { return flag }
        return false
    }

    public static func availability(environment: [String: String] = ProcessInfo.processInfo.environment,
                                    info: [String: Any]? = Bundle.main.infoDictionary,
                                    fileManager: FileManager = .default) -> CloudAvailability {
        if let raw = environment[cloudDirVariable]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let root = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath, isDirectory: true)
            return .available(fileURL(inContainer: root), ubiquitous: false)
        }
        if let home = environment[AppPaths.homeVariable]?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
            return .unavailable(.testHome)
        }
        guard buildHasICloud(info: info) else { return .unavailable(.unsignedBuild) }
        guard fileManager.ubiquityIdentityToken != nil else { return .unavailable(.notSignedIn) }
        guard let container = fileManager.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            return .unavailable(.containerUnavailable)
        }
        return .available(fileURL(inContainer: container), ubiquitous: true)
    }
}
