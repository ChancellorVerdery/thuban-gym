import SwiftUI
import ThubanGymCore

/// Exercise history (board Exercise): e1RM now, the change and index, the chart, the next target, and every session
/// (newest first, bests marked). The "…" menu edits the exercise.
struct ExerciseHistoryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var exerciseId: String
    var backTitle: String? = "Progress"
    @State private var editing = false

    var body: some View {
        Group {
            if let exercise = app.exercise(exerciseId) {
                content(exercise, history: app.history(exerciseId: exerciseId))
            } else {
                Text("This exercise was deleted.").font(.subheadline).foregroundStyle(theme.inkDimColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .phoneScreen(theme)
        .navigationTitle(app.exercise(exerciseId)?.name ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit exercise…") { editing = true }
                } label: {
                    Icon(.more, size: 24).foregroundStyle(theme.brassInkColor)
                        .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                }
                .accessibilityLabel("Exercise options")
            }
        }
        .sheet(isPresented: $editing) {
            if let exercise = app.exercise(exerciseId) {
                ExerciseEditSheet(workoutId: exercise.workoutId, exerciseId: exercise.id)
                    .phoneChrome()
            }
        }
    }

    private func content(_ exercise: Exercise, history: ExerciseHistory?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(eyebrow(exercise, history: history))
                if let history, let latest = history.latest {
                    headline(history, latest: latest)
                    Card(padding: 14) {
                        StrengthChart(points: history.sessions.map { ChartPoint(date: $0.date, value: app.unit.fromKilogramsIfWeighted($0.score, bodyweight: history.isBodyweight)) },
                                      baseline: nil, showsPoints: history.sessions.count <= 40, showsYLabels: true)
                            .frame(height: 140)
                    }
                    .padding(.top, 14)
                    if let target = app.nextTarget(exerciseId: exerciseId) {
                        nextTarget(target, history: history).padding(.top, 12)
                    }
                    SectionHeading("Sessions") {
                        Text(history.isBodyweight ? "reps" : "\(app.unit.label) × reps · e1RM").font(.footnote).foregroundStyle(theme.inkFaintColor)
                    }
                    .padding(.top, 22)
                    sessions(history)
                } else {
                    Text("Nothing logged yet. It shows up here after the first session.")
                        .font(.subheadline).foregroundStyle(theme.inkDimColor).padding(.top, 12)
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func eyebrow(_ exercise: Exercise, history: ExerciseHistory?) -> String {
        var parts = [app.workout(exercise.workoutId)?.name ?? "Exercise"]
        if let spec = exercise.targetSpec { parts.append(spec.display) }
        if let history, let first = history.first {
            parts.append("\(PhoneFormat.count(history.sessions.count, "session")) since \(GymFormat.monthDay(first.date))")
        }
        return parts.joined(separator: " · ")
    }

    private func headline(_ history: ExerciseHistory, latest: ExerciseSession) -> some View {
        let bodyweight = history.isBodyweight
        let previous = history.sessions.dropLast().last
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bodyweight ? "\(Int(latest.score.rounded()))" : String(format: "%.1f", app.unit.fromKilograms(latest.score)))
                    .font(PhoneFont.serif(56, relativeTo: .largeTitle))
                    .kerning(-1)
                    .foregroundStyle(theme.inkColor)
                Text(bodyweight ? "reps, best set" : "\(app.unit.label) e1RM").font(.body.weight(.medium)).foregroundStyle(theme.inkDimColor)
            }
            HStack(spacing: 0) {
                if let previous {
                    let delta = latest.score - previous.score
                    Text(bodyweight ? "\(delta >= 0 ? "+" : "−")\(Int(abs(delta).rounded())) vs last" : "\(GymFormat.delta(app.unit.fromKilograms(delta))) vs last")
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.toneTextColor(GymFormat.tone(for: delta)))
                    Text(" · ").foregroundStyle(theme.inkDimColor)
                }
                Text("index \(String(format: "%.1f", latest.index))").foregroundStyle(theme.inkDimColor)
                if let first = history.first {
                    Text(" · first \(app.score(first.score, bodyweight: bodyweight))").foregroundStyle(theme.inkDimColor)
                }
            }
            .font(.subheadline)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    private func nextTarget(_ target: NextTarget, history: ExerciseHistory) -> some View {
        let weight = target.weightKg.map { app.weightWithUnit($0) }
        let head = weight.map { "Next time \($0) × \(target.reps)." } ?? "Next time \(target.reps) reps a set."
        let why: String
        if target.increase, let top = history.latest?.topWeight {
            why = " All \(target.sets == 4 ? "four" : "\(target.sets)") sets hit \(history.exercise.targetSpec?.repsHigh ?? target.reps) at \(app.weight(top))."
        } else if history.isBodyweight {
            why = " One more rep than your best set."
        } else {
            why = " Aim for \(target.reps) on every set, then add \(GymFormat.weightWithUnit(target.incrementKg, unit: app.unit))."
        }
        return HStack(alignment: .top, spacing: 12) {
            Icon(.arrowUp, size: 18).foregroundStyle(theme.signalTextColor).padding(.top, 2)
            (Text(head).fontWeight(.semibold).foregroundColor(theme.inkColor) + Text(why).foregroundColor(theme.inkDimColor))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(theme.signalSoftColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func sessions(_ history: ExerciseHistory) -> some View {
        let newestFirst = Array(history.sessions.reversed())
        let top = history.sessions.map(\.score).max()
        let bestId = history.sessions.last { top != nil && abs($0.score - top!) < 1e-9 }?.id
        return Card {
            ForEach(Array(newestFirst.prefix(60).enumerated()), id: \.element.id) { index, session in
                if index > 0 { RowDivider() }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(GymFormat.shortDay(session.date)).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                            if session.id == bestId { PhoneChip("Best", kind: .pos) }
                        }
                        Text(PhoneFormat.session(session, unit: app.unit)).font(PhoneFont.mono(14)).foregroundStyle(theme.inkDimColor)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Text(history.isBodyweight ? "\(session.totalReps)" : String(format: "%.1f", app.unit.fromKilograms(session.score)))
                        .font(PhoneFont.mono(16, relativeTo: .body))
                        .foregroundStyle(session.id == bestId ? theme.posTextColor : theme.inkColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(minHeight: 60)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

extension WeightUnit {
    /// A score in the display unit (bodyweight scores are reps and stay as they are).
    func fromKilogramsIfWeighted(_ value: Double, bodyweight: Bool) -> Double { bodyweight ? value : fromKilograms(value) }
}
