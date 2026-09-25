import SwiftUI
import ThubanGymCore

/// Plan (board Plan): weekly / cycle, the cycle's slots (done · now · next), and the next seven days — swipe a day
/// to Skip or Swap it (or Restore a changed day). "+" changes any day; "Edit" / "Reorder" edit the plan itself.
struct PlanScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var changing: PlanDayChange?
    @State private var editing = false

    var body: some View {
        let days = app.planDays(from: app.today, count: 7)
        List {
            Section {
                PhoneSegmented(options: [(PlanType.weekly, "Weekly"), (PlanType.cycle, "Cycle")],
                               selection: Binding(get: { app.plan.type }, set: { app.setPlanType($0) }),
                               accessibilityLabel: "Plan type")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            if app.isCycle {
                Section {
                    PlanCycleSlots()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    header(app.plan.cycle.isEmpty ? "Cycle" : "Cycle · \(app.plan.cycle.count) days") {
                        Button("Reorder") { editing = true }.buttonStyle(PhoneTextStyle(weight: .regular, size: 17))
                    }
                } footer: {
                    Text("The cycle moves on only when you finish a workout in it. Skips, swaps and extras never move it.")
                        .font(.subheadline).foregroundStyle(theme.inkDimColor)
                        .padding(.horizontal, -16)
                }
            } else {
                Section {
                    ForEach(Weekday.allCases) { day in
                        PlanWeeklyRow(day: day).listRowBackground(theme.panelColor)
                    }
                } header: {
                    header("Every week") { EmptyView() }
                }
            }

            Section {
                ForEach(days) { day in
                    PlanDayRow(day: day, moved: moved(day, in: days))
                        .listRowBackground(theme.panelColor)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if day.override != nil {
                                Button("Restore") { app.clearOverride(date: day.date) }
                                    .tint(theme.inkFaintColor)
                            } else if day.status != .done && day.status != .restDone && day.status != .inProgress {
                                Button { app.skip(date: day.date) } label: { swipeLabel("Skip", icon: .skip) }
                                    .tint(theme.negColor)
                                Button { changing = PlanDayChange(date: day.date, mode: .swap) } label: { swipeLabel("Swap", icon: .swap) }
                                    .tint(theme.accentColor)
                            }
                        }
                        .contextMenu {
                            Button("Swap…") { changing = PlanDayChange(date: day.date, mode: .swap) }
                            if day.override != nil {
                                Button("Restore the plan") { app.clearOverride(date: day.date) }
                            } else {
                                Button("Skip…") { changing = PlanDayChange(date: day.date, mode: .skip) }
                            }
                        }
                }
            } header: {
                header("Next 7 days") {
                    Text("Swipe a day to change it").font(.subheadline).foregroundStyle(theme.inkFaintColor).textCase(nil)
                }
            }
        }
        .phoneList(theme)
        .phoneScreen(theme)
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                IconButton(.plus, label: "Change a day") { changing = PlanDayChange(date: app.today.adding(days: 1), mode: .swap) }
                Button("Edit") { editing = true }
            }
        }
        .sheet(item: $changing) { change in
            PlanDayChangeSheet(change: change)
                .phoneChrome()
        }
        .sheet(isPresented: $editing) {
            PlanEditorSheet()
                .phoneChrome()
        }
    }

    private func header<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Eyebrow(title)
            Spacer()
            trailing()
        }
        .padding(.horizontal, -16)
        .textCase(nil)
    }

    private func swipeLabel(_ text: String, icon: IconName) -> some View {
        Label { Text(text) } icon: { Image(uiImage: TabIcon.image(icon)) }
    }

    /// The day right after a changed day that now does the workout the changed day had planned ("moved").
    private func moved(_ day: PlanDay, in days: [PlanDay]) -> Bool {
        guard day.override == nil, let index = days.firstIndex(of: day), index > 0 else { return false }
        let previous = days[index - 1]
        guard previous.override != nil, let planned = previous.plannedWorkout else { return false }
        return day.workout?.id == planned.id
    }
}

