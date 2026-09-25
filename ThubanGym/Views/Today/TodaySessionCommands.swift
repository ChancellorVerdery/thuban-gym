import SwiftUI
import ThubanGymCore

extension Notification.Name {
    /// Session menu → the focused Today card: check off its first open set.
    static let todayLogNextSet = Notification.Name("ThubanGym.todayLogNextSet")
    /// Session menu → the focused Today card: add a set row.
    static let todayAddSet = Notification.Name("ThubanGym.todayAddSet")
}

/// The "Session" menu: keyboard logging for quick one-handed use at the gym. Everything is disabled while no session
/// is running; the card actions also need Today on screen (they act on its focused card).
struct TodaySessionCommands: Commands {
    var app: AppModel

    var body: some Commands {
        CommandMenu("Session") {
            let running = app.activeSession != nil
            let onToday = running && app.section == .today && !app.todayVisibleItems().isEmpty
            Button("Log Next Set") { NotificationCenter.default.post(name: .todayLogNextSet, object: nil) }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(!onToday)
            Button("Add Set") { NotificationCenter.default.post(name: .todayAddSet, object: nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!onToday)
            Divider()
            Button(TodayRestClock.shared.isRunning ? "Stop Rest Timer" : "Start Rest Timer") {
                let clock = TodayRestClock.shared
                if clock.isRunning { clock.stop() } else { clock.start(seconds: app.restSeconds(for: app.activeSession?.workoutId)) }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!running)
            Divider()
            Button("Next Exercise") { app.todayMoveFocus(by: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!onToday)
            Button("Previous Exercise") { app.todayMoveFocus(by: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!onToday)
            Divider()
            Button("Finish Session") {
                app.finishSession()
                TodayRestClock.shared.stop()
            }
            .disabled(!running)
        }
    }
}
