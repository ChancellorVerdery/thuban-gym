import SwiftUI
import ThubanGymCore

@main
struct ThubanGymApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var appModel: AppModel

    init() {
        // Must run before anything touches NSApplication (see SharedTheme): an icon-only launch exits here.
        SharedTheme.refreshIconAndExitIfRequested { AppIconRenderer.render(theme: $0) }
        _appModel = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Thuban Gym") {
            ShellView()
                .environment(appModel)
                .frame(minWidth: 1100, minHeight: 700)
                .task { await appModel.load() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appSettings) {
                SettingsCommandButton().environment(appModel)
            }
            CommandMenu("Go") {
                ForEach(AppSection.allCases) { section in
                    Button(section.label) { appModel.section = section }
                        .keyboardShortcut(KeyEquivalent(section.shortcut), modifiers: .command)
                }
            }
            TodaySessionCommands(app: appModel)
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(appModel)
                .frame(minWidth: 900, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 760)
    }
}

/// "Settings… ⌘," in the App menu; opens the Settings window scene.
private struct SettingsCommandButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") { openWindow(id: "settings") }
            .keyboardShortcut(",", modifiers: .command)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
