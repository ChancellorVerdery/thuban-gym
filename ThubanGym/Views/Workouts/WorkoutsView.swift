import SwiftUI
import ThubanGymCore

/// Workouts section. OWNER: Engineer B (Plan + Workouts).
///
/// TODO: Engineer B (Plan + Workouts). Build Workouts.dc.html: workout list (cycle position, Rest / Flex chips), the editor (Day type Training/Rest/Flex, exercise table with Target, L/R, Bodyweight, Current e1RM, Add exercise / Copy from another workout), the side panel (exercise notes, Rest timer, Used in).
/// Read state and call mutations only through `AppModel` (see ARCHITECTURE.md). Colours only from `theme`.
struct WorkoutsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SectionPlaceholder(icon: .workouts, title: "Workouts", todo: "Workouts is being built. See ARCHITECTURE.md → Workouts.")
    }
}
