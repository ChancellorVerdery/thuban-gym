import SwiftUI
import ThubanGymCore

/// iPad (board IPad): a sidebar (mark, sections, the cycle), and the section on the right. While a session runs,
/// Today splits into the session's exercise list and the logger / rest timer side by side.
struct PadRoot: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var app = app
        NavigationSplitView(columnVisibility: $columns) {
            PadSidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 320)
                .toolbar(.hidden, for: .navigationBar)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder private var detail: some View {
        @Bindable var app = app
        switch app.padSection {
        case .today:
            if showsSession {
                PadSession()
            } else {
                NavigationStack(path: $app.todayPath) { TodayScreen().phoneDestinations() }
            }
        case .plan:
            NavigationStack(path: $app.planPath) { PlanScreen().phoneDestinations() }
        case .workouts:
            NavigationStack(path: $app.workoutsPath) { WorkoutsScreen().phoneDestinations() }
        case .progress:
            NavigationStack(path: $app.progressPath) { ProgressScreen().phoneDestinations() }
        case .settings:
            NavigationStack { SettingsSheet(embedded: true) }
        }
    }

    private var showsSession: Bool {
        if case .finished = app.sessionStage { return true }
        return app.sessionPresented || app.activeSession != nil
    }
}

struct PadSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppArtView(size: 30, theme: theme, ground: theme.panelColor)
                Text("Thuban Gym").font(PhoneFont.serif(26, relativeTo: .title2)).foregroundStyle(theme.inkColor)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 4) {
                ForEach(PadSection.allCases) { section in
                    row(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            if app.isCycle, !app.plan.cycle.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Cycle")
                    TodayCycleChips(plan: app.todayPlan, compact: true)
                    if let note = app.todayPlanNote() {
                        Text(note).font(.footnote).foregroundStyle(theme.inkDimColor).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor.ignoresSafeArea())
    }

    private func row(_ section: PadSection) -> some View {
        let selected = app.padSection == section
        return Button {
            if section == .settings || section != app.padSection { app.padSection = section }
            if section == .today, app.activeSession != nil { app.sessionPresented = true }
        } label: {
            HStack(spacing: 14) {
                Icon(section.icon, size: 22)
                    .foregroundStyle(selected ? theme.brassInkColor : theme.inkDimColor)
                Text(section.label)
                    .font(PhoneFont.sans(17, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? theme.brassInkColor : theme.inkColor)
                Spacer()
                if section == .today, app.activeSession != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(GymFormat.elapsed(app.sessionElapsed(now: context.date)))
                            .font(PhoneFont.mono(14, weight: .semibold))
                            .foregroundStyle(theme.brassInkColor)
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(selected ? theme.accentTintColor : .clear, in: RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// Today with a session on iPad: the exercise list (middle) and the logger or the rest timer (right).
struct PadSession: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var confirmFinish = false

    var body: some View {
        switch app.sessionStage {
        case .finished(let summary):
            FinishedView(summary: summary)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .background(theme.bgColor.ignoresSafeArea())
        default:
            GeometryReader { proxy in
            HStack(spacing: 0) {
                // Side by side when there is room (landscape); the header's exercise menu covers the rest.
                if proxy.size.width >= 760 {
                    list
                        .frame(width: min(380, proxy.size.width * 0.42))
                    Rectangle().fill(theme.lineColor).frame(width: 1).ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    SessionHeader(showsClose: false)
                    if app.sessionStage == .resting {
                        RestView(compact: true)
                    } else if let item = app.sessionExercise {
                        LoggingView(item: item)
                    } else {
                        SessionEmpty()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            }
            .background(theme.bgColor.ignoresSafeArea())
        }
    }

    private var list: some View {
        let items = app.sessionItems
        let current = app.sessionExercise?.id
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow("\(PhoneFormat.weekdayMonthDay(app.sessionDay))\(app.cyclePosition(on: app.sessionDay).map { " · Day \($0.index + 1) of \($0.count)" } ?? "")")
                    Text(app.sessionWorkout?.name ?? "Today")
                        .font(PhoneFont.serif(34, relativeTo: .largeTitle)).foregroundStyle(theme.inkColor)
                    Text(caption).font(.subheadline).foregroundStyle(theme.inkDimColor)
                    Card {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { RowDivider(inset: 0) }
                            Button {
                                app.focusedExerciseId = item.id
                                app.editingSet = nil
                                if app.sessionStage == .resting { app.endRest() }
                            } label: {
                                sessionRow(item, number: index + 1, isCurrent: item.id == current)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 16)
                }
                .padding(20)
            }
            if app.activeSession != nil {
                Button("Finish workout") { confirmFinish = true }
                    .buttonStyle(PhoneSecondaryStyle())
                    .padding(20)
                    .confirmationDialog("Finish \(app.sessionWorkout?.name ?? "the workout")?", isPresented: $confirmFinish, titleVisibility: .visible) {
                        Button("Finish workout") { app.finishWorkout() }
                        Button("Keep going", role: .cancel) {}
                    }
            } else {
                Button("Close") { app.minimizeSession() }
                    .buttonStyle(PhoneSecondaryStyle())
                    .padding(20)
            }
        }
    }

    private var caption: String {
        let progress = app.sessionProgress
        let start = app.activeSession.map { GymFormat.clock(ClockTime.string(from: $0.startedAt)) }
        return "\(progress.logged) of \(progress.planned) sets" + (start.map { " · started \($0)" } ?? "")
    }

    private func sessionRow(_ item: SessionExercise, number: Int, isCurrent: Bool) -> some View {
        let exercise = item.exercise
        let finished = SessionLogic.isFinished(app.data, exercise: exercise, on: app.sessionDay)
        let logged = SessionLogic.loggedSetCount(app.data, exercise: exercise, on: app.sessionDay)
        let today = app.session(exerciseId: exercise.id, on: app.sessionDay)
        return HStack(spacing: 14) {
            Group {
                if finished {
                    Icon(.check, size: 14, lineWidth: 2.2).foregroundStyle(theme.posTextColor)
                        .frame(width: 30, height: 30).background(theme.posSoftColor, in: Circle())
                } else if isCurrent {
                    Text("\(number)").font(PhoneFont.mono(14, weight: .semibold)).foregroundStyle(theme.onAccentColor)
                        .frame(width: 30, height: 30).background(theme.accentColor, in: Circle())
                } else {
                    Text(item.isExtra ? "+" : "\(number)").font(PhoneFont.mono(14, weight: .semibold)).foregroundStyle(theme.inkDimColor)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(theme.line2Color, style: StrokeStyle(lineWidth: 1, dash: item.isExtra ? [2, 2] : [])))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(exercise.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                    if item.isExtra { PhoneChip("Extra", kind: .warn) }
                }
                Text(isCurrent && !finished
                     ? "\(logged) of \(exercise.targetSpec?.sets ?? 0)\(today.map { " · " + PhoneFormat.session($0, unit: app.unit) } ?? "")"
                     : (today.map { PhoneFormat.session($0, unit: app.unit) } ?? (exercise.targetSpec?.display ?? exercise.target) + (exercise.unilateral ? " L / R" : "")))
                    .font(PhoneFont.mono(13)).foregroundStyle(theme.inkFaintColor).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 66)
        .background(isCurrent ? theme.accentTintColor : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}
