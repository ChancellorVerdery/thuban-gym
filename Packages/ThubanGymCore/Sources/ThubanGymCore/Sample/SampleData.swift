import Foundation

/// Realistic, deterministic sample data (the design's Push / Pull / Legs / Rest cycle, ~8 months of history in lb,
/// Pull in progress today, tomorrow skipped, a swap next week, an extra today). Used by the smoke run
/// (`THUBAN_GYM_SMOKE`) and `THUBAN_GYM_SEED=sample`; never written over real data.
public enum SampleData {
    /// Days of history before today.
    public static let historyDays = 234

    private struct Spec {
        var name: String
        var target: String
        /// First-session working weight in lb; nil = bodyweight.
        var startLb: Double?
        /// Total gain over the history, as a fraction.
        var gain: Double
        var unilateral: Bool = false
    }

    private static let plan: [(name: String, kind: WorkoutKind, specs: [Spec])] = [
        ("Push", .training, [
            Spec(name: "Bench Press", target: "4×5", startLb: 160, gain: 0.16),
            Spec(name: "Overhead Press", target: "3×8", startLb: 85, gain: 0.12),
            Spec(name: "Incline DB Press", target: "3×10", startLb: 50, gain: 0.2),
            Spec(name: "Triceps Pushdown", target: "3×12", startLb: 50, gain: 0.2),
            Spec(name: "Lateral Raise", target: "3×15", startLb: 15, gain: 0.33),
        ]),
        ("Pull", .training, [
            Spec(name: "Pull-up", target: "4×6–8", startLb: nil, gain: 0.33),
            Spec(name: "Barbell Row", target: "4×8", startLb: 125, gain: 0.12),
            Spec(name: "Single-arm DB Row", target: "3×10", startLb: 50, gain: 0.2, unilateral: true),
            Spec(name: "Face Pull", target: "3×15", startLb: 35, gain: 0.14),
            Spec(name: "Hammer Curl", target: "3×10", startLb: 25, gain: 0.2),
        ]),
        ("Legs", .training, [
            Spec(name: "Back Squat", target: "4×5", startLb: 185, gain: 0.22),
            Spec(name: "Romanian Deadlift", target: "3×8", startLb: 155, gain: 0.19),
            Spec(name: "Bulgarian Split Squat", target: "3×10", startLb: 30, gain: 0.33, unilateral: true),
            Spec(name: "Leg Curl", target: "3×12", startLb: 80, gain: 0.12),
            Spec(name: "Calf Raise", target: "3×15", startLb: 90, gain: 0.2),
        ]),
        ("Rest", .rest, []),
        ("Upper", .training, [
            Spec(name: "Rear Delt Fly", target: "3×12", startLb: 15, gain: 0.33),
            Spec(name: "DB Bench Press", target: "3×10", startLb: 55, gain: 0.15),
            Spec(name: "Seated Cable Row", target: "3×12", startLb: 100, gain: 0.15),
            Spec(name: "EZ-bar Curl", target: "3×12", startLb: 45, gain: 0.2),
            Spec(name: "Dip", target: "3×10", startLb: nil, gain: 0.3),
        ]),
        ("Lower", .training, [
            Spec(name: "Front Squat", target: "3×6", startLb: 135, gain: 0.15),
            Spec(name: "Hip Thrust", target: "3×10", startLb: 185, gain: 0.2),
            Spec(name: "Leg Press", target: "3×12", startLb: 270, gain: 0.15),
            Spec(name: "Walking Lunge", target: "3×12", startLb: 30, gain: 0.33, unilateral: true),
        ]),
        ("Flex", .flex, []),
    ]

