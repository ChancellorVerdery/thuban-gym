import Foundation
import ThubanGymCore

/// One extra smoke screenshot: put the app in a state, capture a window, undo the state.
struct SmokeScene {
    enum Window {
        /// The main window's content.
        case main
        /// The sheet attached to the main window (e.g. the Exercise history sheet).
        case sheet
        /// The Settings window (open it in `prepare` with `app.openSettings(pane)`).
        case settings
    }

    var name: String
    var window: Window = .main
    /// Seconds to wait after `prepare` before capturing.
    var settle: Double = 1.2
    var prepare: @MainActor (AppModel) async -> Void
    var cleanup: @MainActor (AppModel) async -> Void = { _ in }

    init(name: String, window: Window = .main, settle: Double = 1.2,
         prepare: @escaping @MainActor (AppModel) async -> Void,
         cleanup: @escaping @MainActor (AppModel) async -> Void = { _ in }) {
        self.name = name
        self.window = window
        self.settle = settle
        self.prepare = prepare
        self.cleanup = cleanup
    }
}

/// The scene registry. Each area owns ONE static list in its own file (Views/<Area>/<Area>SmokeScenes.swift), so
/// parallel branches never edit the same line. The harness runs them in this order after the standard walk.
enum SmokeScenes {
    static var all: [SmokeScene] { today + exercise + plan + workouts + progress + settings }
}
