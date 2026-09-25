import SwiftUI
import ThubanGymCore

/// Settings window (design: Import.dc.html): 280 pt nav on the left (serif "Settings", one row per pane, the
/// "Everything lives on this Mac" note at the bottom), the pane on the right. Each pane lives in its own file.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var pane: SettingsPane = .importAtlas

    var body: some View {
        let theme = app.theme
        HStack(spacing: 0) {
            SettingsNav(selection: $pane)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch pane {
                    case .importAtlas: ImportSettings()
                    case .units: UnitsSettings()
                    case .appearance: AppearanceSettings()
                    case .plan: PlanSettings()
                    case .data: DataSettings()
                    case .about: AboutSettings()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 26)
                .padding(.bottom, 24)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .environment(\.thubanTextScale, app.preferences.textSize.scale)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .onAppear(perform: consumeRequestedPane)
        .onChange(of: app.settingsRequest) { _, _ in consumeRequestedPane() }
    }

    private func consumeRequestedPane() {
        if let requested = app.settingsPane {
            pane = requested
            app.settingsPane = nil
        }
    }
}

private struct SettingsNav: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(ThubanFont.display(26))
                .foregroundStyle(theme.inkColor)
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            ForEach(SettingsPane.allCases) { pane in
                SettingsNavRow(pane: pane, isSelected: pane == selection) { selection = pane }
            }
            Spacer(minLength: 16)
            Text("Everything lives on this Mac. Atlas is read once and never written to.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.inkFaintColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 26)
        .frame(width: 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
    }
}

private struct SettingsNavRow: View {
    @Environment(\.thubanTheme) private var theme
    var pane: SettingsPane
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(pane.icon, size: 16)
                    .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkDimColor)
                Text(pane.rawValue)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? theme.inkColor : theme.inkDimColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(isSelected ? theme.panel2Color : (hovering ? theme.panel2Color.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(isSelected ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
