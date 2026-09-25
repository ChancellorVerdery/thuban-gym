import SwiftUI
import ThubanGymCore

/// Settings → Units: kg / lb for display. Storage stays kg, so switching never rounds history.
/// OWNER: Engineer C (Progress + Settings/Import).
struct UnitsSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Units",
                               caption: "Display only. Weights are stored in kg, so switching never rounds your history.")
            SettingsGroup("Weight", caption: "Every weight, e1RM and next target on every screen follows this.") {
                UnitsPicker()
            }
            SettingsGroup("What changes", caption: nil) {
                VStack(spacing: 0) {
                    exampleRow("Typing a set", value: app.unit == .kg ? "62.5 → stored 62.5 kg" : "140 → stored 63.503 kg")
                    exampleRow("Next target step", value: app.unit == .kg ? "add 2.5 kg" : "add 5 lb")
                    if let heaviest {
                        exampleRow("Your heaviest set", value: heaviest)
                    }
                }
                .thubanPanel(padding: 0)
            }
        }
    }

    private func exampleRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(ThubanFont.body(14, weight: .semibold)).foregroundStyle(theme.inkColor)
            Spacer(minLength: 12)
            Text(value).font(ThubanFont.mono(13)).foregroundStyle(theme.inkDimColor)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// "Back Squat 225 lb × 5 (102.058 kg stored)".
    private var heaviest: String? {
        var best: (SetEntry, String)?
        for log in app.data.logs {
            for set in log.sets where set.weight != nil && (best.map { set.weight! > $0.0.weight! } ?? true) {
                best = (set, log.exerciseId)
            }
        }
        guard let (set, id) = best, let kg = set.weight, let name = app.exercise(id)?.name else { return nil }
        return "\(name) \(app.weightWithUnit(kg)) × \(set.reps) (\(GymFormat.number(kg, decimals: 3)) kg stored)"
    }
}

/// kg / lb segmented control with the "140 lb = 63.5 kg" example line (design: Import artboard, Units).
struct UnitsPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SegmentedPicker(
                selection: Binding(get: { app.unit }, set: { app.setUnit($0) }),
                options: [SegmentOption(WeightUnit.kg, "kg"), SegmentOption(WeightUnit.lbs, "lb")],
                segmentHeight: 28
            )
            .fixedSize()
            .accessibilityLabel("Weight unit")
            Text(example)
                .font(ThubanFont.mono(13))
                .foregroundStyle(theme.inkFaintColor)
        }
    }

    private var example: String {
        app.unit == .lbs
            ? "140 lb = \(GymFormat.number(WeightUnit.lbs.toKilograms(140))) kg"
            : "100 kg = \(GymFormat.number(WeightUnit.lbs.fromKilograms(100))) lb"
    }
}

/// The eight Thuban schemes as selectable cards (shared by Import and Appearance).
struct SchemeGrid: View {
    @Environment(AppModel.self) private var app
    var columns: Int = 4
    var spacing: CGFloat = 12

    var body: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
        LazyVGrid(columns: grid, spacing: spacing) {
            ForEach(SchemeCardModel.cards(for: app.themeSelection).filter { $0.id != ThubanScheme.customId }) { card in
                SchemeCard(card: card, isSelected: card.id == app.themeSelection.schemeId) {
                    app.selectScheme(id: card.id)
                }
            }
        }
    }
}
