import SwiftUI
import ThubanGymCore

/// Progress → Recent: date, workout, time, length, sets, top set. The running session sits on top with a live
/// length chip ("31 min") and "6 of 20" sets. Fills the rest of the column and scrolls.
struct ProgressRecentTable: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale

    var body: some View {
        GeometryReader { geometry in
            let columns = RecentColumns(width: geometry.size.width)
            VStack(spacing: 0) {
                header(columns)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            VStack(spacing: 0) {
                                ForEach(app.progressRecentRows()) { row in
                                    RecentRow(row: row, columns: columns)
                                }
                            }
                        }
                    }
                }
                // Rows are laid out to the card width; a legacy (always-on) scroller would steal 16 pt and shift them.
                .scrollIndicators(.never)
            }
        }
        .thubanPanel(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .frame(minHeight: 110)
    }

    private func header(_ columns: RecentColumns) -> some View {
        HStack(spacing: RecentColumns.gap) {
            label("Recent", width: columns.date)
            label("Workout", width: columns.workout)
            label("Time", width: columns.time)
            label("Length", width: columns.length)
            label("Sets", width: columns.sets)
            label("Top set", width: columns.top)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func label(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.inkFaintColor)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
    }
}

/// Column widths from the design (104 / 84 / 1.1fr / 76 / 64 / 1.3fr, gap 12, 16 pt side padding).
struct RecentColumns {
    static let gap: CGFloat = 12
    var date: CGFloat = 104
    var workout: CGFloat = 84
    var length: CGFloat = 76
    var sets: CGFloat = 64
    var time: CGFloat
    var top: CGFloat

    init(width: CGFloat) {
        let flexible = max(160, width - 32 - 104 - 84 - 76 - 64 - RecentColumns.gap * 5)
        time = (flexible * 1.1 / 2.4).rounded(.down)
        top = (flexible * 1.3 / 2.4).rounded(.down)
    }
}

private struct RecentRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var row: ProgressSessionRow
    var columns: RecentColumns

    var body: some View {
        HStack(spacing: RecentColumns.gap) {
            Text(GymFormat.shortDay(row.date))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: columns.date, alignment: .leading)
            Text(row.workoutName)
                .fontWeight(.semibold)
                .foregroundStyle(theme.inkColor)
                .frame(width: columns.workout, alignment: .leading)
            Text(row.time.isEmpty ? "–" : row.time)
                .font(ThubanFont.mono(12.5 * textScale))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: columns.time, alignment: .leading)
            length
                .frame(width: columns.length, alignment: .leading)
            Text(row.sets)
                .font(ThubanFont.mono(13.5 * textScale))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: columns.sets, alignment: .leading)
            Text(row.topSet ?? "–")
                .foregroundStyle(theme.inkDimColor)
                .frame(width: columns.top, alignment: .leading)
        }
        .font(.system(size: 13.5 * textScale))
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var length: some View {
        if row.isLive {
            Text(row.minutes.map { "\($0) min" } ?? "now")
                .monospacedDigit()
                .fixedSize()
                .thubanChip(kind: .signal)
        } else {
            Text(row.minutes.map { "\($0) min" } ?? "–")
                .font(ThubanFont.mono(13.5 * textScale))
                .foregroundStyle(theme.inkColor)
        }
    }

    private var accessibilityText: String {
        var parts = [GymFormat.shortDay(row.date), row.workoutName]
        if row.isLive { parts.append("in progress") }
        if !row.time.isEmpty { parts.append(row.time) }
        if let minutes = row.minutes { parts.append("\(minutes) minutes") }
        parts.append("\(row.sets) sets")
        if let top = row.topSet { parts.append("top set \(top)") }
        return parts.joined(separator: ", ")
    }
}