    /// Builds the sample document for `today` with the running session started 31 minutes before `now`.
    public static func make(today: DayKey = .today(), now: Date = Date(), calendar: Calendar = .current) -> GymData {
        var rng = SeededRandom(seed: 0x7475_6261_6e67_796d)
        var data = GymData()
        data.settings = GymSettings(unit: .lbs, address: "Campus Recreation Center", hours: defaultHours(), defaultDuration: 60)

        var specsById: [String: Spec] = [:]
        for (index, entry) in plan.enumerated() {
            let workout = Workout(id: "gw-sample\(index + 1)", name: entry.name, rest: entry.kind == .rest, flex: entry.kind == .flex)
            data.workouts.append(workout)
            for (e, spec) in entry.specs.enumerated() {
                let exercise = Exercise(id: "ge-sample\(index + 1)-\(e + 1)", workoutId: workout.id, name: spec.name,
                                        unilateral: spec.unilateral, bodyweight: spec.startLb == nil, target: spec.target)
                data.exercises.append(exercise)
                specsById[exercise.id] = spec
            }
        }
        let push = data.workouts[0].id, pull = data.workouts[1].id, legs = data.workouts[2].id, rest = data.workouts[3].id
        let upper = data.workouts[4].id, lower = data.workouts[5].id
        data.plan = Plan(type: .cycle,
                         weekly: ["mon": push, "tue": pull, "wed": legs, "thu": rest, "fri": upper, "sat": lower, "sun": rest],
                         cycle: [push, pull, legs, rest], position: 0)

        // Walk the history through the cycle: rest slots auto-complete, ~7% of training days are missed, every
        // ~23rd training day is an Upper / Lower swap (not in the cycle, so the pointer stays).
        let first = today.adding(days: -historyDays)
        var trainingDays = 0
        for day in first.through(today.adding(days: -1)) {
            let slotId = data.plan.cycle[data.plan.normalizedPosition]
            guard let slot = data.workout(slotId) else { continue }
            if slot.isRest {
                data.complete(workoutId: slot.id, date: day, now: day.date(hour: 23, minute: 59, calendar: calendar), auto: true)
                continue
            }
            if rng.next() < 0.07 { continue }
            trainingDays += 1
            var workoutId = slot.id
            if trainingDays % 23 == 0 { workoutId = trainingDays % 46 == 0 ? lower : upper }
            let progress = Double(first.days(to: day)) / Double(historyDays)
            for exercise in data.exercises(in: workoutId) {
                guard let spec = specsById[exercise.id] else { continue }
                logSession(&data, exercise: exercise, spec: spec, date: day, progress: progress, rng: &rng)
            }
            let startMinutes = (day.weekday == .sat || day.weekday == .sun ? 10 * 60 + 30 : 17 * 60 + 10) + Int(rng.next() * 50) - 20
            let length = 52 + Int(rng.next() * 16)
            data.complete(workoutId: workoutId, date: day, start: ClockTime.string(minutes: startMinutes),
                          end: ClockTime.string(minutes: startMinutes + length),
                          now: day.date(hour: (startMinutes + length) / 60 % 24, minute: (startMinutes + length) % 60, calendar: calendar))
        }

        // Today: Pull in progress (pointer on Pull), a few sets logged, one extra pulled in from Upper.
        data.setCyclePosition(1)
        let started = now.addingTimeInterval(-31 * 60 - 12)
        data.activeSession = ActiveSession(workoutId: pull, date: today, startedAt: started)
        let pullExercises = data.exercises(in: pull)
        if let pullUp = pullExercises.first {
            for reps in [8, 8, 7, 7] { data.logSet(exerciseId: pullUp.id, date: today, weightKg: nil, reps: reps) }
        }
        if pullExercises.count > 1 {
            let row = pullExercises[1]
            for _ in 0..<2 { data.logSet(exerciseId: row.id, date: today, weightKg: WeightUnit.lbs.toKilograms(140), reps: 8) }
        }
        if let rearDelt = data.exercises(in: upper).first { data.addExtra(exerciseId: rearDelt.id, date: today) }

        // Tomorrow skipped, a swap next Tuesday-ish.
        data.setOverride(date: today.adding(days: 1), workoutId: nil, note: "Career fair at the student union, 10–3")
        data.setOverride(date: today.adding(days: 5), workoutId: upper, note: "TA office hours until 6")
        data.lastRollover = today
        for index in data.logs.indices { data.logs[index].id = "gl-sample\(index + 1)" } // deterministic ids
        return data
    }

    private static func logSession(_ data: inout GymData, exercise: Exercise, spec: Spec, date: DayKey, progress: Double, rng: inout SeededRandom) {
        guard let targetSpec = TargetSpec(spec.target) else { return }
        // A mid-history deload dip (weeks 13–14) so charts are not straight lines.
        let dip = (0.52...0.58).contains(progress) ? 0.9 : 1
        let sides: [Side?] = spec.unilateral ? [.left, .right] : [nil]
        for side in sides {
            for set in 0..<targetSpec.sets {
                let fatigue = set >= targetSpec.sets - 1 && rng.next() < 0.45 ? 1 : 0
                if let startLb = spec.startLb {
                    var pounds = startLb * (1 + spec.gain * progress) * dip
                    if side == .right { pounds *= 1.04 }
                    pounds = (pounds / 5).rounded() * 5
                    let reps = max(1, targetSpec.repsHigh - fatigue - (rng.next() < 0.2 ? 1 : 0))
                    data.logSet(exerciseId: exercise.id, date: date, side: side, weightKg: WeightUnit.lbs.toKilograms(pounds), reps: reps)
                } else {
                    let base = Double(targetSpec.repsLow) * (1 + spec.gain * progress)
                    let reps = max(1, Int(base.rounded()) - fatigue)
                    data.logSet(exerciseId: exercise.id, date: date, side: side, weightKg: nil, reps: reps)
                }
            }
        }
    }

    private static func defaultHours() -> [String: OpeningHours] {
        var hours: [String: OpeningHours] = [:]
        for day in Weekday.allCases {
            switch day {
            case .sat, .sun: hours[day.rawValue] = OpeningHours(open: "07:00", close: "19:00")
            case .fri: hours[day.rawValue] = OpeningHours(open: "05:00", close: "22:00")
            default: hours[day.rawValue] = OpeningHours(open: "05:00", close: "23:00")
            }
        }
        return hours
    }
}

/// SplitMix64 → [0, 1). Deterministic across runs and platforms.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
