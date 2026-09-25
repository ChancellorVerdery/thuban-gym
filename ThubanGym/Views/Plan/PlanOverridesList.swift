import SwiftUI
import ThubanGymCore

/// "OVERRIDES · 2 UPCOMING": every skip / swap from today on, each with Undo.
struct PlanOverridesList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let overrides = app.upcomingOverrides
        PlanCard {
            Eyebrow(overrides.isEmpty ? "Overrides" : "Overrides · \(overrides.count) upcoming")
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            if overrides.isEmpty {
                PlanListNote(text: "No skips or swaps coming up. Use Skip a day or Swap a day; they never move the cycle.")
            } else {
                ForEach(overrides) { override in
                    PlanListRow(date: override.date,
                                chip: override.isSkip ? Chip("Skip", kind: .neg) : Chip("Swap", kind: .warn),
                                title: title(override),
                                detail: detail(override),
                                undoLabel: "Remove override for \(override.date.planShort)") {
                        app.clearOverride(date: override.date)
                    }
                }
            }
        }
    }

    private func title(_ override: PlanOverride) -> String {
        let day = app.planDay(override.date)
        if override.isSkip { return "Skip the day" }
        let name = app.workout(override.workoutId)?.name ?? "Deleted workout"
        if let planned = day.plannedWorkout, planned.id != override.workoutId { return "\(name) instead of \(planned.name)" }
        return name
    }

    /// The note, then where the displaced workout goes ("Pull moves to Wed").
    private func detail(_ override: PlanOverride) -> String? {
        var parts: [String] = []
        if let note = override.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { parts.append(note) }
        let day = app.planDay(override.date)
        if app.isCycle, let planned = day.plannedWorkout, !planned.isRest, planned.id != override.workoutId,
           let next = app.nextDate(of: planned.id, after: override.date) {
            let when = next.days(to: override.date) > -7 ? next.weekday.short : next.planShort
            parts.append("\(planned.name) moves to \(when)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ". ")
    }
}

/// "EXTRAS · TODAY": exercises pulled into a day from other workouts, each with Undo.
struct PlanExtrasList: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let extras = app.upcomingExtras
        let onlyToday = !extras.isEmpty && extras.allSatisfy { $0.date == app.today }
        PlanCard {
            Eyebrow(extras.isEmpty ? "Extras" : (onlyToday ? "Extras · today" : "Extras · \(extras.count) upcoming"))
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
            if extras.isEmpty {
                PlanListNote(text: "No extra exercises. Today → Add exercise pulls one in from another workout for a day.")
            } else {
                ForEach(extras) { extra in
                    let exercise = app.exercise(extra.exerciseId)
                    PlanListRow(date: extra.date,
                                chip: Chip("Extra", kind: .signal),
                                title: title(exercise),
                                detail: detail(exercise, extra: extra),
                                undoLabel: "Remove \(exercise?.name ?? "extra") from \(extra.date.planShort)") {
                        app.removeExtra(exerciseId: extra.exerciseId, date: extra.date)
                    }
                }
            }
        }
    }

    private func title(_ exercise: Exercise?) -> String {
        guard let exercise else { return "Deleted exercise" }
        guard let from = app.workout(exercise.workoutId) else { return exercise.name }
        return "\(exercise.name), from \(from.name)"
    }

    /// "3 × 12 added after Hammer Curl"
    private func detail(_ exercise: Exercise?, extra: PlanExtra) -> String? {
        guard let exercise else { return nil }
        let target = exercise.targetSpec?.display ?? exercise.target
        let session = app.sessionExercises(on: extra.date)
        let before = session.firstIndex { $0.exercise.id == exercise.id }.flatMap { $0 > 0 ? session[$0 - 1].exercise.name : nil }
        switch (target.isEmpty, before) {
        case (false, let name?): return "\(target) added after \(name)"
        case (false, nil): return "\(target) added to the session"
        case (true, let name?): return "Added after \(name)"
        case (true, nil): return nil
        }
    }
}

/// A list row: mono date, a kind chip, title + detail, Undo.
struct PlanListRow: View {
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var date: DayKey
    var chip: Chip
    var title: String
    var detail: String?
    var undoLabel: String
    var undo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(date.planShort)
                .font(ThubanFont.mono(13))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1)
            chip
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14.5 * textScale, weight: .semibold))
                    .foregroundStyle(theme.inkColor)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12.5 * textScale))
                        .foregroundStyle(theme.inkDimColor)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            PlanRowButton(title: "Undo", accessibility: undoLabel, action: undo)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .thubanHairline(.top, color: theme.lineColor)
    }
}

struct PlanListNote: View {
    @Environment(\.thubanTheme) private var theme
    var text: String

    var body: some View {
        Text(text)
            .font(ThubanFont.small)
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .thubanHairline(.top, color: theme.lineColor)
    }
}
