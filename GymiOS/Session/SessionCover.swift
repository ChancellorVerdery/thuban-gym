import SwiftUI
import ThubanGymCore
import UIKit

/// The full-screen session on iPhone (boards Logging, Rest, Finished, LoggingDark): a header with the workout clock
/// and the set progress, then the logger or the rest timer; the summary once the workout is finished.
struct SessionCover: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        Group {
            switch app.sessionStage {
            case .finished(let summary):
                FinishedView(summary: summary)
            case .resting:
                VStack(spacing: 0) {
                    SessionHeader()
                    RestView()
                }
            case .logging:
                VStack(spacing: 0) {
                    SessionHeader()
                    if let item = app.sessionExercise {
                        LoggingView(item: item)
                    } else {
                        SessionEmpty()
                    }
                }
            }
        }
        .background(theme.bgColor.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = app.preferences.keepScreenAwake }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: app.preferences.keepScreenAwake) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
    }
}

/// Chevron (minimize) · workout + clock · Finish, the segmented progress line, "6 of 20 sets" / "Exercise 2 of 6".
struct SessionHeader: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var showsClose = true
    @State private var confirmFinish = false

    var body: some View {
        let progress = app.sessionProgress
        let items = app.sessionItems
        let current = app.sessionExercise
        let currentIndex = items.firstIndex { $0.id == current?.id } ?? 0
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    Eyebrow(app.sessionWorkout?.name ?? "Session", color: theme.inkDimColor)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(app.activeSession == nil ? "Not started" : GymFormat.elapsed(app.sessionElapsed(now: context.date)))
                            .font(PhoneFont.mono(17, relativeTo: .headline, weight: .semibold))
                            .foregroundStyle(theme.inkColor)
                            .monospacedDigit()
                    }
                }
                .accessibilityElement(children: .combine)
                HStack {
                    if showsClose {
                        IconButton(.chevronDown, label: "Hide the session (it keeps running)") { app.minimizeSession() }
                            .padding(.leading, -8)
                    }
                    Spacer()
                    if app.activeSession != nil {
                        Button("Finish") { confirmFinish = true }
                            .buttonStyle(PhoneTextStyle())
                            .accessibilityHint("Ends the workout and records it")
                    }
                }
            }
            .frame(minHeight: PhoneMetrics.hit)

            HStack(spacing: 3) {
                ForEach(Array(progress.segments.enumerated()), id: \.offset) { index, segment in
                    let isCurrent = !segment.done && segment.exerciseId == current?.id
                        && progress.segments.firstIndex(where: { !$0.done && $0.exerciseId == current?.id }) == index
                    Capsule()
                        .fill(segment.done ? theme.posColor : (isCurrent ? theme.accentColor : theme.line2Color))
                        .frame(height: 4)
                }
            }
            .padding(.top, 12)
            .accessibilityHidden(true)

            HStack {
                Text("\(progress.logged) of \(progress.planned) sets")
                Spacer()
                Menu {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Button {
                            app.focusedExerciseId = item.id
                            app.editingSet = nil
                            if app.sessionStage == .resting { app.endRest() }
                        } label: {
                            let done = SessionLogic.isFinished(app.data, exercise: item.exercise, on: app.sessionDay)
                            Text("\(index + 1). \(item.exercise.name)\(done ? " — done" : "")")
                        }
                    }
                } label: {
                    Text(items.isEmpty ? "" : "Exercise \(currentIndex + 1) of \(items.count)")
                        .foregroundStyle(theme.inkDimColor)
                        .frame(minHeight: 28)
                }
                .accessibilityLabel("Exercise \(currentIndex + 1) of \(items.count). Choose another exercise")
            }
            .font(.subheadline)
            .foregroundStyle(theme.inkDimColor)
            .padding(.top, 4)
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.top, 4)
        .confirmationDialog("Finish \(app.sessionWorkout?.name ?? "the workout")?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish workout") { app.finishWorkout() }
            Button("Keep going", role: .cancel) {}
        } message: {
            let progress = app.sessionProgress
            Text(progress.logged >= progress.planned ? "Every target set is logged." : "\(progress.logged) of \(progress.planned) target sets are logged.")
        }
    }
}

/// A session with nothing to log (an empty flex day).
struct SessionEmpty: View {
    @Environment(\.thubanTheme) private var theme
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Icon(.today, size: 32).foregroundStyle(theme.inkFaintColor)
            Text("No exercises today. Add one from the Today menu.")
                .font(.subheadline).foregroundStyle(theme.inkDimColor).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(PhoneMetrics.gutter)
    }
}
