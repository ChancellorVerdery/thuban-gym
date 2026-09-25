import SwiftUI
import ThubanGymCore

/// "WEEKLY PLAN" (weekly mode): one row per weekday, each with a workout picker (or nothing = rest) and when it
/// next comes up.
struct PlanWeeklyEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        PlanCard {
            VStack(alignment: .leading, spacing: 3) {
                Eyebrow("Weekly plan")
                Text("Each weekday has its own workout. A day with nothing planned is a rest day.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Weekday.allCases) { day in PlanWeekdayRow(day: day) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            Spacer(minLength: 0)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").font(.system(size: 13)).foregroundStyle(theme.inkDimColor)
                Text("Skips and swaps change one date only; the weekday keeps its workout.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgColor)
            .thubanHairline(.top, color: theme.lineColor)
        }
    }
}

struct PlanWeekdayRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var day: Weekday
    @State private var picking = false

    var body: some View {
        let workout = app.workout(app.plan.weeklyWorkoutId(day))
        let isToday = app.today.weekday == day
        HStack(spacing: 12) {
            Text(day.name)
                .font(.system(size: 15 * textScale, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 104, alignment: .leading)
            Button { picking = true } label: {
                HStack(spacing: 8) {
                    Text(workout?.name ?? "Rest (nothing planned)")
                        .font(.system(size: 14 * textScale, weight: .semibold))
                        .foregroundStyle(workout == nil || workout?.isRest == true ? theme.inkDimColor : theme.inkColor)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Glyph(.chevronDown, size: 12).foregroundStyle(theme.inkFaintColor)
                }
                .padding(.horizontal, 10)
                .frame(width: 220, height: 32)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                    .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(day.name) workout: \(workout?.name ?? "nothing")")
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                PlanWorkoutPicker(title: day.name, workouts: app.workouts, allowsNone: true, selectedId: workout?.id) { picked in
                    app.setWeekly(day, workoutId: picked?.id)
                    picking = false
                }
                .environment(\.thubanTheme, theme)
            }
            Spacer(minLength: 8)
            if isToday {
                Chip("Today", kind: .accent)
            } else if let workout, !workout.isRest {
                Text(workout.kind == .flex ? "Log anything" : app.workoutSummary(workout, includeDuration: false))
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
                    .lineLimit(1)
            } else {
                Icon(.moon, size: 14).foregroundStyle(theme.inkFaintColor)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(isToday ? theme.accentTintColor : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(isToday ? theme.accentColor : .clear).frame(width: 3) }
        .thubanHairline(.top, color: theme.lineColor)
    }
}

/// "WEEKLY PLAN · SAVED, NOT ACTIVE" (cycle mode): the weekly plan in seven small cells.
struct PlanWeeklyPreview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("Weekly plan · saved, not active")
                Spacer(minLength: 8)
                Button("Switch to Weekly to use it") { app.setPlanType(.weekly) }
                    .buttonStyle(.plain)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkFaintColor)
            }
            HStack(spacing: 6) {
                ForEach(Weekday.allCases) { day in
                    let workout = app.workout(app.plan.weeklyWorkoutId(day))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.short.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .kerning(0.77)
                            .foregroundStyle(theme.inkFaintColor)
                        Text(workout?.name ?? "Rest")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(workout == nil || workout?.isRest == true ? theme.inkDimColor : theme.inkColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                        .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .thubanPanel(padding: 0)
        .opacity(0.9)
    }
}

/// "CYCLE · SAVED, NOT ACTIVE" (weekly mode): the cycle order as numbered chips.
struct PlanCyclePreview: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow("Cycle · saved, not active")
                Spacer(minLength: 8)
                Button("Switch to Cycle to use it") { app.setPlanType(.cycle) }
                    .buttonStyle(.plain)
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkFaintColor)
            }
            if app.plan.cycle.isEmpty {
                Text("No cycle yet. Switch to Cycle to build one.")
                    .font(ThubanFont.small)
                    .foregroundStyle(theme.inkDimColor)
            } else {
                PlanFlowLayout(spacing: 6) {
                    ForEach(Array(app.plan.cycle.enumerated()), id: \.offset) { index, id in
                        let workout = app.workout(id)
                        HStack(spacing: 6) {
                            Text(String(index + 1)).font(ThubanFont.mono(12)).foregroundStyle(theme.inkFaintColor)
                            Text(workout?.name ?? "Missing")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(workout?.isRest == true ? theme.inkDimColor : theme.inkColor)
                            if index == app.plan.normalizedPosition {
                                Text("next").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(theme.brassInkColor)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous)
                            .strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .thubanPanel(padding: 0)
        .opacity(0.9)
    }
}

/// Wraps children onto new lines (chips).
struct PlanFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for row in rows {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [index], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(index)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
