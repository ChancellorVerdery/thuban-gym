import SwiftUI
import ThubanGymCore

/// Progress section (design: Progress.dc.html). Left: "Stronger by x%" header, four stat tiles, the weekly strength
/// score chart with the 100 baseline, and the Recent sessions table. Right (470 pt panel): By exercise — sparkline,
/// e1RM and index per exercise; a row opens the Exercise history sheet (`app.presentedExerciseId`).
/// OWNER: Engineer C (Progress + Settings/Import).
struct ProgressScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        if app.strengthScore() == nil && app.progressRecentRows(limit: 1).isEmpty {
            ProgressEmptyState()
        } else {
            HStack(spacing: 0) {
                ProgressMainColumn()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ProgressExerciseList()
                    .frame(width: 470)
                    .frame(maxHeight: .infinity)
                    .background(theme.panelColor)
                    .thubanHairline(.leading, color: theme.lineColor)
            }
            .background(theme.bgColor)
        }
    }
}

// MARK: - Main column

private struct ProgressMainColumn: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let range = app.progressRange
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(eyebrow: app.progressEyebrow(range), title: title,
                       subtitle: "Strength score is the average of every exercise's index, so a curl counts as much as a squat. 100 is your first logged session.")
            ProgressTiles(range: range)
            ProgressChartCard(range: range)
            ProgressRecentTable()
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
    }

    private var title: String {
        guard let gain = app.strengthGainPercent else { return "No score yet" }
        let text = String(format: "%.1f%%", abs(gain))
        if abs(gain) < 0.05 { return "Level with your first session" }
        return gain > 0 ? "Stronger by \(text)" : "Weaker by \(text)"
    }
}

// MARK: - Tiles

private struct ProgressTiles: View {
    @Environment(AppModel.self) private var app
    var range: ProgressRange

    var body: some View {
        let last30 = app.today.adding(days: -29)
        let recentAverage = app.averageDuration(since: last30)
        let allAverage = app.averageDuration()
        let adherence = app.adherence(days: 30)
        let change = app.strengthChange(days: 28)
        HStack(spacing: 12) {
            ProgressTile(label: "Strength score",
                         value: app.strengthScore().map { String(format: "%.1f", $0) } ?? "–",
                         caption: change.map { "\(GymFormat.delta($0)) in 4 weeks" } ?? "first four weeks",
                         tone: change.map { $0 > 0.05 ? .pos : ($0 < -0.05 ? .neg : .neutral) } ?? .neutral)
            ProgressTile(label: "Sessions",
                         value: GymFormat.grouped(app.progressSessionCount(range)),
                         caption: app.progressStart(range).map { "since \(GymFormat.monthDay($0))" } ?? "none yet")
            ProgressTile(label: "Avg session",
                         value: (recentAverage ?? allAverage).map { "\($0) min" } ?? "–",
                         caption: averageCaption(recent: recentAverage, all: allAverage))
            ProgressTile(label: "On plan",
                         value: "\(adherence.done) of \(adherence.planned)",
                         caption: "planned days, last 30")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func averageCaption(recent: Int?, all: Int?) -> String {
        switch (recent, all) {
        case let (_?, a?): return "last 30 days · \(a) all-time"
        case (nil, _?): return "all-time"
        default: return "no timed sessions"
        }
    }
}

/// The design's number tile: 12 pt uppercase label, 28 pt serif value, 12.5 pt semibold caption.
private struct ProgressTile: View {
    @Environment(\.thubanTheme) private var theme
    var label: String
    var value: String
    var caption: String
    var tone: ChipKind = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(label)
            Text(value)
                .font(ThubanFont.display(28))
                .foregroundStyle(theme.inkColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 4)
            Text(caption)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(tone == .neutral ? theme.inkDimColor : tone.colors(theme).text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .thubanPanel(padding: 0)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty

private struct ProgressEmptyState: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        EmptyState(icon: .progress, title: "No progress yet",
                   message: app.isFirstRun
                    ? "Bring your history over from Atlas, or log a session on Today. Your first session sets every exercise to 100."
                    : "Log a session on Today. Your first session sets every exercise to 100, and the strength score grows from there.") {
            HStack(spacing: 10) {
                if app.isFirstRun {
                    Button("Import from Atlas…") { app.openSettings(.importAtlas) }
                        .buttonStyle(.thubanPrimary)
                }
                Button("Go to Today") { app.section = .today }
                    .buttonStyle(.thubanSecondary)
            }
        }
    }
}
