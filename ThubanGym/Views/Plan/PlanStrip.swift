import SwiftUI
import ThubanGymCore

/// "NEXT 14 DAYS · SEP 21 – OCT 4" with its legend, then two weeks of day cells split by a hairline.
/// Each future day has a context menu: skip it, swap it, or undo its override.
struct PlanStrip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let days = app.planStrip
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Eyebrow(title(days))
                Spacer(minLength: 8)
                legend
            }
            HStack(spacing: 6) {
                ForEach(Array(days.prefix(7))) { day in PlanDayCell(day: day, showsMonth: day.date.day == 1) }
                Rectangle().fill(theme.line2Color).frame(width: ThubanMetrics.hairline).padding(.vertical, 4).padding(.horizontal, 2)
                ForEach(Array(days.dropFirst(7))) { day in PlanDayCell(day: day, showsMonth: day.date.day == 1) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .thubanPanel(padding: 0)
    }

    private func title(_ days: [PlanDay]) -> String {
        guard let first = days.first?.date, let last = days.last?.date else { return "Next 14 days" }
        return "Next 14 days · \(GymFormat.monthDay(first)) – \(GymFormat.monthDay(last))"
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Done") { Icon(.check, size: 14).foregroundStyle(theme.posTextColor) }
            legendItem("Today") { Circle().fill(theme.accentColor).frame(width: 8, height: 8) }
            legendItem("Skipped") { Icon(.skip, size: 14).foregroundStyle(theme.negTextColor) }
            legendItem("Swapped") { Icon(.swap, size: 14).foregroundStyle(theme.brassInkColor) }
            legendItem("Rest") { Icon(.moon, size: 14).foregroundStyle(theme.inkFaintColor) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: done, today, skipped, swapped, rest")
    }

    private func legendItem<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 6) {
            mark()
            Text(text).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
    }
}

/// One day: weekday + status mark, the date (mono), the workout, and a status line.
struct PlanDayCell: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var day: PlanDay
    var showsMonth: Bool

    var body: some View {
        let restLike = day.status == .rest || day.status == .restDone
        let dim = restLike || day.status == .missed || day.status == .empty
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(day.date.weekday.short.uppercased())
                    .font(.system(size: 11.5, weight: .semibold))
                    .kerning(0.8)
                    .foregroundStyle(theme.inkFaintColor)
                Spacer(minLength: 0)
                mark
            }
            .frame(height: 16)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(day.date.day))
                    .font(ThubanFont.mono(20, weight: .semibold))
                    .foregroundStyle(dim ? theme.inkDimColor : theme.inkColor)
                if showsMonth {
                    Text(GymFormat.month(day.date))
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkFaintColor)
                }
            }
            Text(workoutName)
                .font(.system(size: 14 * textScale, weight: .semibold))
                .strikethrough(day.status == .skipped, color: theme.inkFaintColor)
                .foregroundStyle(nameColor(dim: dim))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(statusText)
                .font(.system(size: 12 * textScale, weight: .semibold))
                .foregroundStyle(statusColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(day.isToday ? theme.accentColor : theme.lineColor, lineWidth: ThubanMetrics.hairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(GymFormat.longDay(day.date)): \(workoutName), \(statusText)")
    }

    // MARK: Parts

    @ViewBuilder
    private var mark: some View {
        if day.isToday {
            Circle().fill(theme.accentColor).frame(width: 8, height: 8)
        } else {
            switch day.status {
            case .done: Icon(.check, size: 14).foregroundStyle(theme.posTextColor)
            case .skipped: Icon(.skip, size: 14).foregroundStyle(theme.negTextColor)
            case .swapped: Icon(.swap, size: 14).foregroundStyle(theme.brassInkColor)
            case .rest, .restDone: Icon(.moon, size: 14).foregroundStyle(theme.inkFaintColor)
            default: EmptyView()
            }
        }
    }

    private var workoutName: String {
        if let workout = day.workout { return workout.name }
        switch day.status {
        case .missed: return "Missed"
        case .skipped: return "Skipped"
        default: return "Nothing"
        }
    }

    private var statusText: String {
        switch day.status {
        case .done:
            if let minutes = day.completions.last(where: { $0.durationMinutes != nil })?.durationMinutes { return GymFormat.minutes(minutes) }
            return "Done"
        case .inProgress: return "In progress"
        case .planned: return day.isToday ? "Today" : "Planned"
        case .skipped: return "Skipped"
        case .swapped: return "Swapped"
        case .rest: return day.override != nil ? "Swapped · rest" : "Rest day"
        case .restDone: return "Rest day"
        case .missed: return "Not done"
        case .empty: return "Nothing planned"
        }
    }

    private var statusColor: Color {
        switch day.status {
        case .done: return theme.posTextColor
        case .inProgress, .swapped: return theme.brassInkColor
        case .skipped: return theme.negTextColor
        case .planned: return day.isToday ? theme.brassInkColor : theme.inkDimColor
        case .rest, .restDone, .missed, .empty: return theme.inkFaintColor
        }
    }

    private func nameColor(dim: Bool) -> Color {
        if day.status == .skipped { return theme.inkFaintColor }
        return dim ? theme.inkDimColor : theme.inkColor
    }

    private var background: Color {
        if day.isToday { return theme.accentTintColor }
        switch day.status {
        case .rest, .restDone, .empty: return theme.bgColor
        default: return theme.panelColor
        }
    }

    // MARK: Context menu (future days)

    @ViewBuilder
    private var menu: some View {
        if day.date >= app.today {
            if day.override != nil {
                Button("Undo \(day.override?.isSkip == true ? "skip" : "swap")") { app.clearOverride(date: day.date) }
            }
            if day.status != .skipped {
                Button("Skip \(day.date.planShort)") { app.skip(date: day.date) }
            }
            Menu("Swap to") {
                ForEach(app.workouts) { workout in
                    Button(workout.name) { app.swap(date: day.date, to: workout.id) }
                        .disabled(workout.id == day.workout?.id && day.status != .skipped)
                }
            }
        }
    }
}