/// The cycle's slots as small cards: "1 · done / Push", "2 · now / Pull", "3 / Legs" …
struct PlanCycleSlots: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        let cycle = app.plan.cycle
        let plan = app.todayPlan
        let pointer = app.plan.normalizedPosition
        let todayDone = plan.status == .done || plan.status == .restDone
        let current = plan.cycleIndex ?? (todayDone ? (pointer - 1 + cycle.count) % max(1, cycle.count) : pointer)
        if cycle.isEmpty {
            Text("No cycle yet. Tap Edit to add workouts in order.")
                .font(.subheadline).foregroundStyle(theme.inkDimColor)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(cycle.enumerated()), id: \.offset) { index, id in
                        let done = index < current || (index == current && todayDone)
                        let now = index == current && !todayDone
                        slot(index: index, name: app.workout(id)?.name ?? "?", done: done, now: now)
                    }
                }
            }
            .scrollDisabled(cycle.count <= 4)
        }
    }

    private func slot(index: Int, name: String, done: Bool, now: Bool) -> some View {
        let fill = done ? theme.posSoftColor : (now ? theme.accentTintColor : theme.panelColor)
        let ink = done ? theme.posTextColor : (now ? theme.brassInkColor : theme.inkColor)
        let border = done ? Color.clear : (now ? theme.accentColor : theme.line2Color)
        return VStack(alignment: .leading, spacing: 2) {
            Text(done ? "\(index + 1) · done" : (now ? "\(index + 1) · now" : "\(index + 1)"))
                .font(PhoneFont.mono(12, relativeTo: .caption1))
                .foregroundStyle(done || now ? ink : theme.inkFaintColor)
            Text(name).font(.body.weight(.semibold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minWidth: 80, maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .containerRelativeFrame(.horizontal, count: 4, spacing: 8)
        .background(fill, in: RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous).strokeBorder(border, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cycle day \(index + 1), \(name)\(done ? ", done" : now ? ", now" : "")")
    }
}

/// One of the next seven days.
struct PlanDayRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var day: PlanDay
    var moved: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(GymFormat.shortDay(day.date))
                .font(.body)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .leading)
            name
            Spacer(minLength: 4)
            trailing
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var name: some View {
        switch day.status {
        case .skipped:
            Text(day.plannedWorkout?.name ?? day.workout?.name ?? "Skipped")
                .font(.body.weight(.semibold)).strikethrough().foregroundStyle(theme.inkFaintColor)
        case .rest, .restDone, .empty:
            Text(day.workout?.name ?? "Nothing").font(.body).foregroundStyle(theme.inkDimColor)
        default:
            Text(day.workout?.name ?? "Nothing").font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
        }
    }

    @ViewBuilder private var trailing: some View {
        HStack(spacing: 8) {
            if let note = day.override?.note, !note.isEmpty {
                Text(AppModel.todayShortNote(note).capitalizedFirst).font(.subheadline).foregroundStyle(theme.inkDimColor).lineLimit(1)
            }
            switch day.status {
            case .skipped: PhoneChip("Skip", kind: .neg)
            case .swapped:
                if let planned = day.plannedWorkout, day.override?.note == nil {
                    Text("\(planned.name) moves").font(.subheadline).foregroundStyle(theme.inkDimColor).lineLimit(1)
                }
                PhoneChip("Swap", kind: .warn)
            case .done, .restDone: PhoneChip("Done", kind: .pos)
            case .inProgress: PhoneChip("Now", kind: .accent)
            default:
                if moved { Text("moved").font(.subheadline).foregroundStyle(theme.inkFaintColor) }
            }
            if day.isToday, day.status != .inProgress { PhoneChip("Today", kind: .warn) }
            if !day.extraExerciseIds.isEmpty { PhoneChip("+\(day.extraExerciseIds.count) extra", kind: .signal) }
        }
    }
}

/// Weekly plan: one weekday and its workout (tap to choose).
struct PlanWeeklyRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var day: Weekday

    var body: some View {
        let current = app.workout(app.plan.weeklyWorkoutId(day))
        Menu {
            Button("Nothing") { app.setWeekly(day, workoutId: nil) }
            ForEach(app.workouts) { workout in
                Button(workout.name) { app.setWeekly(day, workoutId: workout.id) }
            }
        } label: {
            HStack {
                Text(day.name).foregroundStyle(theme.inkColor)
                Spacer()
                Text(current?.name ?? "Nothing").foregroundStyle(current == nil ? theme.inkFaintColor : theme.inkDimColor)
                Icon(.reorder, size: 14).foregroundStyle(theme.inkFaintColor)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("\(day.name): \(current?.name ?? "nothing"). Choose a workout")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
