import SwiftUI
import ThubanGymCore

/// Progress → By exercise (the 470 pt right panel): name + workout, a sparkline of session scores in the range,
/// the latest e1RM (or reps for bodyweight) and the index. Clicking a row opens the Exercise history sheet through
/// the shared route `app.presentedExerciseId` (the shell hosts the sheet).
struct ProgressExerciseList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let rows = app.progressExerciseRows(app.progressRange)
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Eyebrow("By exercise")
                    Text("Est. 1RM (Epley) since first session")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkDimColor)
                }
                Spacer(minLength: 0)
                columnLabel("e1RM", width: ExerciseColumns.score)
                columnLabel("Index", width: ExerciseColumns.index)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if rows.isEmpty {
                Text("Exercises appear here after their first logged session.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .thubanHairline(.top, color: theme.lineColor)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            ProgressExerciseRowView(row: row) { app.presentedExerciseId = row.id }
                        }
                    }
                }
            }
        }
    }

    private func columnLabel(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.inkFaintColor)
            .frame(width: width, alignment: .trailing)
    }
}

enum ExerciseColumns {
    static let sparkline: CGFloat = 96
    static let score: CGFloat = 84
    static let index: CGFloat = 52
}

private struct ProgressExerciseRowView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var row: ProgressExerciseRow
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.exercise.name)
                        .font(.system(size: 14 * textScale, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.system(size: 12 * textScale))
                        .foregroundStyle(theme.inkFaintColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Sparkline(values: row.sparkline)
                    .frame(width: ExerciseColumns.sparkline, height: 28)
                scoreText
                    .frame(width: ExerciseColumns.score, alignment: .trailing)
                Text(String(format: "%.1f", row.index))
                    .font(ThubanFont.mono(13 * textScale, weight: .semibold))
                    .foregroundStyle(indexColor)
                    .frame(width: ExerciseColumns.index, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .background(hovering ? theme.bgColor : Color.clear)
            .thubanHairline(.top, color: theme.lineColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(row.exercise.name), \(subtitle), e1RM \(app.score(row.score, bodyweight: row.isBodyweight)), index \(String(format: "%.1f", row.index))")
        .accessibilityHint("Opens the exercise history")
        .help("Open \(row.exercise.name) history")
    }

    private var subtitle: String {
        let workout = row.workoutName ?? "No workout"
        return row.isBodyweight ? "\(workout) · by reps" : workout
    }

    @ViewBuilder
    private var scoreText: some View {
        if row.isBodyweight {
            Text(app.score(row.score, bodyweight: true))
                .font(ThubanFont.mono(13.5 * textScale))
                .foregroundStyle(theme.inkColor)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(app.score(row.score, bodyweight: false))
                    .font(ThubanFont.mono(13.5 * textScale))
                    .foregroundStyle(theme.inkColor)
                Text(app.unit.label)
                    .font(ThubanFont.mono(11.5 * textScale))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
    }

    private var indexColor: Color {
        if row.index > 100.05 { return theme.posTextColor }
        if row.index < 99.95 { return theme.negTextColor }
        return theme.inkDimColor
    }
}

/// A 1.6 pt accent polyline of values scaled to the frame (2 pt inset), with a dot on the latest value.
struct Sparkline: View {
    @Environment(\.thubanTheme) private var theme
    var values: [Double]

    var body: some View {
        Canvas { context, size in
            let points = Sparkline.points(values, in: size)
            guard let last = points.last else { return }
            if points.count > 1 {
                var path = Path()
                path.addLines(points)
                context.stroke(path, with: .color(theme.accentColor),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            context.fill(Path(ellipseIn: CGRect(x: last.x - 2.4, y: last.y - 2.4, width: 4.8, height: 4.8)),
                         with: .color(theme.accentColor))
        }
        .accessibilityHidden(true)
    }

    static func points(_ values: [Double], in size: CGSize, inset: CGFloat = 2) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let lo = values.min() ?? 0, hi = values.max() ?? 0
        let span = hi - lo
        let width = size.width - inset * 2, height = size.height - inset * 2
        return values.enumerated().map { i, v in
            let x = values.count == 1 ? size.width - inset : inset + width * CGFloat(i) / CGFloat(values.count - 1)
            let y = span == 0 ? size.height / 2 : inset + height * (1 - CGFloat((v - lo) / span))
            return CGPoint(x: x, y: y)
        }
    }
}
