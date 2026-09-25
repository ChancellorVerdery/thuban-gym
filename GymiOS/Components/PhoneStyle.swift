import SwiftUI
import ThubanGymCore
import UIKit

// The Thuban look on iPhone (IOS_BRIEF): serif display, SF body 17 / secondary 15 / footnote 13 / micro 12
// uppercase, inset cards on panel with hairlines, 44 pt targets, accent-filled primary buttons. Colours come ONLY
// from `ResolvedTheme` tokens (Shared/Theme/ThemeEnvironment.swift).

enum PhoneMetrics {
    static let gutter: CGFloat = 16
    static let cardRadius: CGFloat = 12
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 6
    static let primaryHeight: CGFloat = 56
    static let buttonHeight: CGFloat = 50
    static let rowHeight: CGFloat = 52
    static let hit: CGFloat = 44
}

enum PhoneFont {
    /// Serif display at `size`, scaled with Dynamic Type like `style`.
    static func serif(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .title1, weight: Font.Weight = .semibold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight, design: .serif)
    }
    /// Monospaced numbers at `size`, scaled like `style`.
    static func mono(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .footnote, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight, design: .monospaced)
    }
    static func sans(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics(forTextStyle: style).scaledValue(for: size), weight: weight)
    }
    /// UIKit serif (for `NumberField`).
    static func uiSerif(_ size: CGFloat, relativeTo style: UIFont.TextStyle = .title1, weight: UIFont.Weight = .semibold) -> UIFont {
        let scaled = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        let base = UIFont.systemFont(ofSize: scaled, weight: weight)
        return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: scaled) } ?? base
    }
    /// 12 pt semibold, set uppercase with tracking by `Eyebrow`.
    static var micro: Font { sans(12, relativeTo: .caption1, weight: .semibold) }
}

/// Micro eyebrow: "THURSDAY, SEP 24 · CYCLE DAY 2 OF 4".
struct Eyebrow: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var color: Color?

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(PhoneFont.micro)
            .kerning(0.96)
            .foregroundStyle(color ?? theme.inkDimColor)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Section header row above a card: eyebrow on the left, a quiet note or action on the right.
struct SectionHeading<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

/// An inset card: panel fill, hairline border, radius 12.
struct Card<Content: View>: View {
    @Environment(\.thubanTheme) private var theme
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
    }
}

/// 1 px separator inside a card, inset from the leading edge.
struct RowDivider: View {
    @Environment(\.thubanTheme) private var theme
    var inset: CGFloat = 16
    var body: some View {
        Rectangle().fill(theme.lineColor).frame(height: 1).padding(.leading, inset)
    }
}

struct Hairline: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View { Rectangle().fill(theme.lineColor).frame(height: 1) }
}

/// Soft chip ("Today", "L / R", "Extra", "Skip").
struct PhoneChip: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var kind: ChipKind
    var mono = false

    init(_ text: String, kind: ChipKind, mono: Bool = false) {
        self.text = text
        self.kind = kind
        self.mono = mono
    }

    var body: some View {
        let colors = kind.colors(theme)
        Text(text)
            .font(mono ? PhoneFont.mono(12, relativeTo: .caption1) : PhoneFont.sans(11.5, relativeTo: .caption2, weight: .semibold))
            .foregroundStyle(colors.text)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(minHeight: 20)
            .background(colors.fill, in: RoundedRectangle(cornerRadius: PhoneMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.chipRadius, style: .continuous)
                .strokeBorder(colors.border ?? .clear, lineWidth: 1))
            .fixedSize()
    }
}

// MARK: - Buttons

/// Full-width primary action: accent fill, dark ink text, radius 12.
struct PhonePrimaryStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = PhoneMetrics.primaryHeight

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PhoneFont.sans(17, weight: .semibold))
            .foregroundStyle(theme.onAccentColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? theme.accentDeepColor : theme.accentColor,
                        in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(Rectangle())
    }
}

