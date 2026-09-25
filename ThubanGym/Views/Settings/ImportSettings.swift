import SwiftUI
import ThubanGymCore

/// Settings → Import from Atlas (design: Import.dc.html). On first run it is the welcome ("First run · one-time
/// import"). The import card follows `app.importPhase`: Check Atlas (ssh, read-only) or a JSON file → the counts
/// preview → Import (a backup first; confirmation when it replaces local data) → done / failed. Below: the ssh
/// host + email, the exact command, and — as on the artboard — Units and Scheme.
/// OWNER: Engineer C (Progress + Settings/Import).
struct ImportSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            ImportCard()
            ImportConnectionGroup()
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Units").font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
                    Text("Display only. Weights are stored in kg, so switching never rounds your history.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    UnitsPicker()
                }
                .frame(width: 230, alignment: .leading)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Scheme").font(ThubanFont.display(20)).foregroundStyle(theme.inkColor)
                        Text("The eight Thuban schemes. Mode follows macOS.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(theme.inkDimColor)
                            .lineLimit(1)
                    }
                    SchemeGrid(columns: 4, spacing: 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if app.isFirstRun {
            SettingsPaneHeader(eyebrow: "First run · one-time import", title: "Bring your training over from Atlas",
                               caption: "Reads the Atlas gym plugin on your Beelink once. Your plan, history and scores carry over exactly; nothing is sent back.")
        } else {
            SettingsPaneHeader(eyebrow: importedEyebrow, title: "Import from Atlas",
                               caption: "Reads the Atlas gym plugin again and replaces what is here, after saving a backup. Nothing is sent back to Atlas.")
        }
    }

    private var importedEyebrow: String {
        guard let at = app.data.importedAt else { return "Re-runnable · replaces local data" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Last imported \(formatter.string(from: at)) · re-runnable"
    }
}

// MARK: - Import card

