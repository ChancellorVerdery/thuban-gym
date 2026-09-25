import Charts
import SwiftUI
import ThubanGymCore

/// Exercise history sheet (design: Exercise.dc.html, "Barbell Row history"), presented by the shell whenever
/// `app.presentedExerciseId` is set (Today's names / History, Progress's "By exercise" rows).
/// Header (workout · target · n sessions, serif name, e1RM / Top weight / Volume, Done), four tiles (Est. 1RM,
/// First, Index, Next target), the per-session chart and the session table, newest first. Bodyweight exercises
/// score by reps and show "BW"; unilateral scores use the weaker side. OWNER: Engineer A.
struct ExerciseHistorySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var exerciseId: String

    @State private var metric: ExerciseMetric = .e1RM

    var body: some View {
        Group {
            if let history = app.history(exerciseId: exerciseId) {
                content(history)
            } else {
                EmptyState(icon: .history, title: "Exercise not found", message: "It may have been deleted.") {
                    Button("Done") { dismiss() }.buttonStyle(.thubanPrimary)
                }
            }
        }
        .frame(width: 880, height: 790)
        .background(theme.panelColor)
    }

    private func content(_ history: ExerciseHistory) -> some View {
        VStack(spacing: 0) {
            header(history)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)
            if history.sessions.isEmpty {
                Hairline()
                EmptyState(icon: .history, title: "No sessions yet",
                           message: "Log a set of \(history.exercise.name) on Today and its history starts here.")
            } else {
                tiles(history)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                    .thubanHairline(.bottom, color: theme.lineColor)
                ExerciseChart(history: history, metric: metric)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ExerciseSessionTable(history: history)
            }
        }
    }

    // MARK: Header

    private func header(_ history: ExerciseHistory) -> some View {
        let exercise = history.exercise
        var eyebrow: [String] = []
        if let workout = app.workout(exercise.workoutId) { eyebrow.append(workout.name) }
        if let spec = exercise.targetSpec { eyebrow.append(spec.display) }
        if exercise.unilateral { eyebrow.append("L / R") }
        eyebrow.append("\(history.sessions.count) session\(history.sessions.count == 1 ? "" : "s")")
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(eyebrow.joined(separator: " · "))
                Text(exercise.name)
                    .font(ThubanFont.display(28))
                    .kerning(-0.28)
                    .foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if !history.sessions.isEmpty {
                    SegmentedPicker(selection: $metric,
                                    options: ExerciseMetric.options(bodyweight: history.isBodyweight),
                                    segmentHeight: SegmentedPickerHeight.card + 2)
                }
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(height: 30))
                    .keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ history: ExerciseHistory) -> some View {
        let bw = history.isBodyweight
        let latest = history.latest!
        let first = history.first!
        let isToday = latest.date == app.today
        let index = latest.index
        let indexChange = index - 100
        return HStack(alignment: .top, spacing: 16) {
            ExerciseTile(label: bw ? "Best reps" : "Est. 1RM",
                         value: bw ? "\(Int(latest.score.rounded())) reps" : "\(app.score(latest.score, bodyweight: false)) \(app.unit.label)",
                         caption: bestSetText(latest) + (isToday ? " today" : " on \(GymFormat.monthDay(latest.date))"),
                         tone: latest.isBest ? .pos : .dim)
            ExerciseTile(label: "First",
                         value: bw ? "\(Int(first.score.rounded())) reps" : "\(app.score(first.score, bodyweight: false)) \(app.unit.label)",
                         caption: "\(bestSetText(first)) on \(GymFormat.monthDay(first.date))", tone: .dim)
            ExerciseTile(label: "Index", value: String(format: "%.1f", index),
                         caption: "\(GymFormat.delta(indexChange)) since \(GymFormat.month(first.date))",
                         tone: { switch GymFormat.tone(for: indexChange) { case .pos: return .pos; case .neg: return .neg; case .neutral: return .dim } }())
            nextTargetTile(history)
        }
    }

    private func bestSetText(_ session: ExerciseSession) -> String {
        guard let set = session.bestSet else { return "" }
        return GymFormat.set(set, unit: app.unit)
    }

    private func nextTargetTile(_ history: ExerciseHistory) -> some View {
        guard let next = app.nextTarget(exerciseId: history.exercise.id) else {
            return ExerciseTile(label: "Next target", value: "—", caption: "set a target like 3×8", tone: .dim)
        }
        if next.weightKg == nil {
            return ExerciseTile(label: "Next target", value: "BW × \(next.reps) × \(next.sets)", caption: "one more rep", tone: .dim)
        }
        let caption = next.increase
            ? "up \(GymFormat.weightWithUnit(next.incrementKg, unit: app.unit, decimals: 1)) from last time"
            : "then add \(GymFormat.weightWithUnit(next.incrementKg, unit: app.unit, decimals: 1))"
        return ExerciseTile(label: "Next target", value: "\(app.weight(next.weightKg)) × \(next.reps) × \(next.sets)",
                            caption: caption, tone: next.increase ? .accent : .dim)
    }
}