/// Panel button with a hairline (±15 s, Finish workout).
struct PhoneSecondaryStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    var height: CGFloat = PhoneMetrics.buttonHeight
    var font: Font = PhoneFont.sans(17, weight: .semibold)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .foregroundStyle(theme.inkColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(configuration.isPressed ? theme.panel2Color : theme.panelColor,
                        in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// Text-only action in brass ("Finish", "Review and edit sets", "Undo").
struct PhoneTextStyle: ButtonStyle {
    @Environment(\.thubanTheme) private var theme
    var weight: Font.Weight = .semibold
    var size: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PhoneFont.sans(size, weight: weight))
            .foregroundStyle(theme.brassInkColor)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: PhoneMetrics.hit)
            .contentShape(Rectangle())
    }
}

/// A 44 × 44 icon button in brass with a VoiceOver label.
struct IconButton: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var label: String
    var size: CGFloat = 24
    var action: () -> Void

    init(_ icon: IconName, label: String, size: CGFloat = 24, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size)
                .foregroundStyle(theme.brassInkColor)
                .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The −/+ square buttons of the weight and reps cards.
struct StepButton: View {
    @Environment(\.thubanTheme) private var theme
    var icon: IconName
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: 22)
                .foregroundStyle(theme.inkColor)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Segmented control

/// The design's segmented picker: panel2 track, the selected segment on panel with a hairline.
struct PhoneSegmented<Value: Hashable>: View {
    @Environment(\.thubanTheme) private var theme
    var options: [(value: Value, label: String)]
    @Binding var selection: Value
    var accessibilityLabel: String
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(PhoneFont.sans(15, relativeTo: .subheadline, weight: selected ? .semibold : .medium))
                        .foregroundStyle(selected ? theme.inkColor : theme.inkDimColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: height - 4)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.panelColor)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(2)
        .frame(minHeight: height)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Screen chrome

extension View {
    /// Page ground and the navigation bar in theme colours.
    /// (The bars themselves are styled by `PhoneAppearance`: SwiftUI's toolbarBackground would replace the
    /// UIKit appearance and with it the serif large title.)
    func phoneScreen(_ theme: ResolvedTheme) -> some View {
        self.background(theme.bgColor.ignoresSafeArea())
    }

    /// A List drawn on the page ground with panel rows and hairline separators.
    func phoneList(_ theme: ResolvedTheme) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(theme.lineColor)
            .listSectionSpacing(20)
            .environment(\.defaultMinListRowHeight, PhoneMetrics.rowHeight)
    }
}

/// Presented content (sheets, the session cover) lives in its own hierarchy: give it the theme, the brass tint and
/// the chosen light / dark mode (so the keyboard and the status bar match too).
struct PhoneChrome: ViewModifier {
    @Environment(AppModel.self) private var app
    func body(content: Content) -> some View {
        content
            .environment(\.thubanTheme, app.theme)
            .tint(app.theme.brassInkColor)
            .preferredColorScheme(app.preferredColorScheme)
    }
}

extension View {
    func phoneChrome() -> some View { modifier(PhoneChrome()) }
}

/// A tab's serif page title, drawn in the content under the toolbar row (board Plan / Workouts / Progress). The
/// navigation bar keeps the title only for the back button of pushed screens.
struct PageTitle: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(PhoneFont.serif(34, relativeTo: .largeTitle))
            .kerning(-0.3)
            .foregroundStyle(theme.inkColor)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Title for the back button and VoiceOver, with nothing drawn in the bar itself (the page draws `PageTitle`).
    func pageNavigationTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
    }
}

/// Chevron at the end of a tappable row.
struct RowChevron: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        Icon(.chevronRight, size: 16).foregroundStyle(theme.inkFaintColor)
    }
}

/// Small footnote under a card.
struct CardFootnote: View {
    @Environment(\.thubanTheme) private var theme
    var text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(theme.inkDimColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
            .padding(.top, 8)
    }
}

// MARK: - UIKit colour helpers

extension UIColor {
    convenience init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: text).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}
