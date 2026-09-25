import SwiftUI
import ThubanGymCore

/// Settings → Plan. OWNER: Engineer C (Progress + Settings/Import).
///
/// TODO: Plan type (app.setPlanType), default session length (app.updateSettings { $0.defaultDuration = … }), default rest timer (restSeconds), gym address and opening hours per weekday (app.settings.hours).
struct PlanSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Plan", caption: "This pane is being built. See ARCHITECTURE.md → Settings.")
    }
}
