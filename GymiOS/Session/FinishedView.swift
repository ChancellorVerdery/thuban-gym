import SwiftUI
import ThubanGymCore

/// Workout finished (board Finished): the check, "Pull, 58 min", when and where the cycle goes next, four tiles
/// (sets, volume, best e1RM, strength score), highlights, "Review and edit sets" and Done.
struct FinishedView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var summary: WorkoutSummary

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Icon(.check, size: 26, lineWidth: 2)
                        .foregroundStyle(theme.posTextColor)
                        .frame(width: 60, height: 60)
                        .background(theme.posSoftColor, in: Circle())
                        .accessibilityHidden(true)
                        .padding(.top, 16)
                    Eyebrow("Workout complete · \(GymFormat.shortDay(summary.completion.date))")
                        .padding(.top, 20)
                    Text(title)
                        .font(PhoneFont.serif(34, relativeTo: .largeTitle))
                        .foregroundStyle(theme.inkColor)
                        .padding(.top, 4)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.subheadline).foregroundStyle(theme.inkDimColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    tiles.padding(.top, 20)
                    if !summary.highlights.isEmpty {
                        SectionHeading("Highlights").padding(.top, 22)
                        Card {
                            ForEach(Array(summary.highlights.enumerated()), id: \.offset) { index, highlight in
                                if index > 0 { RowDivider(inset: 60) }
                                highlightRow(highlight)
                            }
                        }
                    }
                }
                .padding(.horizontal, PhoneMetrics.gutter)
                .padding(.bottom, 16)
            }
            VStack(spacing: 4) {
                Button("Review and edit sets") { app.reviewFinishedSets() }
                    .buttonStyle(PhoneTextStyle())
                    .accessibilityHint("Reopens the session so sets can be changed; finish it again after")
                Button("Done") { app.closeFinished() }
                    .buttonStyle(PhonePrimaryStyle())
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.bottom, 8)
        }
    }

    private var title: String {
        let name = summary.workout?.name ?? "Workout"
        return summary.minutes.map { "\(name), \(GymFormat.minutes($0))" } ?? name
    }

    private var subtitle: String {
        var parts: [String] = []
        let range = GymFormat.clockRange(start: summary.completion.start, end: summary.completion.end)
        if !range.isEmpty { parts.append(range) }
        if let next = summary.nextWorkout, let date = summary.nextDate {
            parts.append("the cycle moves to \(next.name), \(GymFormat.shortDay(date))")
        }
        return parts.joined(separator: " · ")
    }

    private var tiles: some View {
        let unit = app.unit
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                tile("Sets", value: "\(summary.setsLogged)", suffix: summary.setsPlanned > 0 ? "/ \(summary.setsPlanned)" : nil,
                     caption: summary.setsPlanned > 0 && summary.setsLogged >= summary.setsPlanned ? "Every target set logged"
                        : "\(max(0, summary.setsPlanned - summary.setsLogged)) target sets skipped", tone: nil)
                tile("Volume", value: GymFormat.grouped(Int(unit.fromKilograms(summary.volume).rounded())), suffix: unit.label,
                     caption: summary.previousVolume.map { "\(PhoneFormat.signedGrouped(unit.fromKilograms(summary.volume - $0))) vs last \(summary.workout?.name ?? "time")" } ?? "First time",
                     tone: summary.previousVolume.map { GymFormat.tone(for: summary.volume - $0, decimals: 0) })
            }
            GridRow {
                tile("Best e1RM", value: summary.bestLift.map { app.score($0.score, bodyweight: false) } ?? "–",
                     suffix: summary.bestLift == nil ? nil : unit.label, caption: summary.bestLift?.exercise.name ?? "Bodyweight only", tone: nil)
                tile("Strength score", value: summary.strengthScore.map { String(format: "%.1f", $0) } ?? "–", suffix: nil,
                     caption: summary.strengthChange.map { "\(GymFormat.delta($0)) today" } ?? "Not enough history",
                     tone: summary.strengthChange.map { GymFormat.tone(for: $0) })
            }
        }
    }

    private func tile(_ label: String, value: String, suffix: String?, caption: String, tone: DeltaTone?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(PhoneFont.serif(30, relativeTo: .title1)).foregroundStyle(theme.inkColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let suffix {
                    Text(suffix).font(suffix.hasPrefix("/") ? PhoneFont.serif(20, relativeTo: .title3) : .footnote.weight(.medium))
                        .foregroundStyle(theme.inkFaintColor)
                }
            }
            Text(caption)
                .font(.footnote.weight(tone == nil ? .regular : .semibold))
                .foregroundStyle(tone.map { theme.toneTextColor($0) } ?? theme.inkDimColor)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func highlightRow(_ highlight: WorkoutSummary.Highlight) -> some View {
        let unit = app.unit
        switch highlight {
        case .newBest(let exercise, let set, let score, let gain):
            row(icon: .arrowUp, kind: .pos, title: "\(exercise.name), new e1RM best",
                detail: "\(GymFormat.set(set, unit: unit)) · \(app.score(score, bodyweight: false)) \(unit.label)" + (gain.map { ", \(GymFormat.delta(unit.fromKilograms($0)))" } ?? ""),
                mono: true, exerciseId: exercise.id)
        case .moreReps(let exercise, let sets, let total, let gain):
            row(icon: .arrowUp, kind: .pos, title: "\(exercise.name), \(total) total reps",
                detail: "\(PhoneFormat.sets(sets, unit: unit)) · +\(gain) reps", mono: true, exerciseId: exercise.id)
        case .targetHit(let exercise, let spec, let next):
            row(icon: .target, kind: .signal, title: "\(exercise.name) hit \(spec.display)",
                detail: next.map { "Next time the target is \(GymFormat.weightWithUnit($0, unit: unit))" } ?? "Next time add a rep",
                mono: false, exerciseId: exercise.id)
        }
    }

    private func row(icon: IconName, kind: ChipKind, title: String, detail: String, mono: Bool, exerciseId: String) -> some View {
        let colors = kind.colors(theme)
        return HStack(spacing: 14) {
            Icon(icon, size: 16)
                .foregroundStyle(colors.text)
                .frame(width: 32, height: 32)
                .background(colors.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                Text(detail).font(mono ? PhoneFont.mono(13) : .footnote).foregroundStyle(theme.inkDimColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 62)
        .accessibilityElement(children: .combine)
    }
}
