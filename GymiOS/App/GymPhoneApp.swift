import SwiftUI
import ThubanGymCore

@main
struct GymPhoneApp: App {
    @State private var app: AppModel

    init() {
        PhoneSmoke.prepareEnvironment()
        let model = AppModel()
        _app = State(initialValue: model)
        PhoneAppearance.update(model.themeSelection)
        PhoneAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            PhoneRoot()
                .environment(app)
        }
    }
}

/// Picks the iPhone tabs or the iPad split view, applies the theme, and hosts the Settings sheet and the session.
struct PhoneRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        Group {
            if sizeClass == .regular {
                PadRoot()
            } else {
                PhoneTabs()
            }
        }
        // Fonts are scaled when built (PhoneFont), so a Dynamic Type change rebuilds the tree.
        .id(typeSize)
        .phoneChrome()
        .sheet(isPresented: $app.showSettings) {
            SettingsSheet()
                .phoneChrome()
        }
        .onChange(of: colorScheme, initial: true) { _, scheme in
            if app.themeSelection.mode == .auto { app.setSystemIsDark(scheme == .dark) }
        }
        .onChange(of: app.themeSelection, initial: true) { _, selection in
            PhoneAppearance.update(selection)
            PhoneAppearance.refreshExistingBars()
            if selection.mode == .auto {
                app.setSystemIsDark(UIScreen.main.traitCollection.userInterfaceStyle == .dark)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { app.refreshDay(); app.restTick() }
        }
        .task {
            app.load()
            PhoneSmoke.startIfEnabled(app: app)
        }
    }
}

/// iPhone: four tabs, each its own navigation stack; the session logger covers everything.
struct PhoneTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack(path: $app.todayPath) {
                TodayScreen().phoneDestinations()
            }
            .tabItem { Label { Text("Today") } icon: { Image(uiImage: TabIcon.image(.kettlebell)) } }
            .tag(PhoneTab.today)

            NavigationStack(path: $app.planPath) {
                PlanScreen().phoneDestinations()
            }
            .tabItem { Label { Text("Plan") } icon: { Image(uiImage: TabIcon.image(.calendar)) } }
            .tag(PhoneTab.plan)

            NavigationStack(path: $app.workoutsPath) {
                WorkoutsScreen().phoneDestinations()
            }
            .tabItem { Label { Text("Workouts") } icon: { Image(uiImage: TabIcon.image(.today)) } }
            .tag(PhoneTab.workouts)

            NavigationStack(path: $app.progressPath) {
                ProgressScreen().phoneDestinations()
            }
            .tabItem { Label { Text("Progress") } icon: { Image(uiImage: TabIcon.image(.progress)) } }
            .tag(PhoneTab.progress)
        }
        .fullScreenCover(isPresented: $app.sessionPresented) {
            // In a stack so the number pad's Done bar (a keyboard toolbar) has a home.
            NavigationStack {
                SessionCover()
                    .toolbar(.hidden, for: .navigationBar)
            }
            .phoneChrome()
        }
    }
}

extension View {
    /// Pushed screens shared by every tab.
    func phoneDestinations() -> some View {
        navigationDestination(for: PhoneRoute.self) { route in
            switch route {
            case .exercise(let id): ExerciseHistoryScreen(exerciseId: id)
            case .workout(let id): WorkoutEditorScreen(workoutId: id)
            }
        }
    }
}
