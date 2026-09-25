import SwiftUI
import ThubanGymCore

/// Today section. OWNER: Engineer A (Today + Exercise sheet).
///
/// TODO: Engineer A (Today + Exercise sheet). Build the Main.dc.html / TodayDark.dc.html artboards: eyebrow (date · Cycle day n of m), serif workout title, summary line, sets-logged progress, the exercise list with set tables (Previous / Weight / Reps / e1RM, Add set, rest timer, L/R rows for unilateral, BW for bodyweight, extras marked 'Extra · from <workout>'), and the right-hand Session / This session / Cycle panels. First run (app.isFirstRun): offer the Atlas import (app.openSettings(.importAtlas)).
/// Read state and call mutations only through `AppModel` (see ARCHITECTURE.md). Colours only from `theme`.
struct TodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SectionPlaceholder(icon: .today, title: "Today", todo: "Today is being built. See ARCHITECTURE.md → Today.")
    }
}
