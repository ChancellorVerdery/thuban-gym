import SwiftUI
import ThubanGymCore

/// The "…" button on Today: swap workout, skip today, add exercise.
struct TodayMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var plan: PlanDay
    @Binding var sheet: TodaySheet?

    var body: some View {
        Menu {
            Button("Swap workout…") { sheet = .swap }
            if plan.status == .skipped {
                Button("Undo skip") { app.clearOverride(date: app.today) }
            } else if app.activeSession == nil, plan.status != .done {
                Button("Skip today…") { sheet = .skip }
            }
            Button("Add exercise…") { sheet = .addExercise }
            if app.activeSession != nil {
                Divider()
                Button("Discard session", role: .destructive) { app.discardSession() }
            }
        } label: {
            Icon(.more, size: 24)
                .foregroundStyle(theme.brassInkColor)
                .frame(width: PhoneMetrics.hit, height: PhoneMetrics.hit)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Today options: swap workout, skip today, add exercise")
    }
}

/// The sheets behind the "…" menu.
struct TodaySheetView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var which: TodaySheet
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Group {
                switch which {
                case .swap: swapList
                case .addExercise: addList
                case .skip: skipForm
                }
            }
            .phoneScreen(theme)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents(which == .skip ? [.medium] : [.large])
        .presentationBackground(theme.bgColor)
    }

    // Swap: pick any workout for today.
    private var swapList: some View {
        let plannedId = app.planDay(app.today).plannedWorkout?.id ?? app.todayPlan.workout?.id
        return List {
            Section {
                ForEach(app.workouts) { workout in
                    Button {
                        dismiss()
                        if app.activeSession != nil || app.todayPlan.status == .done || app.todayPlan.status == .restDone {
                            app.swap(to: workout.id)
                        } else if workout.id == plannedId {
                            app.clearOverride(date: app.today)
                        } else {
                            app.swap(to: workout.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.name).font(.body.weight(.semibold)).foregroundStyle(theme.inkColor)
                                Text(workout.isRest ? "Rest day" : PhoneFormat.count(app.exercises(in: workout.id).count, "exercise"))
                                    .font(.subheadline).foregroundStyle(theme.inkDimColor)
                            }
                            Spacer()
                            if workout.id == app.todayPlan.workout?.id { PhoneChip("Today", kind: .accent) }
                        }
                    }
                    .listRowBackground(theme.panelColor)
                }
            } header: {
                Eyebrow("Do this today instead")
            } footer: {
                Text("A swap never moves the cycle. Finishing a workout that is in the cycle moves it past that workout.")
                    .font(.footnote).foregroundStyle(theme.inkDimColor)
            }
        }
        .phoneList(theme)
        .navigationTitle("Swap workout")
    }

    // Add exercise: pull one from another workout into today.
    private var addList: some View {
        let present = Set(app.sessionExercises(on: app.sessionDay).map(\.id))
        return List {
            ForEach(app.todayExtraCandidates(excluding: present), id: \.workout.id) { group in
                Section {
                    ForEach(group.exercises) { exercise in
                        Button {
                            app.addExtra(exerciseId: exercise.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(exercise.name).foregroundStyle(theme.inkColor)
                                Spacer()
                                Text(exercise.targetSpec?.display ?? exercise.target).font(PhoneFont.mono(13)).foregroundStyle(theme.inkFaintColor)
                            }
                        }
                        .listRowBackground(theme.panelColor)
                    }
                } header: {
                    Eyebrow(group.workout.name)
                }
            }
        }
        .phoneList(theme)
        .navigationTitle("Add exercise")
    }

    private var skipForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skip today").font(PhoneFont.serif(28, relativeTo: .title1)).foregroundStyle(theme.inkColor)
            Text("The cycle waits: \(app.todayPlan.workout?.name ?? "today's workout") moves to the next training day.")
                .font(.subheadline).foregroundStyle(theme.inkDimColor)
            TextField("Reason (optional)", text: $note)
                .font(.body)
                .padding(.horizontal, 14)
                .frame(minHeight: PhoneMetrics.rowHeight)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous).strokeBorder(theme.lineColor, lineWidth: 1))
            Button("Skip today") {
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                app.skip(note: trimmed.isEmpty ? nil : trimmed)
                dismiss()
            }
            .buttonStyle(PhonePrimaryStyle(height: PhoneMetrics.buttonHeight))
            Spacer()
        }
        .padding(PhoneMetrics.gutter)
    }
}
