import SwiftUI
import ThubanGymCore

/// Settings → About. OWNER: Engineer C (may restyle).
struct AboutSettings: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPaneHeader(eyebrow: nil, title: "Thuban Gym", caption: "Training log, plan and progress. A sibling of Thuban Study and Thuban Canvas.")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    AppArtView(size: 28, theme: theme)
                    Text("Everything lives on this Mac in one file. Weights are stored in kilograms; the unit setting only changes how they are shown. Atlas is read once, over ssh, with a read-only query, and never written to.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Hairline()
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkFaintColor)
            }
            .padding(14)
            .thubanPanel(padding: 0)
        }
    }
}
