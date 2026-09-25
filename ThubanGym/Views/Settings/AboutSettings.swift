import SwiftUI
import ThubanGymCore

/// Settings → About: the mark, version, and what the app does with your data. OWNER: Engineer C.
struct AboutSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .center, spacing: 20) {
                AppArtView(size: 72, theme: theme)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thuban Gym")
                        .font(ThubanFont.display(32))
                        .foregroundStyle(theme.inkColor)
                        .accessibilityAddTraits(.isHeader)
                    Text("Training log, plan and progress. A sibling of Thuban Study and Thuban Canvas.")
                        .font(ThubanFont.body(14))
                        .foregroundStyle(theme.inkDimColor)
                    Text("Version \(version)")
                        .font(ThubanFont.mono(12.5))
                        .foregroundStyle(theme.inkFaintColor)
                        .padding(.top, 2)
                }
            }

            SettingsGroup("How it works") {
                VStack(spacing: 0) {
                    fact("Local", "Everything lives on this Mac in one file, with daily backups. Nothing is synced.")
                    fact("Units", "Weights are stored in kilograms. The unit setting only changes how they are shown.")
                    fact("Scores", "e1RM is Epley: weight × (1 + reps ÷ 30); bodyweight moves score by reps. An exercise's index is 100 at its first session. The strength score is the mean of every index.")
                    fact("Atlas", "Read once, over ssh, with a read-only query. Atlas is never written to.")
                }
                .thubanPanel(padding: 0)
            }
        }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    private func fact(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(ThubanFont.body(14, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 70, alignment: .leading)
            Text(text)
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkDimColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