// MARK: - Metric

enum ExerciseMetric: String, Hashable, CaseIterable {
    case e1RM, topWeight, volume

    static func options(bodyweight: Bool) -> [SegmentOption<ExerciseMetric>] {
        [SegmentOption(.e1RM, bodyweight ? "Reps" : "e1RM"),
         SegmentOption(.topWeight, "Top weight"),
         SegmentOption(.volume, "Volume")]
    }
}

// MARK: - Tile

struct ExerciseTile: View {
    enum Tone { case dim, pos, neg, accent }
    @Environment(\.thubanTheme) private var theme
    var label: String
    var value: String
    var caption: String
    var tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.84)
                .foregroundStyle(theme.inkDimColor)
            Text(value)
                .font(ThubanFont.display(24))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.vertical, 2)
            Text(caption)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tone {
        case .dim: return theme.inkDimColor
        case .pos: return theme.posTextColor
        case .neg: return theme.negTextColor
        case .accent: return theme.brassInkColor
        }
    }
}

// MARK: - Chart

/// Per-session step line in `accent`, a dashed `inkFaint` baseline at the first session, and the latest value
/// ringed and labelled. Range follows `app.progressRange` (3M / 6M / All).
struct ExerciseChart: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var history: ExerciseHistory
    var metric: ExerciseMetric

    private struct Point: Identifiable {
        var date: Date
        var value: Double
        var id: Date { date }
    }

    var body: some View {
        @Bindable var app = app
        let points = self.points
        let baseline = points.first?.value
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow(title)
                Spacer()
                SegmentedPicker(selection: $app.progressRange,
                                options: ProgressRange.allCases.map { SegmentOption($0, $0.rawValue) },
                                segmentHeight: SegmentedPickerHeight.card)
            }
            if points.count < 2 {
                Text(points.isEmpty ? "No sessions in this range." : "One session so far: the line starts with the next one.")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkDimColor)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                chart(points, baseline: baseline)
                    .frame(height: 220)
                    .padding(.top, 4)
            }
        }
    }

    private var title: String {
        switch metric {
        case .e1RM: return history.isBodyweight ? "Best reps per session" : "Est. 1RM per session · \(app.unit.label)"
        case .topWeight: return "Top weight per session · \(app.unit.label)"
        case .volume: return history.isBodyweight ? "Total reps per session" : "Volume per session · \(app.unit.label)"
        }
    }

    private var points: [Point] {
        let start = app.progressRange.start(today: app.today)
        return history.sessions.compactMap { session -> Point? in
            if let start, session.date < start { return nil }
            let value: Double?
            switch metric {
            case .e1RM: value = history.isBodyweight ? session.score : app.unit.fromKilograms(session.score)
            case .topWeight: value = session.topWeight.map(app.unit.fromKilograms)
            case .volume: value = history.isBodyweight ? Double(session.totalReps) : app.unit.fromKilograms(session.volume)
            }
            return value.map { Point(date: session.date.date(hour: 12), value: $0) }
        }
    }

    private func label(_ value: Double) -> String {
        metric == .volume || history.isBodyweight ? GymFormat.number(value, decimals: 0) : String(format: "%.1f", value)
    }

    private func chart(_ points: [Point], baseline: Double?) -> some View {
        let values = points.map(\.value) + (baseline.map { [$0] } ?? [])
        let low = values.min() ?? 0, high = values.max() ?? 1
        let pad = max((high - low) * 0.12, 1)
        let last = points.last!
        return Chart {
            if let baseline {
                RuleMark(y: .value("First", baseline))
                    .foregroundStyle(theme.inkFaintColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
            }
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(theme.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            PointMark(x: .value("Date", last.date), y: .value("Value", last.value))
                .symbol {
                    Circle()
                        .fill(theme.panelColor)
                        .overlay(Circle().strokeBorder(theme.accentColor, lineWidth: 2))
                        .frame(width: 10, height: 10)
                }
                .annotation(position: .topLeading, spacing: 4) {
                    Text(label(last.value))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                }
        }
        .chartYScale(domain: (low - pad)...(high + pad * 1.6))
        .chartPlotStyle { plot in plot.padding(.top, 8) }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
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
            AxisMarks(values: .stride(by: .month)) { value in
                AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(theme.line2Color)
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Table

/// Date · Weight · Reps per set · Best e1RM · Volume · chip (Best / Up 5 lb), newest first.
struct ExerciseSessionTable: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var history: ExerciseHistory

    var body: some View {
        // The header is a pinned section header so it shares the rows' width (a visible scroller narrows both).
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(history.sessions.reversed()) { session in
                        sessionRow(session)
                    }
                } header: {
                    row(header: true) {
                        cell("Date", width: 120)
                        cell("Weight", width: 80)
                        cell("Reps per set")
                        cell(history.isBodyweight ? "Best reps" : "Best e1RM", width: 104, alignment: .trailing)
                        cell(history.isBodyweight ? "Total reps" : "Volume", width: 104, alignment: .trailing)
                        cell("", width: 80, alignment: .trailing)
                    }
                    .frame(height: 34)
                    .background(theme.bgColor)
                }
            }
        }
        .thubanHairline(.top, color: theme.lineColor)
    }

    private func row<Content: View>(header: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 20)
            .font(header ? .system(size: 11.5, weight: .semibold) : .system(size: 13.5))
            .kerning(header ? 0.8 : 0)
            .textCase(header ? .uppercase : nil)
            .foregroundStyle(header ? theme.inkFaintColor : theme.inkColor)
    }

    private func cell(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func reps(_ sets: [SetEntry]) -> String { sets.map { String($0.reps) }.joined(separator: " · ") }

    private func repsText(_ session: ExerciseSession) -> String {
        if !session.left.isEmpty || !session.right.isEmpty {
            var parts: [String] = []
            if !session.left.isEmpty { parts.append("L \(reps(session.left))") }
            if !session.right.isEmpty { parts.append("R \(reps(session.right))") }
            if !session.sets.isEmpty { parts.append(reps(session.sets)) }
            return parts.joined(separator: "  ")
        }
        return reps(session.sets)
    }

    private func sessionRow(_ session: ExerciseSession) -> some View {
        let bw = history.isBodyweight
        return row {
            Text(GymFormat.shortDay(session.date))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 120, alignment: .leading)
            Text(session.topWeight.map { app.weightWithUnit($0) } ?? "BW")
                .font(ThubanFont.mono(13.5))
                .frame(width: 80, alignment: .leading)
            Text(repsText(session))
                .font(ThubanFont.mono(13.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(bw ? "\(Int(session.score.rounded()))" : app.score(session.score, bodyweight: false))
                .font(ThubanFont.mono(13.5))
                .frame(width: 104, alignment: .trailing)
            Text(bw ? "\(session.totalReps)" : GymFormat.grouped(Int(app.unit.fromKilograms(session.volume).rounded())))
                .font(ThubanFont.mono(13.5))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 104, alignment: .trailing)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if session.isBest {
                    Chip("Best", kind: .pos)
                } else if let change = session.topWeightChange, abs(change) > 0.01 {
                    Chip("\(change > 0 ? "Up" : "Down") \(GymFormat.weightWithUnit(abs(change), unit: app.unit))",
                         kind: change > 0 ? .warn : .neutral)
                }
            }
            .frame(width: 80)
        }
        .frame(height: 40)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }
}
