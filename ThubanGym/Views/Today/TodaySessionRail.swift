import SwiftUI
import ThubanGymCore

/// Today's right rail (360 pt, `panel`): Session (timer + Finish / Start / Resume), the Rest timer, "This session"
/// numbers and the Cycle (or week) strip with the next plan change. OWNER: Engineer A.
struct TodaySessionRail: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var plan: PlanDay
    var items: [SessionExercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            sessionBlock
            if showsRestTimer { TodayRestTimerBox(seconds: app.restSeconds(for: plan.workout?.id)) }
            if !items.isEmpty, plan.status != .skipped || app.todayProgress(items).logged > 0 { statsBlock }
            Spacer(minLength: 0)
            planBlock
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.leading, color: theme.lineColor)
    }

    /// Only while a session is running: before it starts, once it is finished and on a skipped day there is
    /// nothing to rest between.
    private var showsRestTimer: Bool {
        app.activeSession != nil && !items.isEmpty
    }

    // MARK: Session

    @ViewBuilder
    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Session")
            if let session = app.activeSession, session.date == app.sessionDay {
                running(session)
            } else if let receipt = app.lastFinish, receipt.completion.date == app.today {
                finished(receipt.completion, canResume: true)
            } else if let done = plan.completions.last(where: { !(app.workout($0.workoutId)?.isRest ?? false) }) {
                finished(done, canResume: false)
            } else if plan.status == .rest || plan.status == .restDone {
                restDay
            } else if plan.status == .skipped {
                note(big: "Skipped", line: plan.override?.note ?? "Enjoy the day off.")
            } else if let workout = plan.workout {
                notStarted(workout)
            } else {
                note(big: "Free day", line: "Nothing is planned. Swap in a workout to train.")
            }
        }
    }

    private func bigNumber(_ text: String) -> some View {
        Text(text)
            .font(ThubanFont.display(48))
            .foregroundStyle(theme.inkColor)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13.5))
            .foregroundStyle(theme.inkDimColor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func running(_ session: ActiveSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    bigNumber(GymFormat.elapsed(app.sessionElapsed(now: context.date)))
                    Text("elapsed").font(.system(size: 13)).foregroundStyle(theme.inkDimColor)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Session time \(GymFormat.elapsed(app.sessionElapsed(now: context.date))) elapsed")
            }
            .padding(.top, 8)
            .padding(.bottom, 2)
            line("Started \(GymFormat.clock(ClockTime.string(from: session.startedAt))) · your average is \(GymFormat.minutes(app.workoutDuration(session.workoutId)))")
            HStack(spacing: 8) {
                Button {
                    app.finishSession()
                    TodayRestClock.shared.stop()
                } label: {
                    HStack(spacing: 7) { TodayStopGlyph(size: 15); Text("Finish session") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(height: 38))
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Finish session (⌘↩)")
            }
            .padding(.top, 14)
            Button("Discard session") { app.discardSession() }
                .buttonStyle(GhostButtonStyle(height: 26, horizontalPadding: 0))
                .font(.system(size: 12.5))
                .padding(.top, 6)
                .help("Stop the timer without recording a completion. Logged sets stay.")
        }
    }

    private func finished(_ completion: Completion, canResume: Bool) -> some View {
        let workout = app.workout(completion.workoutId)
        var saved = "Saved"
        let range = GymFormat.clockRange(start: completion.start, end: completion.end)
        if !range.isEmpty { saved += " \(range.replacingOccurrences(of: " – ", with: "–"))" }
        if app.isCycle, let next = nextCycleWorkout {
            saved += " · cycle moves to \(next.name)"
        } else if let workout {
            saved += " · \(workout.name) done"
        }
        return VStack(alignment: .leading, spacing: 0) {
            bigNumber(completion.durationMinutes.map(GymFormat.minutes) ?? "Done")
                .padding(.top, 8)
                .padding(.bottom, 2)
            line(saved)
            if canResume {
                Button {
                    app.undoFinish()
                } label: {
                    HStack(spacing: 7) { Icon(.play, size: 15); Text("Resume session") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(height: 38))
                .padding(.top, 14)
            }
        }
    }

    /// The workout at the cycle pointer (what comes next once today is done).
    private var nextCycleWorkout: Workout? {
        guard app.isCycle, !app.plan.cycle.isEmpty else { return nil }
        return app.workout(app.plan.cycle[app.plan.normalizedPosition])
    }

    private func notStarted(_ workout: Workout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            bigNumber("0:00")
                .foregroundStyle(theme.inkFaintColor)
                .padding(.top, 8)
                .padding(.bottom, 2)
            line("Not started · \(workout.name) usually takes \(GymFormat.minutes(app.workoutDuration(workout.id)))")
            Button {
                app.startSession()
            } label: {
                HStack(spacing: 7) { Icon(.play, size: 15); Text("Start session") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(height: 38))
            .padding(.top, 14)
            .help("Starts the timer. Checking off a set starts it too.")
        }
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: 0) {
            bigNumber(plan.status == .restDone ? "Rested" : "Rest")
                .padding(.top, 8)
                .padding(.bottom, 2)
            line(plan.status == .restDone ? "Rest day recorded." : "Recovery day. It is marked done by itself at midnight.")
            if plan.status == .rest, let workout = plan.workout {
                Button {
                    app.complete(workoutId: workout.id)
                } label: {
                    HStack(spacing: 7) { Icon(.check, size: 15); Text("Mark rest done") }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(height: 38))
                .padding(.top, 14)
            }
        }
    }

    private func note(big: String, line text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            bigNumber(big).padding(.top, 8).padding(.bottom, 2)
            line(text)
        }
    }

    // MARK: This session

    private var statsBlock: some View {
        let progress = app.todayProgress(items)
        let ids = items.map(\.id)
        let volume = app.todayVolume(exerciseIds: ids, on: app.sessionDay)
        let lastVolume = plan.workout.flatMap { app.todayLastVolume(of: $0.id) }
        let best = app.todayBestLift(items)
        let score = app.strengthScore()
        let change = app.strengthChange(days: 28)
        return VStack(alignment: .leading, spacing: 0) {
            Eyebrow("This session").padding(.bottom, 4)
            statRow("Sets logged", value: "\(progress.logged) / \(progress.planned)")
            statRow("Volume", value: GymFormat.grouped(Int(app.unit.fromKilograms(volume).rounded())) + " \(app.unit.label)",
                    caption: lastVolume.map { "last \(plan.workout?.name ?? "session") \(GymFormat.grouped(Int(app.unit.fromKilograms($0.volume).rounded()))) \(app.unit.label)" },
                    tone: .faint)
            if let best {
                let delta = best.delta.map { app.unit.fromKilograms($0) }
                statRow("Best e1RM", value: "\(app.score(best.score, bodyweight: false)) \(app.unit.label)",
                        caption: "\(best.exercise.name)" + (delta.map { " · \(GymFormat.delta($0))" } ?? ""),
                        tone: Tone(delta.map { GymFormat.tone(for: $0) }))
            } else {
                statRow("Best e1RM", value: "—", caption: "log a weighted set", tone: .faint)
            }
            statRow("Strength score", value: score.map { String(format: "%.1f", $0) } ?? "—",
                    caption: change.map { "\(GymFormat.delta($0)) in 4 weeks" },
                    tone: Tone(change.map { GymFormat.tone(for: $0) }))
        }
    }

    private enum Tone {
        case faint, pos, neg, neutral
        init(_ tone: DeltaTone?) {
            switch tone {
            case .pos: self = .pos
            case .neg: self = .neg
            case .neutral: self = .neutral
            case nil: self = .faint
            }
        }
    }

    private func captionColor(_ tone: Tone) -> Color {
        switch tone {
        case .pos: return theme.toneTextColor(.pos)
        case .neg: return theme.toneTextColor(.neg)
        case .neutral: return theme.toneTextColor(.neutral)
        case .faint: return theme.inkFaintColor
        }
    }

    private func statRow(_ label: String, value: String, caption: String? = nil, tone: Tone = .faint) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.system(size: 14)).foregroundStyle(theme.inkDimColor)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(ThubanFont.mono(15, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                if let caption {
                    Text(caption)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(captionColor(tone))
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 11)
        .thubanHairline(.top, color: theme.lineColor)
        .accessibilityElement(children: .combine)
    }

    // MARK: Cycle / week

    @ViewBuilder
    private var planBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Eyebrow(app.isCycle ? "Cycle" : "This week")
                Spacer()
                Button("Plan") { app.section = .plan }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .accessibilityLabel("Open the plan")
            }
            .padding(.bottom, 10)
            if app.isCycle { cycleChips } else { weekChips }
            if let note = app.todayPlanNote() {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkDimColor)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private enum SlotState { case done, current, upcoming }

    private func slotChip(_ text: String, state: SlotState, help: String) -> some View {
        let fill: Color, ink: Color, border: Color
        switch state {
        case .done: (fill, ink, border) = (theme.posSoftColor, theme.posTextColor, .clear)
        case .current: (fill, ink, border) = (theme.accentTintColor, theme.brassInkColor, theme.accentColor)
        case .upcoming: (fill, ink, border) = (theme.panelColor, theme.inkDimColor, theme.line2Color)
        }
        return Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(fill, in: RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.chipRadius, style: .continuous).strokeBorder(border, lineWidth: ThubanMetrics.hairline))
            .help(help)
            .accessibilityLabel(help)
    }

    private var cycleChips: some View {
        let cycle = app.plan.cycle
        // Today's slot: the slot feeding today, else (today done / swapped) the slot just before the pointer.
        let pointer = app.plan.normalizedPosition
        let todayDone = plan.status == .done || plan.status == .restDone
        let current = plan.cycleIndex ?? (todayDone ? (pointer - 1 + cycle.count) % max(1, cycle.count) : pointer)
        return HStack(spacing: 6) {
            ForEach(Array(cycle.enumerated()), id: \.offset) { index, id in
                let name = app.workout(id)?.name ?? "?"
                let state: SlotState = index < current ? .done : (index == current ? (todayDone ? .done : .current) : .upcoming)
                slotChip(name, state: state, help: "Cycle day \(index + 1): \(name)")
            }
        }
    }

    private var weekChips: some View {
        let days = app.planDays(from: app.weekStart, count: 7)
        return HStack(spacing: 6) {
            ForEach(days) { day in
                let state: SlotState = day.isToday ? .current : ((day.status == .done || day.status == .restDone) ? .done : .upcoming)
                slotChip(String(day.date.weekday.short.prefix(3)), state: state,
                         help: "\(GymFormat.shortDay(day.date)): \(day.workout?.name ?? "nothing planned")")
            }
        }
    }
}

