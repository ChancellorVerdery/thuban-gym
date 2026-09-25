import Charts
import SwiftUI
import ThubanGymCore

/// The iPhone's range picker (4W · 3M · 6M · 1Y · All).
enum PhoneRange: String, CaseIterable, Identifiable {
    case fourWeeks = "4W", threeMonths = "3M", sixMonths = "6M", year = "1Y", all = "All"
    var id: String { rawValue }

    func start(today: DayKey) -> DayKey? {
        switch self {
        case .fourWeeks: return today.adding(days: -28)
        case .threeMonths: return today.adding(days: -91)
        case .sixMonths: return today.adding(days: -182)
        case .year: return today.adding(days: -365)
        case .all: return nil
        }
    }
}

/// Progress (board Progress): the strength score with its chart, three tiles, and the exercises that improved this
/// month (tap → history), then every other exercise.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var range: PhoneRange = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhoneSegmented(options: PhoneRange.allCases.map { ($0, $0.rawValue) }, selection: $range, accessibilityLabel: "Range")
                if app.firstActivity == nil {
                    Text("Log a few sessions and your strength score shows up here: the average of every exercise's e1RM, as a percentage of where it started.")
                        .font(.subheadline).foregroundStyle(theme.inkDimColor).padding(.top, 24).padding(.horizontal, 4)
                } else {
                    scoreCard.padding(.top, 16)
                    tiles.padding(.top, 12)
                    exerciseLists
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 24)
        }
        .phoneScreen(theme)
        .navigationTitle("Progress")
    }

    // MARK: Strength score

    private var series: [(date: DayKey, score: Double)] {
        guard let first = app.firstActivity else { return [] }
        let start = max(first, range.start(today: app.today) ?? first)
        let span = start.days(to: app.today)
        let step = span <= 35 ? 1 : (span <= 120 ? 3 : 7)
        return Scoring.sampledStrengthSeries(app.data, from: start, through: app.today, stepDays: step)
    }

    private var changeText: (String, DeltaTone)? {
        let days: Int
        let label: String
        switch range {
        case .fourWeeks, .all: days = 28; label = "in 4 weeks"
        case .threeMonths: days = 91; label = "in 3 months"
        case .sixMonths: days = 182; label = "in 6 months"
        case .year: days = 365; label = "in a year"
        }
        guard let change = app.strengthChange(days: days) else { return nil }
        return ("\(GymFormat.delta(change)) \(label)", GymFormat.tone(for: change))
    }

    private var scoreCard: some View {
        Card(padding: 18) {
            Eyebrow("Strength score")
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(app.strengthScore().map { String(format: "%.1f", $0) } ?? "–")
                    .font(PhoneFont.serif(60, relativeTo: .largeTitle))
                    .foregroundStyle(theme.inkColor)
                    .kerning(-1)
                if let change = changeText {
                    Text(change.0).font(.body.weight(.semibold)).foregroundStyle(theme.toneTextColor(change.1))
                }
            }
            .accessibilityElement(children: .combine)
            StrengthChart(points: series.map { ChartPoint(date: $0.date, value: $0.score) }, baseline: 100)
                .frame(height: 150)
                .padding(.top, 10)
        }
    }

    private var tiles: some View {
        let start = range.start(today: app.today)
        let adherence = app.adherence(days: 28)
        return HStack(spacing: 10) {
            tile("Sessions", "\(app.sessionCount(since: start))")
            tile("Average", app.averageDuration(since: start).map { GymFormat.minutes($0) } ?? "–")
            tile("Last 4 weeks", "\(adherence.done) of \(adherence.planned)")
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(PhoneFont.serif(24, relativeTo: .title2)).foregroundStyle(theme.inkColor)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Exercises

    struct ExerciseChange: Identifiable {
        var exercise: Exercise
        var history: ExerciseHistory
        var change: Double?
        var id: String { exercise.id }
    }

    private var changes: [ExerciseChange] {
        let cutoff = app.today.adding(days: -30)
        return app.data.exercises.compactMap { exercise in
            guard let history = app.history(exerciseId: exercise.id), let latest = history.latest else { return nil }
            let base = history.sessions.last { $0.date < cutoff }
            let change = (latest.date >= cutoff && base != nil) ? latest.score - base!.score : nil
            return ExerciseChange(exercise: exercise, history: history, change: change)
        }
    }

    @ViewBuilder private var exerciseLists: some View {
        let all = changes
        let improved = all.filter { ($0.change ?? 0) > 1e-9 }.sorted { relative($0) > relative($1) }
        let rest = all.filter { !improved.map(\.id).contains($0.id) }
        if !improved.isEmpty {
            SectionHeading("Improved this month") {
                Text("e1RM · index").font(.footnote).foregroundStyle(theme.inkFaintColor)
            }
            .padding(.top, 22)
            exerciseCard(improved)
        }
        if !rest.isEmpty {
            SectionHeading(improved.isEmpty ? "Exercises" : "Everything else").padding(.top, 22)
            exerciseCard(rest)
        }
    }

    private func relative(_ item: ExerciseChange) -> Double {
        guard let change = item.change, let first = item.history.first?.score, first > 0 else { return 0 }
        return change / first
    }

    private func exerciseCard(_ items: [ExerciseChange]) -> some View {
        Card {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { RowDivider() }
                Button { app.presentExercise(item.id) } label: { exerciseRow(item) }
                    .buttonStyle(RowPressStyle())
            }
        }
    }

    private func exerciseRow(_ item: ExerciseChange) -> some View {
        let bodyweight = item.history.isBodyweight
        let latest = item.history.latest
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                Text("\(latest.map { app.score($0.score, bodyweight: bodyweight) + (bodyweight ? "" : " \(app.unit.label)") } ?? "–") · \(String(format: "%.1f", item.history.index ?? 100))")
                    .font(PhoneFont.mono(13)).foregroundStyle(theme.inkFaintColor)
            }
            Spacer(minLength: 4)
            if let change = item.change {
                let text = bodyweight ? "\(change >= 0 ? "+" : "−")\(Int(abs(change).rounded())) rep\(Int(abs(change).rounded()) == 1 ? "" : "s")"
                                      : GymFormat.delta(app.unit.fromKilograms(change))
                Text(text).font(PhoneFont.mono(15, relativeTo: .subheadline, weight: .semibold))
                    .foregroundStyle(theme.toneTextColor(GymFormat.tone(for: change)))
            }
            RowChevron()
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

struct ChartPoint: Identifiable {
    var date: DayKey
    var value: Double
    var id: String { date.rawValue }
    var day: Date { date.date() }
}

/// A quiet line chart in theme colours: accent line and points, the last point filled, an optional dashed baseline,
/// hairline grid, month labels in mono.
struct StrengthChart: View {
    @Environment(\.thubanTheme) private var theme
    var points: [ChartPoint]
    var baseline: Double?
    var showsPoints = false
    var showsYLabels = false

    var body: some View {
        let values = points.map(\.value) + (baseline.map { [$0] } ?? [])
        let low = (values.min() ?? 0), high = (values.max() ?? 1)
        let pad = max(1, (high - low) * 0.12)
        Chart {
            if let baseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(theme.line2Color)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(GymFormat.number(baseline)).font(PhoneFont.mono(11, relativeTo: .caption2)).foregroundStyle(theme.inkFaintColor)
                    }
            }
            ForEach(points) { point in
                LineMark(x: .value("Day", point.day), y: .value("Score", point.value))
                    .foregroundStyle(theme.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
                if showsPoints {
                    PointMark(x: .value("Day", point.day), y: .value("Score", point.value))
                        .foregroundStyle(theme.accentColor)
                        .symbolSize(18)
                }
            }
            if let last = points.last {
                PointMark(x: .value("Day", last.day), y: .value("Score", last.value))
                    .foregroundStyle(theme.accentColor)
                    .symbolSize(40)
            }
        }
        .chartYScale(domain: (low - pad)...(high + pad))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(theme.lineColor)
                if showsYLabels, let number = value.as(Double.self) {
                    AxisValueLabel(anchor: .bottomLeading) {
                        Text(GymFormat.number(number, decimals: 0)).font(PhoneFont.mono(11, relativeTo: .caption2)).foregroundStyle(theme.inkFaintColor)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated))
                            .font(PhoneFont.mono(11, relativeTo: .caption2))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                }
            }
        }
        .accessibilityLabel("Chart")
        .accessibilityValue(points.last.map { "Latest \(GymFormat.number($0.value))" } ?? "No data")
    }
}
