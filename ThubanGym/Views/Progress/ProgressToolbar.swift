import SwiftUI
import ThubanGymCore

/// Progress's actions on the right of the section bar (design: `3M / 6M / All` segmented + ghost "Units: lb").
/// The range is shared with the view through `app.progressRange`; the units button toggles kg / lb (display only).
struct ProgressToolbar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 6) {
            SegmentedPicker(
                selection: Binding(get: { app.progressRange }, set: { app.progressRange = $0 }),
                options: ProgressRange.allCases.map { SegmentOption($0, $0.rawValue) },
                segmentHeight: SegmentedPickerHeight.toolbar + 2
            )
            .accessibilityLabel("Range")
            Button {
                app.setUnit(app.unit == .kg ? .lbs : .kg)
            } label: {
                HStack(spacing: 7) {
                    SlidersGlyph().frame(width: 15, height: 15)
                    Text("Units: \(app.unit.label)").lineLimit(1)
                }
            }
            .buttonStyle(GhostButtonStyle(height: 32, horizontalPadding: 14))
            .accessibilityLabel("Units: \(app.unit.label). Switch to \(app.unit == .kg ? "lb" : "kg")")
            .help("Show weights in \(app.unit == .kg ? "pounds" : "kilograms"). Stored weights never change.")
        }
    }
}

/// The design's "units" line icon (two sliders), drawn from its 24-unit path.
struct SlidersGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height) / 24
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var path = Path()
            path.move(to: p(4, 7)); path.addLine(to: p(13, 7))
            path.move(to: p(17, 7)); path.addLine(to: p(20, 7))
            path.addEllipse(in: CGRect(x: 13 * s, y: 5 * s, width: 4 * s, height: 4 * s))
            path.move(to: p(4, 17)); path.addLine(to: p(7, 17))
            path.move(to: p(11, 17)); path.addLine(to: p(20, 17))
            path.addEllipse(in: CGRect(x: 7 * s, y: 15 * s, width: 4 * s, height: 4 * s))
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.75 * s, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
