import SwiftUI
import ThubanGymCore

/// Settings → Data & storage. OWNER: Engineer C (Progress + Settings/Import).
///
/// TODO: Data folder (app.dataFolder, Reveal → app.revealDataFolder()), backups list (app.backups(), Restore → app.restoreBackup(url) after confirming), Export… (app.exportData(to:)), counts of what is stored.
struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsPaneHeader(eyebrow: nil, title: "Data & storage", caption: "This pane is being built. See ARCHITECTURE.md → Settings.")
    }
}
