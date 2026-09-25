import SwiftUI
import ThubanGymCore

/// Plan section (Plan.dc.html). OWNER: Engineer B (Plan + Workouts).
///
/// Header (Plan · cycle of n, the cycle's names, the pointer rule) with the Weekly / Cycle switch; the 14-day strip;
/// then the active plan's editor on the left (Cycle order, or the weekday editor) and, on the right, upcoming
/// overrides, extras, and the other plan type (saved, not active).
struct PlanView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            PlanStrip()
            GeometryReader { proxy in
                let left = (proxy.size.width - 18) / 2.25
                HStack(alignment: .top, spacing: 18) {
                    Group {
                        if app.isCycle { PlanCycleEditor() } else { PlanWeeklyEditor() }
                    }
                    .frame(width: left)
                    .frame(maxHeight: .infinity, alignment: .top)

                    ScrollView {
                        VStack(spacing: 18) {
                            PlanOverridesList()
                            PlanExtrasList()
                            if app.isCycle { PlanWeeklyPreview() } else { PlanCyclePreview() }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.never)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(minHeight: 300)
        }
        .padding(.horizontal, 32)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bgColor)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 20) {
            PageHeader(eyebrow: eyebrow, title: title, subtitle: subtitle)
            VStack(alignment: .trailing, spacing: 6) {
                PlanControlCaption("Plan type")
                SegmentedPicker(
                    selection: Binding(get: { app.plan.type }, set: { app.setPlanType($0) }),
                    options: [SegmentOption(PlanType.weekly, "Weekly"), SegmentOption(PlanType.cycle, "Cycle", icon: .plan)],
                    segmentHeight: 28
                )
                .accessibilityLabel("Plan type")
            }
        }
    }

    private var eyebrow: String {
        app.isCycle ? "Plan · cycle of \(app.plan.cycle.count)" : "Plan · weekly"
    }

    private var title: String {
        if app.isCycle {
            let names = app.plan.cycle.compactMap { app.workout($0)?.name }
            return names.isEmpty ? "No cycle yet" : names.joined(separator: ", ")
        }
        var seen = Set<String>()
        let names = Weekday.allCases.compactMap { app.workout(app.plan.weeklyWorkoutId($0)) }
            .filter { !$0.isRest && seen.insert($0.id).inserted }
            .map(\.name)
        return names.isEmpty ? "No weekly plan yet" : names.joined(separator: ", ")
    }

    private var subtitle: String {
        app.isCycle
            ? "The cycle advances only when you finish a workout in it. Skips, swaps and extras never move it."
            : "Each weekday keeps its workout. Skips, swaps and extras change a single date."
    }
}
