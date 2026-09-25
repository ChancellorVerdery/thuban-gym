import SwiftUI
import ThubanGymCore

// Small building blocks shared by the Plan and Workouts screens (Engineer B). Kept here, not in Components/, so the
// three UI branches never touch the same file.

/// A panel card that clips its rows (the artboards' `section` with hairline rows inside).
struct PlanCard<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(theme.panelColor)
            .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
                    .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline)
            )
    }
}

/// The artboards' small uppercase caption above a control ("PLAN TYPE", "DAY TYPE"): 12 pt, faint.
struct PlanControlCaption: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(ThubanFont.micro)
            .kerning(0.84)
            .foregroundStyle(theme.inkFaintColor)
    }
}

/// A 38 × 22 switch (the Workouts table's L / R and Bodyweight columns): `pos` when on, `line2` when off.
struct PlanSwitch: View {
    @Environment(\.thubanTheme) private var theme
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.12)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.posColor : theme.line2Color)
                Circle()
                    .fill(theme.isDark ? theme.inkColor : theme.panelColor)
                    .frame(width: 18, height: 18)
                    .padding(2)
            }
            .frame(width: 38, height: 22)
            .contentShape(Rectangle())
            .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .help(label)
    }
}

/// A text field in the design's control style: `panel` fill, `line2` border, radius 8. `quiet` hides the chrome
/// until hover / focus (the exercise name cells).
struct PlanFieldChrome: ViewModifier {
    @Environment(\.thubanTheme) private var theme
    var height: CGFloat = 32
    var mono = false
    var quiet = false
    var focused = false
    var alignment: TextAlignment = .leading
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    @State private var hovering = false

    func body(content: Content) -> some View {
        let showChrome = !quiet || hovering || focused
        content
            .textFieldStyle(.plain)
            .font(mono ? ThubanFont.mono(size, weight: weight) : ThubanFont.body(size, weight: weight))
            .multilineTextAlignment(alignment)
            .foregroundStyle(theme.inkColor)
            .padding(.horizontal, 10)
            .frame(height: height)
            .background(showChrome ? theme.panelColor : .clear, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(focused ? theme.accentColor : (showChrome ? theme.line2Color : .clear), lineWidth: ThubanMetrics.hairline)
            )
            .onHover { hovering = $0 }
    }
}

extension View {
    func planField(height: CGFloat = 32, mono: Bool = false, quiet: Bool = false, focused: Bool = false,
                   alignment: TextAlignment = .leading, size: CGFloat = 14, weight: Font.Weight = .regular) -> some View {
        modifier(PlanFieldChrome(height: height, mono: mono, quiet: quiet, focused: focused, alignment: alignment, size: size, weight: weight))
    }
}

/// A 28 pt text-only ghost button for row actions ("Undo", "Make next").
struct PlanRowButton: View {
    var title: String
    var accessibility: String?
    var tinted = false
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(GhostButtonStyle(height: 28, tinted: tinted, horizontalPadding: 10))
            .font(.system(size: 13, weight: .semibold))
            .accessibilityLabel(accessibility ?? title)
    }
}

/// The section bar's ghost button with a tone (Workouts → "Delete" is drawn in `negText`).
struct PlanToneToolbarButton: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var label: String
    var icon: IconName
    var destructive = false
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(icon, size: 15)
                Text(label).lineLimit(1)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(destructive ? theme.negTextColor : theme.inkDimColor)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(hovering ? theme.panel2Color : .clear, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(label)
    }
}

/// A day's name in the strip and lists: "Fri Sep 25".
extension DayKey {
    var planShort: String { GymFormat.shortDay(self) }
}
