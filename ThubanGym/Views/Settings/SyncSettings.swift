import SwiftUI
import ThubanGymCore

/// Settings ▸ Data & storage ▸ iCloud Sync: the switch, the status line ("Up to date · last synced 9:41 AM",
/// "Syncing…", "Off: iCloud needs a signed build") and "Sync now".
struct SyncSettingsGroup: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let status = app.syncStatus
        SettingsGroup("iCloud Sync", caption: "This Mac and your iPhone share one log through a hidden folder in your own iCloud. Changes merge item by item: a set logged on either device is never lost, and a deletion stays deleted.") {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCloud Sync").font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
                        Text("Uses the iCloud account signed in on this Mac.")
                            .font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                    }
                    Spacer(minLength: 12)
                    ThubanToggle(isOn: Binding(get: { app.iCloudSyncEnabled }, set: { app.iCloudSyncEnabled = $0 }), label: "iCloud Sync")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                HStack(spacing: 10) {
                    Circle().fill(dotColor(status.tone)).frame(width: 8, height: 8)
                    Text(status.text())
                        .font(ThubanFont.body(14))
                        .foregroundStyle(status.tone == .bad ? theme.negTextColor : theme.inkColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Sync status: \(status.text())")
                    Spacer(minLength: 8)
                    Button("Sync now") { app.syncNow() }
                        .buttonStyle(SecondaryButtonStyle(height: 30))
                        .disabled(!app.canSyncNow)
                        .accessibilityHint("Merges this Mac's log with the copy in iCloud")
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .thubanHairline(.top, color: theme.lineColor)

                if let hint = status.hint(device: "Mac") {
                    Text(hint)
                        .font(ThubanFont.small)
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .thubanHairline(.top, color: theme.lineColor)
                }
            }
            .thubanPanel(padding: 0)
        }
    }

    private func dotColor(_ tone: SyncTone) -> Color {
        switch tone {
        case .good: return theme.posColor
        case .busy: return theme.signalColor
        case .idle: return theme.line2Color
        case .bad: return theme.negColor
        }
    }
}
