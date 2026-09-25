import SwiftUI
import ThubanGymCore

/// Exercise history sheet (design: Exercise.dc.html, "Barbell Row history"), presented by the shell whenever
/// `app.presentedExerciseId` is set (from Today's "History" and Progress's "By exercise" rows).
/// OWNER: Engineer A (Today + Exercise sheet).
///
/// TODO: header (workout · target · n sessions, serif exercise name, e1RM / Top weight / Volume picker, Done),
/// Est. 1RM / First / Index / Next target tiles, the per-session chart, and the session table (Date, Weight,
/// Reps per set, Best e1RM, Volume, Best / Up 5 lb chips). Data: `app.history(exerciseId:)`,
/// `app.nextTarget(exerciseId:)`; bodyweight shows reps and "BW"; unilateral scores use the weaker side.
struct ExerciseHistorySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var exerciseId: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeader(eyebrow: app.workout(app.exercise(exerciseId)?.workoutId)?.name,
                           title: app.exercise(exerciseId)?.name ?? "Exercise",
                           subtitle: "\(app.history(exerciseId: exerciseId)?.sessions.count ?? 0) sessions")
                Button("Done") { dismiss() }
                    .buttonStyle(.thubanSecondary)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(24)
            Hairline()
            SectionPlaceholder(icon: .history, title: "History", todo: "The exercise history is being built. See ARCHITECTURE.md → Exercise sheet.")
        }
        .frame(width: 1040, height: 720)
        .background(theme.bgColor)
    }
}