/// The rest timer card: clock, "Rest", remaining / total, and a `signal` progress line. Tap Start to run it by
/// hand; checking off a set starts it automatically.
struct TodayRestTimerBox: View {
    @Environment(\.thubanTheme) private var theme
    var seconds: Int
    private var clock: TodayRestClock { TodayRestClock.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = clock.remaining(at: context.date)
            let over = clock.isRunning && remaining <= 0
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TodayClockGlyph(size: 14)
                    Text(over ? "Rest done" : "Rest")
                    Spacer(minLength: 6)
                    Text(GymFormat.elapsed(clock.isRunning ? remaining.rounded(.up) : TimeInterval(seconds)))
                        .font(ThubanFont.mono(15))
                        .foregroundStyle(over ? theme.posTextColor : theme.inkColor)
                        .monospacedDigit()
                    Text("/ \(GymFormat.elapsed(TimeInterval(clock.isRunning ? clock.duration : seconds)))")
                        .font(ThubanFont.mono(13))
                        .foregroundStyle(theme.inkFaintColor)
                    Button(clock.isRunning ? "Stop" : "Start") {
                        if clock.isRunning { clock.stop() } else { clock.start(seconds: seconds) }
                    }
                    .buttonStyle(GhostButtonStyle(height: 24, horizontalPadding: 8))
                    .font(.system(size: 12.5, weight: .semibold))
                    .accessibilityLabel(clock.isRunning ? "Stop rest timer" : "Start rest timer")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkDimColor)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(theme.lineColor)
                        Capsule().fill(over ? theme.posColor : theme.signalColor)
                            .frame(width: geometry.size.width * clock.fraction(at: context.date))
                    }
                }
                .frame(height: 4)
                .padding(.top, 10)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rest timer")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.bgColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }
}
