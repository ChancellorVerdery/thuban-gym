import Foundation
import ThubanGymCore

/// SwiftUI's `ColorScheme` shadows the core type inside the app target.
typealias ThubanScheme = ThubanGymCore.ColorScheme

/// The four sections in the section bar, in order.
enum AppSection: String, CaseIterable, Hashable, Codable, Identifiable {
    case today, plan, workouts, progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .workouts: return "Workouts"
        case .progress: return "Progress"
        }
    }

    var icon: IconName {
        switch self {
        case .today: return .today
        case .plan: return .plan
        case .workouts: return .workouts
        case .progress: return .progress
        }
    }

    /// ⌘1 … ⌘4
    var shortcut: Character { Character(String((AppSection.allCases.firstIndex(of: self) ?? 0) + 1)) }
}

/// Settings window panes, in nav order (design: Import and settings artboard).
enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case importAtlas = "Import from Atlas"
    case units = "Units"
    case appearance = "Appearance"
    case plan = "Plan"
    case data = "Data & storage"
    case about = "About"

    var id: String { rawValue }

    var icon: IconName {
        switch self {
        case .importAtlas: return .download
        case .units: return .today
        case .appearance: return .settings
        case .plan: return .plan
        case .data: return .file
        case .about: return .history
        }
    }
}

/// Progress range picker (3M / 6M / All).
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
