import SwiftUI
import ThubanGymCore

struct PlanDayChange: Identifiable, Hashable {
    enum Mode: String, Hashable { case swap, skip }
    var date: DayKey
    var mode: Mode
    var id: String { "\(date.rawValue)|\(mode.rawValue)" }
}

/// Swap or skip one day: pick the day (next 60), what to do, an optional note.
struct PlanDayChangeSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var change: PlanDayChange

    @State private var date: Date = .now
    @State private var mode: PlanDayChange.Mode = .swap
    @State private var workoutId: String?
    @State private var note = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $date, in: app.today.date()...app.today.adding(days: 60).date(), displayedComponents: .date)
                        .foregroundStyle(theme.inkColor)
                        .listRowBackground(theme.panelColor)
                    PhoneSegmented(options: [(PlanDayChange.Mode.swap, "Swap"), (.skip, "Skip")], selection: $mode, accessibilityLabel: "Change")
                        .listRowBackground(theme.panelColor)
                } footer: {
                    Text(planned.map { "The plan has \($0.name) that day." } ?? "Nothing is planned that day.")
                        .font(.footnote).foregroundStyle(theme.inkDimColor)
                }
                if mode == .swap {
                    Section {
                        ForEach(app.workouts) { workout in
                            Button { workoutId = workout.id } label: {
                                HStack {
                                    Text(workout.name).foregroundStyle(theme.inkColor)
                                    Spacer()
                                    if workoutId == workout.id { Icon(.check, size: 16, lineWidth: 2).foregroundStyle(theme.brassInkColor) }
                                }
                            }
                            .listRowBackground(theme.panelColor)
                            .accessibilityAddTraits(workoutId == workout.id ? .isSelected : [])
                        }
                    } header: { Eyebrow("Do instead").textCase(nil).padding(.horizontal, -16) }
                }
                Section {
                    TextField("Note, e.g. Career fair", text: $note)
                        .listRowBackground(theme.panelColor)
                } footer: {
                    Text("Skips and swaps never move the cycle; the workouts after it wait a day.")
                        .font(.footnote).foregroundStyle(theme.inkDimColor)
                }
            }
            .phoneList(theme)
            .phoneScreen(theme)
            .navigationTitle(mode == .swap ? "Swap a day" : "Skip a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold).disabled(mode == .swap && workoutId == nil)
                }
            }
        }
        .presentationBackground(theme.bgColor)
        .onAppear {
            date = change.date.date()
            mode = change.mode
            workoutId = app.planDay(change.date).override?.workoutId
            note = app.planDay(change.date).override?.note ?? ""
        }
    }

    private var day: DayKey { DayKey.today(now: date) }
    private var planned: Workout? {
        let entry = app.planDay(day)
        return entry.plannedWorkout ?? entry.workout
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        app.override(date: day, workoutId: mode == .skip ? nil : workoutId, note: trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}

/// Edit the plan: the cycle's order (drag, remove, add, make next) or the weekly days.
struct PlanEditorSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if app.isCycle {
                    Section {
                        ForEach(Array(app.plan.cycle.enumerated()), id: \.offset) { index, id in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(PhoneFont.mono(14, weight: .semibold)).foregroundStyle(theme.inkDimColor).frame(width: 24)
                                Text(app.workout(id)?.name ?? "?").foregroundStyle(theme.inkColor)
                                Spacer()
                                if index == app.plan.normalizedPosition { PhoneChip("Next", kind: .accent) }
                            }
                            .frame(minHeight: 44)
                            .listRowBackground(theme.panelColor)
                            .swipeActions(edge: .leading) {
                                Button("Make next") { app.setCyclePosition(index) }.tint(theme.accentColor)
                            }
                        }
                        .onMove { from, to in
                            var order = app.plan.cycle
                            order.move(fromOffsets: from, toOffset: to)
                            app.setCycle(order)
                        }
                        .onDelete { offsets in
                            var order = app.plan.cycle
                            order.remove(atOffsets: offsets)
                            app.setCycle(order)
                        }
                        Menu {
                            ForEach(app.workouts) { workout in
                                Button(workout.name) { app.setCycle(app.plan.cycle + [workout.id]) }
                            }
                        } label: {
                            HStack(spacing: 10) { Icon(.plusCircle, size: 20); Text("Add a day") }
                                .foregroundStyle(theme.brassInkColor)
                                .frame(minHeight: 44)
                        }
                        .listRowBackground(theme.panelColor)
                    } header: {
                        Eyebrow("Cycle order").textCase(nil).padding(.horizontal, -16)
                    } footer: {
                        Text("Drag to reorder. Swipe right on a day to make it next; the pointer follows its workout when you reorder.")
                            .font(.footnote).foregroundStyle(theme.inkDimColor)
                    }
                } else {
                    Section {
                        ForEach(Weekday.allCases) { day in
                            PlanWeeklyRow(day: day).listRowBackground(theme.panelColor)
                        }
                    } header: {
                        Eyebrow("Every week").textCase(nil).padding(.horizontal, -16)
                    }
                }
            }
            .phoneList(theme)
            .phoneScreen(theme)
            .environment(\.editMode, .constant(app.isCycle ? .active : .inactive))
            .navigationTitle(app.isCycle ? "Edit cycle" : "Edit week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationBackground(theme.bgColor)
    }
}