private struct ImportCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var confirmReplace = false

    var body: some View {
        VStack(spacing: 0) {
            top
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 14)
            ForEach(steps) { step in
                ImportStepRow(step: step)
            }
            if let note = footnote {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Icon(.info, size: 14).foregroundStyle(theme.inkDimColor).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(theme.bgColor)
                .thubanHairline(.top, color: theme.lineColor)
            }
        }
        .thubanPanel(padding: 0)
        .clipShape(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .confirmationDialog("Replace the data on this Mac?", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("Back up and replace", role: .destructive) { app.applyImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceMessage)
        }
    }

    // MARK: Top row (title, detail, actions) per phase

    @ViewBuilder
    private var top: some View {
        switch app.importPhase {
        case .idle:
            topRow(title: "Check Atlas first", detail: "Nothing is imported until you have seen the counts.", mono: false) {
                Button("Import from a file…") { app.chooseImportFile() }.buttonStyle(SecondaryButtonStyle(height: 32))
                Button("Check Atlas") { app.fetchAtlasPreview() }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(!connectionIsValid)
                    .keyboardShortcut(.defaultAction)
            }
        case .fetching:
            VStack(alignment: .leading, spacing: 10) {
                topRow(title: "Reading Atlas", detail: "ssh \(app.preferences.atlasHost) · one read-only query", mono: true) {
                    Button("Cancel") { app.cancelImport() }.buttonStyle(SecondaryButtonStyle(height: 32))
                }
                IndeterminateBar()
            }
        case .preview(let preview):
            VStack(alignment: .leading, spacing: 10) {
                topRow(title: "Ready to import", detail: previewDetail(preview), mono: true) {
                    Button("Cancel") { app.cancelImport() }.buttonStyle(SecondaryButtonStyle(height: 32))
                    Button(preview.replacesExisting ? "Back up and import" : "Import") {
                        if preview.replacesExisting { confirmReplace = true } else { app.applyImport() }
                    }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .keyboardShortcut(.defaultAction)
                }
            }
        case .applying:
            VStack(alignment: .leading, spacing: 10) {
                topRow(title: "Importing", detail: "saving a backup, then replacing the local data", mono: true) { EmptyView() }
                ProgressBar(value: 0.66)
            }
        case .done(let summary, let backup):
            VStack(alignment: .leading, spacing: 10) {
                if let backup {
                    // The file name gets its own one-line Text so it never breaks inside the name.
                    let name = backup.lastPathComponent
                    HStack(alignment: .center, spacing: 16) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Imported")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.posTextColor)
                                .fixedSize()
                            Text("previous data saved as")
                                .font(ThubanFont.mono(13))
                                .foregroundStyle(theme.inkDimColor)
                                .fixedSize()
                            Text(name)
                                .font(ThubanFont.mono(13))
                                .foregroundStyle(theme.inkDimColor)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(name)
                                .textSelection(.enabled)
                                .layoutPriority(-1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Button("Show backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                                .buttonStyle(SecondaryButtonStyle(height: 32))
                            Button("Done") { app.cancelImport() }
                                .buttonStyle(PrimaryButtonStyle(height: 32))
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                } else {
                    topRow(title: "Imported", titleColor: theme.posTextColor,
                           detail: "\(GymFormat.grouped(summary.sets)) sets · nothing to back up", mono: true) {
                        Button("Done") { app.cancelImport() }
                            .buttonStyle(PrimaryButtonStyle(height: 32))
                            .keyboardShortcut(.defaultAction)
                    }
                }
                ProgressBar(value: 1, tint: theme.posColor)
            }
        case .failed(let message):
            topRow(title: "Atlas could not be read", titleColor: theme.negTextColor, detail: message, mono: false) {
                Button("Import from a file…") { app.chooseImportFile() }.buttonStyle(SecondaryButtonStyle(height: 32))
                Button("Try again") { app.fetchAtlasPreview() }
                    .buttonStyle(PrimaryButtonStyle(height: 32))
                    .disabled(!connectionIsValid)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func topRow<Actions: View>(title: String, titleColor: Color? = nil, detail: String, mono: Bool,
                                       @ViewBuilder actions: () -> Actions) -> some View {
        let titleText = Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(titleColor ?? theme.inkColor)
        let detailText = Text(detail)
            .font(mono ? ThubanFont.mono(13) : .system(size: 13.5))
            .foregroundStyle(theme.inkDimColor)
            .textSelection(.enabled)
        return HStack(alignment: .center, spacing: 16) {
            // Inline like the design ("Importing sets  1,776 of 2,690") when it fits, else the detail goes below.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    titleText.fixedSize()
                    detailText.fixedSize()
                }
                VStack(alignment: .leading, spacing: 3) {
                    titleText
                    detailText.lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) { actions() }
        }
    }

    private func previewDetail(_ preview: ImportPreview) -> String {
        let source = preview.source.hasPrefix("file:") ? String(preview.source.dropFirst(5)) : preview.source
        if let email = preview.summary.email { return "\(source) · \(email)" }
        return source
    }

    private var connectionIsValid: Bool {
        (try? AtlasImporter.validateHost(app.preferences.atlasHost)) != nil
            && (try? AtlasImporter.validateEmail(app.preferences.atlasEmail)) != nil
    }

    private var replaceMessage: String {
        guard case .preview(let preview) = app.importPhase else { return "" }
        return "This replaces \(preview.localWorkouts) workouts, \(GymFormat.grouped(preview.localSets)) sets and \(preview.localSessions) sessions. A backup is saved first and can be restored from Data & storage."
    }

    // MARK: Steps

    private var summary: ImportSummary? {
        switch app.importPhase {
        case .preview(let preview): return preview.summary
        case .done(let summary, _): return summary
        default: return nil
        }
    }

    private var steps: [ImportStep] {
        let phase = app.importPhase
        guard let s = summary else {
            let fetching = phase == .fetching
            return ImportStep.placeholders.enumerated().map { index, step in
                var step = step
                step.state = fetching && index == 0 ? .active : .pending
                return step
            }
        }
        let range: String = {
            guard let first = s.firstSession, let last = s.lastSession else { return "none in Atlas yet" }
            return "start and end times, \(GymFormat.monthDay(first)) – \(GymFormat.monthDay(last))"
        }()
        let plan: String = {
            switch s.planType {
            case .cycle:
                guard s.cycleLength > 0 else { return "an empty cycle" }
                let pointer = s.pointerWorkout.map { ", pointer on \($0) (day \(s.pointerIndex + 1))" } ?? ""
                return "\(s.cycleLength) workouts\(pointer)"
            case .weekly:
                return "\(s.weeklyDays) of 7 days planned"
            }
        }()
        var flags: [String] = []
        if s.unilateralExercises > 0 { flags.append("\(s.unilateralExercises) single-arm") }
        if s.bodyweightExercises > 0 { flags.append("\(s.bodyweightExercises) bodyweight") }
        func state(_ count: Int) -> ImportStep.State { count > 0 ? .done : .empty }
        return [
            ImportStep(title: "Workouts", detail: s.workoutNames.isEmpty ? "none" : s.workoutNames.joined(separator: ", "),
                       value: String(s.workouts), state: state(s.workouts)),
            ImportStep(title: "Exercises", detail: flags.isEmpty ? "targets, L/R and bodyweight flags" : "targets · \(flags.joined(separator: ", "))",
                       value: String(s.exercises), state: state(s.exercises)),
            ImportStep(title: "Plan", detail: plan, value: s.planType.label, state: .done),
            ImportStep(title: "Sessions", detail: range, value: GymFormat.grouped(s.completions), state: state(s.completions)),
            ImportStep(title: "Sets", detail: "weights converted to kg for storage, shown in \(s.unit.label)",
                       value: GymFormat.grouped(s.sets), state: state(s.sets)),
            ImportStep(title: "Overrides and extras", detail: "skips, swaps, borrowed exercises",
                       value: "\(s.overrides) + \(s.extras)", state: state(s.overrides + s.extras)),
        ]
    }

    private var footnote: String? {
        switch app.importPhase {
        case .preview(let preview):
            var parts: [String] = []
            if let expected = Scoring.strengthScore(preview.data, on: app.today) {
                parts.append("Strength score is recomputed from every set after import (Epley, 100 = first session). Expected: \(String(format: "%.1f", expected)).")
            } else {
                parts.append("No sets yet, so there is no strength score until your first logged session.")
            }
            if preview.replacesExisting {
                parts.append("Replaces \(preview.localWorkouts) workouts and \(GymFormat.grouped(preview.localSets)) sets here, after a backup.")
            }
            parts.append(contentsOf: preview.summary.warnings.map { "Note: \($0)." })
            return parts.joined(separator: " ")
        case .done(let summary, _):
            return summary.warnings.isEmpty ? "Your plan, workouts and history are on this Mac now. Atlas was not changed." : summary.warnings.map { "Note: \($0)." }.joined(separator: " ")
        case .failed:
            return "Check that “ssh \(app.preferences.atlasHost)” works in Terminal without a password prompt, or import a saved Atlas JSON file."
        case .idle where app.isFirstRun:
            return "Strength score is recomputed from every set after import (Epley, 100 = first session)."
        default:
            return nil
        }
    }
}

struct ImportStep: Identifiable, Hashable {
    enum State { case done, active, pending, empty }
    var title: String
    var detail: String
    var value: String
    var state: State = .pending
    var id: String { title }

    static let placeholders: [ImportStep] = [
        ImportStep(title: "Workouts", detail: "names, rest and flex days", value: "–"),
        ImportStep(title: "Exercises", detail: "targets, L/R and bodyweight flags", value: "–"),
        ImportStep(title: "Plan", detail: "weekly days or the cycle and its pointer", value: "–"),
        ImportStep(title: "Sessions", detail: "start and end times", value: "–"),
        ImportStep(title: "Sets", detail: "weights converted to kg for storage", value: "–"),
        ImportStep(title: "Overrides and extras", detail: "skips, swaps, borrowed exercises", value: "–"),
    ]
}

/// A 42 pt row: state mark, title (170 pt), detail, value (right-aligned mono).
private struct ImportStepRow: View {
    @Environment(\.thubanTheme) private var theme
    var step: ImportStep

    var body: some View {
        HStack(spacing: 14) {
            ImportStepMark(state: step.state)
            Text(step.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(step.state == .pending || step.state == .empty ? theme.inkDimColor : theme.inkColor)
                .frame(width: 170, alignment: .leading)
            Text(step.detail)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(step.value)
                .font(ThubanFont.mono(13.5))
                .foregroundStyle(step.state == .done ? theme.inkColor : theme.inkFaintColor)
                .frame(width: 120, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 42)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }
}

private struct ImportStepMark: View {
    @Environment(\.thubanTheme) private var theme
    var state: ImportStep.State

    var body: some View {
        Group {
            switch state {
            case .done:
                Circle().fill(theme.posSoftColor)
                    .overlay(Icon(.check, size: 13).foregroundStyle(theme.posTextColor))
            case .active:
                TimelineView(.animation) { context in
                    let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360
                    ZStack {
                        Circle().strokeBorder(theme.lineColor, lineWidth: 2)
                        Circle().trim(from: 0, to: 0.75)
                            .stroke(theme.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .padding(1)
                            .rotationEffect(.degrees(angle))
                    }
                }
            case .pending:
                Circle().strokeBorder(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            case .empty:
                Circle().fill(theme.panel2Color)
                    .overlay(Rectangle().fill(theme.inkFaintColor).frame(width: 8, height: 1.5))
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

/// An accent segment sliding along a `panel2` track while ssh runs.
private struct IndeterminateBar: View {
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        TimelineView(.animation) { context in
            GeometryReader { geometry in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let segment = geometry.size.width * 0.3
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.panel2Color)
                    Capsule().fill(theme.accentColor)
                        .frame(width: segment)
                        .offset(x: (geometry.size.width + segment) * t - segment)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Reading Atlas")
    }
}

// MARK: - Connection

private struct ImportConnectionGroup: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        SettingsGroup("Connection", caption: "The import signs in with your ssh key (no passwords are stored) and runs one SELECT inside a read-only transaction. Nothing is written to Atlas.") {
            HStack(alignment: .top, spacing: 12) {
                field(label: "ssh host", text: Binding(get: { app.preferences.atlasHost },
                                                       set: { app.preferences.atlasHost = $0.trimmingCharacters(in: .whitespaces) }),
                      prompt: Preferences.defaultAtlasHost, invalid: hostError != nil)
                    .frame(width: 220)
                field(label: "Atlas account email", text: Binding(get: { app.preferences.atlasEmail },
                                                                  set: { app.preferences.atlasEmail = $0.trimmingCharacters(in: .whitespaces) }),
                      prompt: Preferences.defaultAtlasEmail, invalid: emailError != nil)
                    .frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            .disabled(app.importPhase.isBusy)
            if let problem = hostError ?? emailError {
                SettingsNote(text: problem, tone: .negative)
            }
            HStack(spacing: 8) {
                Text(app.atlasImporter.commandDescription)
                    .font(ThubanFont.mono(12))
                    .foregroundStyle(theme.inkDimColor)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if app.preferences.atlasHost != Preferences.defaultAtlasHost || app.preferences.atlasEmail != Preferences.defaultAtlasEmail {
                    Button("Reset") {
                        app.preferences.atlasHost = Preferences.defaultAtlasHost
                        app.preferences.atlasEmail = Preferences.defaultAtlasEmail
                    }
                    .buttonStyle(GhostButtonStyle(height: 26, horizontalPadding: 8))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .accessibilityLabel("Command: \(app.atlasImporter.commandDescription)")
        }
    }

    private var hostError: String? {
        do { try AtlasImporter.validateHost(app.preferences.atlasHost); return nil } catch { return error.localizedDescription }
    }

    private var emailError: String? {
        do { try AtlasImporter.validateEmail(app.preferences.atlasEmail); return nil } catch { return error.localizedDescription }
    }

    private func field(label: String, text: Binding<String>, prompt: String, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(theme.inkDimColor)
            TextField(label, text: text, prompt: Text(prompt).foregroundStyle(theme.inkFaintColor))
                .labelsHidden()
                .autocorrectionDisabled()
                .thubanField(invalid: invalid, mono: true, height: 32)
                .accessibilityLabel(label)
        }
    }
}
