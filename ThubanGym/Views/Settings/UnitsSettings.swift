import SwiftUI
import ThubanGymCore

/// Settings → Units. OWNER: Engineer C (Progress + Settings/Import).
///
/// TODO: kg / lb SegmentedPicker bound to app.unit via app.setUnit(_:), the '140 lb = 63.5 kg' example line, and the note that weights are stored in kg so switching never rounds history.
struct UnitsSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Units", caption: "This pane is being built. See ARCHITECTURE.md → Settings.")
    }
}
