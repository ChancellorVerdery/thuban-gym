import Foundation
import ThubanGymCore

/// Text the iPhone screens share (on top of the core's `GymFormat`).
enum PhoneFormat {
    /// "Thursday, Sep 24".
    static func weekdayMonthDay(_ day: DayKey) -> String {
        "\(day.weekday.name), \(GymFormat.monthDay(day))"
    }

    /// Sets in the display unit: "135 × 8, 8, 8, 7" when the weight is the same throughout, otherwise
    /// "132.5 × 8, 135 × 8"; "BW 8, 8, 7, 7" for bodyweight.
    static func sets(_ sets: [SetEntry], unit: WeightUnit) -> String {
        guard let first = sets.first else { return "" }
        if sets.allSatisfy({ $0.weight == nil }) { return "BW " + sets.map { String($0.reps) }.joined(separator: ", ") }
        if sets.allSatisfy({ $0.weight == first.weight }) {
            return "\(GymFormat.weight(first.weight, unit: unit)) × " + sets.map { String($0.reps) }.joined(separator: ", ")
        }
        return sets.map { GymFormat.set($0, unit: unit) }.joined(separator: ", ")
    }

    /// A unilateral session: "L 60 × 10, 10 · R 60 × 10, 9" (or the plain form when logged without sides).
    static func session(_ session: ExerciseSession, unit: WeightUnit) -> String {
        if !session.left.isEmpty || !session.right.isEmpty {
            var parts: [String] = []
            if !session.left.isEmpty { parts.append("L " + sets(session.left, unit: unit)) }
            if !session.right.isEmpty { parts.append("R " + sets(session.right, unit: unit)) }
            if !session.sets.isEmpty { parts.append(sets(session.sets, unit: unit)) }
            return parts.joined(separator: " · ")
        }
        return sets(session.sets, unit: unit)
    }

    /// "2:00" for a rest length in seconds.
    static func rest(_ seconds: Int) -> String { GymFormat.elapsed(TimeInterval(seconds)) }

    /// "1 exercise" / "5 exercises".
    static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

    /// "10,345 lb" for a volume in kg.
    static func volume(_ kg: Double, unit: WeightUnit) -> String {
        "\(GymFormat.grouped(Int(unit.fromKilograms(kg).rounded()))) \(unit.label)"
    }

    /// Signed whole number with grouping: "+1,155", "−40".
    static func signedGrouped(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n == 0 { return "0" }
        return (n > 0 ? "+" : "−") + GymFormat.grouped(abs(n))
    }

    /// "7 workouts, 1,240 sets in 169 sessions, Feb 4 – Sep 25".
    static func contents(_ contents: GymTransfer.Contents) -> String {
        var text = "\(count(contents.workouts, "workout")), \(count(contents.sets, "set")) in \(count(contents.sessions, "session"))"
        if let first = contents.firstDay, let last = contents.lastDay {
            text += ", \(GymFormat.monthDay(first)) – \(GymFormat.monthDay(last))"
        }
        if contents.format == "atlas" { text += " (an Atlas export)" }
        return text
    }

    /// A display-unit weight for a text field: "140", "62.5".
    static func fieldWeight(_ value: Double) -> String { GymFormat.number(value, decimals: 2).replacingOccurrences(of: ",", with: "") }
}
