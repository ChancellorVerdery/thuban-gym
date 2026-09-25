import SwiftUI
import ThubanGymCore

/// Appearance pane: Mode (Auto / Light / Dark), the eight Thuban schemes (design: "The eight Thuban schemes.
/// Mode follows macOS."), text size, and a live preview. Working now; Engineer C may restyle it to the artboard.
struct AppearanceSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Appearance", caption: "Colours only. Every scheme uses the same Thuban layout.")

            SettingsGroup("Mode", caption: modeCaption) {
                SegmentedPicker(
                    selection: Binding(get: { app.themeSelection.mode }, set: { app.setAppearanceMode($0) }),
                    options: AppearanceMode.allCases.map { SegmentOption($0, $0.label) }
                )
            }

            SettingsGroup("Scheme", caption: "The eight Thuban schemes. Brass is the default.") {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(SchemeCardModel.cards(for: app.themeSelection).filter { $0.id != ThubanScheme.customId }) { card in
                        SchemeCard(card: card, isSelected: card.id == app.themeSelection.schemeId) {
                            app.selectScheme(id: card.id)
                        }
                    }
                }
            }

            SettingsGroup("Text size", caption: "Scales body text on every screen.") {
                SegmentedPicker(
                    selection: Binding(get: { app.preferences.textSize }, set: { app.preferences.textSize = $0 }),
                    options: TextSize.allCases.map { SegmentOption($0, $0.label) }
                )
            }

            SettingsGroup("Preview", caption: "How the selected scheme reads in \(theme.isDark ? "dark" : "light") mode.") {
                ThemePreviewCard()
            }
        }
    }

    private var modeCaption: String {
        switch app.themeSelection.mode {
        case .auto: return "Follows macOS — currently \(app.systemIsDark ? "dark" : "light")."
        case .light: return "Always light, whatever macOS is set to."
        case .dark: return "Always dark, whatever macOS is set to."
        }
    }
}

// MARK: - Scheme card

/// Label + four color dots + a split light|dark ground swatch (each half with a small panel rectangle inside).
/// Selected: accent ring and tint. The default scheme carries a "Default" tag.
struct SchemeCard: View {
    @Environment(\.thubanTheme) private var theme
    var card: SchemeCardModel
    var isSelected: Bool
    var action: () -> Void
    @State private var hovering = false

    private var isCustom: Bool { card.id == ThubanScheme.customId }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(card.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? theme.brassInkColor : theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if card.isDefault {
                        Chip("Default", kind: isSelected ? .accent : .neutral)
                    } else if isCustom && isSelected {
                        Chip("In use", kind: .accent)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(Array(card.dots.enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                    }
                    Spacer(minLength: 0)
                    if isCustom {
                        Text("Edit")
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.brassInkColor)
                    }
                }
                SplitGroundSwatch(lightBg: card.lightBg, lightPanel: card.lightPanel, darkBg: card.darkBg, darkPanel: card.darkPanel)
                    .frame(height: 36)
            }
            .padding(12)
            .background(
                isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : theme.panelColor),
                in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                    .strokeBorder(isSelected ? theme.accentColor : theme.lineColor, lineWidth: isSelected ? 1.5 : ThubanMetrics.hairline)
            )
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(isCustom ? "Custom scheme, edit" : "\(card.label) scheme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Light ground on the left, dark ground on the right, each with a small panel rectangle inside.
struct SplitGroundSwatch: View {
    @Environment(\.thubanTheme) private var theme
    var lightBg: String
    var lightPanel: String
    var darkBg: String
    var darkPanel: String

    var body: some View {
        HStack(spacing: 0) {
            half(bg: lightBg, panel: lightPanel)
            half(bg: darkBg, panel: darkPanel)
        }
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline)
        )
        .accessibilityHidden(true)
    }

    private func half(bg: String, panel: String) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(hex: bg)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: panel))
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview card

/// A mini section bar, primary / secondary buttons, status chips and a progress line in the selected scheme.
struct ThemePreviewCard: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                AppArtView(size: 16, theme: theme)
                Text("Thuban Gym").font(ThubanFont.display(14)).foregroundStyle(theme.inkColor)
                Spacer(minLength: 0)
                Chip("Pull in progress · 31:12", kind: .neutral, dot: true)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .background(theme.panelColor)
            .thubanHairline(.bottom, color: theme.lineColor)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button("Finish session") {}.buttonStyle(.thubanPrimary)
                    Button("Add exercise") {}.buttonStyle(.thubanSecondary)
                    Spacer(minLength: 0)
                    Chip("Done", kind: .pos, dot: true)
                    Chip("Skipped", kind: .neg, dot: true)
                    Chip("Swapped", kind: .signal, dot: true)
                }
                .allowsHitTesting(false)
                HStack(spacing: 18) {
                    Text("177.3 lb e1RM").font(ThubanFont.display(18)).foregroundStyle(theme.inkColor)
                    Text("+6.3 vs last").font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.posTextColor)
                    Spacer(minLength: 0)
                    Text("6 of 20 sets logged").font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
                }
                ProgressBar(value: 0.3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Theme preview")
    }
}
