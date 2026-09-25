import SwiftUI
import ThubanGymCore

/// Plan section. OWNER: Engineer B (Plan + Workouts).
///
/// TODO: Engineer B (Plan + Workouts). Build Plan.dc.html: header (Plan · cycle of n, order, the pointer rule), Plan type Weekly/Cycle, the 14-day strip (app.planStrip) with its legend, Cycle order (drag to reorder → app.setCycle), Overrides · upcoming (Undo → app.clearOverride), Extras · today, the saved weekly plan.
/// Read state and call mutations only through `AppModel` (see ARCHITECTURE.md). Colours only from `theme`.
struct PlanView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SectionPlaceholder(icon: .plan, title: "Plan", todo: "Plan is being built. See ARCHITECTURE.md → Plan.")
    }
}
