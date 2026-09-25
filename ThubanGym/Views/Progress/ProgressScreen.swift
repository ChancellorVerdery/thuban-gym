import SwiftUI
import ThubanGymCore

/// Progress section. OWNER: Engineer C (Progress + Settings/Import).
///
/// TODO: Engineer C (Progress + Settings/Import). Build Progress.dc.html: 'Stronger by x%' header, Strength score / Sessions / Avg session / On plan tiles, the weekly strength-score chart with the 100 baseline, Recent sessions table, By exercise list (row click → app.presentedExerciseId = id).
/// Read state and call mutations only through `AppModel` (see ARCHITECTURE.md). Colours only from `theme`.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SectionPlaceholder(icon: .progress, title: "Progress", todo: "Progress is being built. See ARCHITECTURE.md → Progress.")
    }
}
