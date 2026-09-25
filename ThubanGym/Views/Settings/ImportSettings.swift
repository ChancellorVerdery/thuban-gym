import SwiftUI
import ThubanGymCore

/// Settings → Import from Atlas. OWNER: Engineer C (Progress + Settings/Import).
///
/// TODO: Build the Import.dc.html pane: first-run header, the import card (phase from app.importPhase: fetching progress + Cancel, preview counts table — Workouts, Exercises, Plan, Sessions, Sets, Overrides and extras — with Apply / Cancel, done + backup path, failed + message), host and email fields bound to app.preferences.atlasHost / atlasEmail, 'Import from a file…' (app.chooseImportFile()), the command shown read-only (app.atlasImporter.commandDescription). Re-import asks for confirmation when preview.replacesExisting.
struct ImportSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Import from Atlas", caption: "This pane is being built. See ARCHITECTURE.md → Settings.")
    }
}
