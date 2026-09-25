import SwiftUI
import ThubanGymCore

/// The workout library: serif "Workouts" + new-workout button, one row per workout (drag to reorder), and a
/// footer count.
struct WorkoutsSidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var selectedId: String?
    var onCreate: (String) -> Void
    @State private var pendingDelete: Workout?
    @State private var dropTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Workouts")
                    .font(ThubanFont.display(22))
                    .foregroundStyle(theme.inkColor)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: create) {
                    Icon(.plus, size: 16)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(theme.inkColor)
                        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                            .strokeBorder(theme.line2Color, lineWidth: ThubanMetrics.hairline))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New workout")
                .help("New workout")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(app.workouts.enumerated()), id: \.element.id) { index, workout in
                        WorkoutsSidebarRow(workout: workout, isSelected: workout.id == selectedId, isDropTarget: dropTarget == workout.id) {
                            app.selectedWorkoutId = workout.id
                        }
                        .draggable(WorkoutDrag.workoutPayload(workout.id)) {
                            Text(workout.name).font(ThubanFont.body(14, weight: .semibold))
                                .padding(.horizontal, 12).frame(height: 32)
                                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .dropDestination(for: String.self) { items, _ in
                            guard let id = items.first.flatMap(WorkoutDrag.workoutId) else { return false }
                            app.moveWorkout(id, to: index)
                            return true
                        } isTargeted: { targeted in
                            if targeted { dropTarget = workout.id } else if dropTarget == workout.id { dropTarget = nil }
                        }
                        .contextMenu {
                            Button("Duplicate") {
                                if let copy = app.duplicateWorkout(workout.id) { app.selectedWorkoutId = copy.id }
                            }
                            Button("Move up") { app.moveWorkout(workout.id, to: index - 1) }.disabled(index == 0)
                            Button("Move down") { app.moveWorkout(workout.id, to: index + 1) }.disabled(index == app.workouts.count - 1)
                            Divider()
                            Button("Delete…") { pendingDelete = workout }
                        }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)

            Spacer(minLength: 0)

            Text(footer)
                .font(ThubanFont.small)
                .foregroundStyle(theme.inkDimColor)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .thubanHairline(.top, color: theme.lineColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.panelColor)
        .thubanHairline(.trailing, color: theme.lineColor)
        .confirmsWorkoutDelete($pendingDelete)
    }

    private var footer: String {
        let ids = Set(app.workouts.map(\.id))
        let exercises = app.data.exercises.filter { ids.contains($0.workoutId) }.count
        let hasSpecial = app.workouts.contains { $0.kind != .training }
        let base = "\(AppModel.plural(exercises, "exercise")) across \(AppModel.plural(app.workouts.count, "workout"))."
        return hasSpecial ? base + " Rest and Flex days count toward the cycle but have no targets." : base
    }

    private func create() {
        let workout = app.addWorkout(name: "New workout")
        app.selectedWorkoutId = workout.id
        onCreate(workout.id)
    }
}

enum WorkoutDrag {
    static let workoutPrefix = "gym-workout:"
    static let exercisePrefix = "gym-exercise:"
    static func workoutPayload(_ id: String) -> String { workoutPrefix + id }
    static func exercisePayload(_ id: String) -> String { exercisePrefix + id }
    static func workoutId(_ payload: String) -> String? {
        payload.hasPrefix(workoutPrefix) ? String(payload.dropFirst(workoutPrefix.count)) : nil
    }
    static func exerciseId(_ payload: String) -> String? {
        payload.hasPrefix(exercisePrefix) ? String(payload.dropFirst(exercisePrefix.count)) : nil
    }
}

struct WorkoutsSidebarRow: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale
    var workout: Workout
    var isSelected: Bool
    var isDropTarget: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(workout.name)
                        .font(.system(size: 15 * textScale, weight: .semibold))
                        .foregroundStyle(theme.inkColor)
                    Text(subtitle)
                        .font(.system(size: 12.5 * textScale))
                        .foregroundStyle(theme.inkDimColor)
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                switch workout.kind {
                case .rest: Chip("Rest")
                case .flex: Chip("Flex", kind: .signal)
                case .training:
                    if !app.cycleSlots(of: workout.id).isEmpty {
                        Icon(.plan, size: 13).foregroundStyle(theme.inkFaintColor).help("In the cycle")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.accentTintColor : (hovering ? theme.panel2Color : .clear),
                        in: RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.controlRadius, style: .continuous)
                .strokeBorder(isDropTarget ? theme.accentColor : (isSelected ? theme.line2Color : .clear), lineWidth: ThubanMetrics.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(workout.name), \(subtitle)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var subtitle: String {
        let slots = app.cycleSlots(of: workout.id)
        let cycle = slots.isEmpty ? nil : "cycle \(slots.map(String.init).joined(separator: ", "))"
        let head: String
        switch workout.kind {
        case .rest: head = "Rest day"
        case .flex: head = "Log anything"
        case .training: head = AppModel.plural(app.exercises(in: workout.id).count, "exercise")
        }
        return [head, cycle].compactMap { $0 }.joined(separator: " · ")
    }
}
