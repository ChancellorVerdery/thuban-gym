import SwiftUI
import ThubanGymCore

/// Rest timer (board Rest): the signal ring counting down, −15 s / +15 s, the set just logged with Undo, what is
/// next, and "Skip rest, start set 4". At 0:00 a haptic (on screen) and a local notification (in the background).
struct RestView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let now = context.date
            let countdown = app.rest
            let remaining = countdown?.remaining(at: now) ?? 0
            let done = remaining <= 0
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Eyebrow(done ? "Rest done" : "Rest", color: done ? theme.posTextColor : theme.inkDimColor)
                            .padding(.top, compact ? 8 : 20)
                        ring(fraction: countdown?.fractionRemaining(at: now) ?? 0, remaining: remaining, total: countdown?.total ?? 0)
                            .padding(.top, 14)
                        HStack(spacing: 12) {
                            Button("−15 s") { app.adjustRest(by: -15) }
                                .accessibilityLabel("15 seconds less")
                            Button("+15 s") { app.adjustRest(by: 15) }
                                .accessibilityLabel("15 seconds more")
                        }
                        .buttonStyle(PhoneSecondaryStyle(height: 52, font: PhoneFont.mono(17, relativeTo: .body, weight: .semibold)))
                        .padding(.top, 20)
                        summaryCard.padding(.top, 20)
                        HStack(alignment: .top, spacing: 10) {
                            Icon(.bell, size: 16).foregroundStyle(theme.inkFaintColor).padding(.top, 1)
                            Text(app.preferences.restAlert
                                 ? "A haptic and a notification at 0:00, so you hear it with the phone locked or in your pocket."
                                 : "The 0:00 alert is off (Settings ▸ During a workout).")
                                .font(.footnote).foregroundStyle(theme.inkDimColor)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 4)
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, PhoneMetrics.gutter)
                    .padding(.bottom, 16)
                }
                Button { app.endRest() } label: {
                    HStack(spacing: 10) {
                        Icon(.skip, size: 18)
                        Text(done ? "Start \(nextSetTitle.lowercasedFirst)" : "Skip rest, start \(nextSetTitle.lowercasedFirst)")
                    }
                }
                .buttonStyle(PhonePrimaryStyle())
                .padding(.horizontal, PhoneMetrics.gutter)
                .padding(.vertical, 8)
            }
        }
    }

    private func ring(fraction: Double, remaining: TimeInterval, total: TimeInterval) -> some View {
        let size: CGFloat = compact ? 200 : 270
        return ZStack {
            Circle().stroke(theme.line2Color, lineWidth: 10)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(theme.signalColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: fraction)
            VStack(spacing: 2) {
                Text(GymFormat.elapsed(remaining.rounded(.up)))
                    .font(PhoneFont.serif(compact ? 56 : 72, relativeTo: .largeTitle))
                    .foregroundStyle(theme.inkColor)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                Text("of \(GymFormat.elapsed(total))")
                    .font(PhoneFont.mono(15, relativeTo: .subheadline))
                    .foregroundStyle(theme.inkFaintColor)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest")
        .accessibilityValue("\(Int(remaining.rounded(.up))) seconds left of \(Int(total))")
    }

    // MARK: Logged + next

    private var summaryCard: some View {
        Card {
            if let last = app.lastLogged, let exercise = app.exercise(last.exerciseId) {
                HStack(spacing: 12) {
                    Icon(.check, size: 14, lineWidth: 2.2)
                        .foregroundStyle(theme.posTextColor)
                        .frame(width: 32, height: 32)
                        .background(theme.posSoftColor, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Set \(last.index + 1) logged\(last.side.map { ", \($0.label.lowercased())" } ?? "")")
                            .font(.subheadline).foregroundStyle(theme.inkDimColor)
                        Text(loggedLine(last, exercise: exercise))
                            .font(PhoneFont.mono(16, relativeTo: .body, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                    }
                    Spacer(minLength: 4)
                    Button("Undo") { app.undoLastSet() }
                        .buttonStyle(PhoneTextStyle())
                        .accessibilityLabel("Undo set \(last.index + 1)")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                RowDivider(inset: 0)
            }
            nextRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    @ViewBuilder private var nextRow: some View {
        if let item = app.sessionExercise, !allDone {
            let exercise = item.exercise
            let slots = SessionLogic.slots(app.data, exercise: exercise, on: app.sessionDay)
            let current = slots.first { $0.state == .current }
            let number = (current?.index ?? 0) + 1
            let isLast = exercise.targetSpec.map { number == $0.sets } ?? false
            let side = SessionLogic.nextSide(app.data, exercise: exercise, on: app.sessionDay)
            let draft = SessionLogic.suggestion(app.data, exercise: exercise, on: app.sessionDay, side: side)
            HStack(spacing: 12) {
                Text("\(number)")
                    .font(PhoneFont.mono(14, weight: .semibold))
                    .foregroundStyle(theme.brassInkColor)
                    .frame(width: 32, height: 32)
                    .background(theme.accentTintColor, in: Circle())
                    .overlay(Circle().strokeBorder(theme.accentColor, lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next · \(exercise.name)\(isLast ? ", last set" : "")")
                        .font(.subheadline).foregroundStyle(theme.inkDimColor).lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(GymFormat.weightWithUnit(draft.entry.weight, unit: app.unit)) × \(draft.reps)")
                            .font(PhoneFont.mono(16, relativeTo: .body, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                        if let previous = current?.previous {
                            Text("last \(GymFormat.set(previous, unit: app.unit))")
                                .font(PhoneFont.mono(14)).foregroundStyle(theme.inkFaintColor)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 12) {
                Icon(.target, size: 20).foregroundStyle(theme.posTextColor).frame(width: 32, height: 32)
                Text("Every target set is logged. Finish when you are done.")
                    .font(.subheadline).foregroundStyle(theme.inkDimColor)
                Spacer(minLength: 0)
            }
        }
    }

    private var allDone: Bool {
        app.sessionItems.allSatisfy { SessionLogic.isFinished(app.data, exercise: $0.exercise, on: app.sessionDay) }
    }

    private func loggedLine(_ last: LoggedSet, exercise: Exercise) -> String {
        let set = GymFormat.weightWithUnit(last.set.weight, unit: app.unit) + " × \(last.set.reps)"
        let score = Scoring.e1RM(last.set)
        return last.set.weight == nil ? set : "\(set) · e1RM \(app.score(score, bodyweight: false))"
    }

    private var nextSetTitle: String {
        guard let item = app.sessionExercise, !allDone else { return "Next set" }
        let slots = SessionLogic.slots(app.data, exercise: item.exercise, on: app.sessionDay)
        let number = (slots.first { $0.state == .current }?.index ?? 0) + 1
        return "Set \(number)"
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
