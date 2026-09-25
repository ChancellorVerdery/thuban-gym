import Charts
import SwiftUI
import ThubanGymCore

/// "Strength score · weekly" card: the weekly strength score (accent, 2 pt) over the dashed 100 baseline, drawn to
/// scale with Swift Charts; the latest point is ringed and labelled "117.3 today".
struct ProgressChartCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var range: ProgressRange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                Eyebrow("Strength score · weekly")
                Spacer(minLength: 0)
                legend(label: "Score") {
                    Rectangle().fill(theme.accentColor).frame(width: 16, height: 2)
                }
                legend(label: "Baseline 100") {
                    Line().stroke(theme.inkFaintColor, style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 16, height: 1)
                }
            }
            StrengthChart(points: app.weeklyStrengthSeries(range).map { StrengthPoint(date: $0.date, score: $0.score) })
                .frame(height: 226)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .thubanPanel(padding: 0)
    }

    private func legend<Swatch: View>(label: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 6) {
            swatch()
            Text(label).font(.system(size: 12.5)).foregroundStyle(theme.inkDimColor)
        }
        .accessibilityElement(children: .combine)
    }
}

struct StrengthPoint: Identifiable, Hashable {
    var date: DayKey
    var score: Double
    var id: DayKey { date }
    var day: Date { date.date() }
}

/// A horizontal line across the frame (legend swatch).
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct StrengthChart: View {
    @Environment(\.thubanTheme) private var theme
    var points: [StrengthPoint]

    var body: some View {
        let scale = YScale(points.map(\.score))
        Chart {
            RuleMark(y: .value("Baseline", 100))
                .foregroundStyle(theme.inkFaintColor)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            ForEach(points) { point in
                LineMark(x: .value("Week", point.day), y: .value("Strength score", point.score))
                    .foregroundStyle(theme.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
            }
            if let last = points.last {
                PointMark(x: .value("Week", last.day), y: .value("Strength score", last.score))
                    .symbol {
                        Circle()
                            .fill(theme.panelColor)
                            .overlay(Circle().strokeBorder(theme.accentColor, lineWidth: 2))
                            .frame(width: 10, height: 10)
                    }
                    .annotation(position: .topLeading, alignment: .trailing, spacing: 4) {
                        Text("\(String(format: "%.1f", last.score)) today")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                            .fixedSize()
                    }
            }
        }
        .chartYScale(domain: scale.low...scale.high)
        .chartXScale(domain: xDomain)
        .chartYAxis {
            AxisMarks(position: .leading, values: scale.ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(theme.lineColor)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(GymFormat.number(number, decimals: 0))
                            .font(ThubanFont.mono(11))
                            .foregroundStyle(theme.inkFaintColor)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { _ in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(theme.line2Color)
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: false)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
        .chartPlotStyle { plot in plot.background(Color.clear) }
        .accessibilityLabel("Strength score by week")
        .accessibilityValue(points.last.map { "Latest \(String(format: "%.1f", $0.score)), baseline 100" } ?? "No data")
    }

    private var xDomain: ClosedRange<Date> {
        guard let first = points.first?.day, let last = points.last?.day, first < last else {
            let now = Date()
            return now.addingTimeInterval(-86_400 * 28)...now
        }
        return first...last
    }

    /// Round gridlines (step 1 / 2 / 5 / 10 / 20 / 25 / 50) around the data and the 100 baseline.
    struct YScale {
        var low: Double
        var high: Double
        var ticks: [Double]

        init(_ values: [Double]) {
            let lo = min(100, values.min() ?? 100)
            let hi = max(100, values.max() ?? 100)
            let span = max(hi - lo, 4)
            let step = [1.0, 2, 5, 10, 20, 25, 50, 100].first { span / $0 <= 5 } ?? 100
            // A dip that only grazes the baseline keeps 100 as the floor instead of adding a whole empty step.
            low = (lo / step).rounded(.down) * step
            if lo >= 100 - step * 0.1, low < 100 { low = 100 }
            high = (hi / step).rounded(.up) * step
            if high - hi < step * 0.25 { high += step }
            if high <= low { high = low + step }
            ticks = stride(from: low, through: high, by: step).map { $0 }
        }
    }
}
