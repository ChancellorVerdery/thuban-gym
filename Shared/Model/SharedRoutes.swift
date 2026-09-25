import Foundation
import ThubanGymCore

// Types the Mac and iOS apps share (their navigation enums stay per platform).

/// SwiftUI's `ColorScheme` shadows the core type inside the app targets.
typealias ThubanScheme = ThubanGymCore.ColorScheme

/// Progress range picker (3M / 6M / All on the Mac).
enum ProgressRange: String, CaseIterable, Hashable, Identifiable {
    case threeMonths = "3M", sixMonths = "6M", all = "All"

    var id: String { rawValue }

    /// First day of the range (nil = from the first logged day).
    func start(today: DayKey) -> DayKey? {
        switch self {
        case .threeMonths: return today.adding(days: -91)
        case .sixMonths: return today.adding(days: -182)
        case .all: return nil
        }
    }
}
