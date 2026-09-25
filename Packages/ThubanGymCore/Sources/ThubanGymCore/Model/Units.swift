import Foundation

// MARK: - Weight units

extension WeightUnit {
    /// Exact international pound.
    public static let kilogramsPerPound = 0.45359237

    /// "kg" / "lb" (the design writes pounds as "lb"; Atlas stores the setting as "lbs").
    public var label: String { self == .kg ? "kg" : "lb" }

    /// kg → this unit. Never rounds.
    public func fromKilograms(_ kg: Double) -> Double {
        self == .kg ? kg : kg / WeightUnit.kilogramsPerPound
    }

    /// This unit → kg. Never rounds: 140 lb is stored as 63.50293180 kg and shows as 140 again.
    public func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value * WeightUnit.kilogramsPerPound
    }

    /// The usual plate jump in this unit, returned in kg (2.5 kg / 5 lb).
    public var incrementKg: Double { self == .kg ? 2.5 : toKilograms(5) }

    /// Rounds a display value to the nearest loadable step (0.5 kg / 1 lb… used for suggestions only, never storage).
    public func roundedForDisplay(_ value: Double) -> Double {
        self == .kg ? (value * 2).rounded() / 2 : value.rounded()
    }
}

// MARK: - Targets

/// A parsed target: "3×8" → 3 sets of 8; "4 × 6–8" → 4 sets of 6 to 8; "3x10" works too.
public struct TargetSpec: Hashable, Sendable {
    public var sets: Int
    public var repsLow: Int
    public var repsHigh: Int

    public init(sets: Int, repsLow: Int, repsHigh: Int) {
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = max(repsLow, repsHigh)
    }

    public init?(_ text: String) {
        let normalized = text.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .replacingOccurrences(of: " ", with: "")
        let halves = normalized.split(separator: "x", maxSplits: 1)
        guard halves.count == 2, let sets = Int(halves[0]), sets > 0 else { return nil }
        let reps = halves[1].split(separator: "-")
        guard let low = reps.first.flatMap({ Int($0) }), low > 0 else { return nil }
        let high = reps.count > 1 ? (Int(reps[1]) ?? low) : low
        self.init(sets: sets, repsLow: low, repsHigh: high)
    }

    /// Canonical display: "3 × 8" / "4 × 6–8".
    public var display: String {
        repsLow == repsHigh ? "\(sets) × \(repsLow)" : "\(sets) × \(repsLow)–\(repsHigh)"
    }
}

// MARK: - Formatting

/// Shared text formatting, so every screen writes numbers, weights, days and times the same way.
public enum GymFormat {
    static let posix = Locale(identifier: "en_US_POSIX")

    /// Trims a trailing ".0": 140.0 → "140", 63.5 → "63.5". `decimals` caps the fraction digits.
    public static func number(_ value: Double, decimals: Int = 1) -> String {
        let factor = pow(10, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        if rounded == rounded.rounded() { return grouped(Int(rounded)) }
        let text = String(format: "%.\(decimals)f", rounded)
        let parts = text.split(separator: ".")
        let whole = Int(parts[0]).map(grouped) ?? String(parts[0])
        var fraction = String(parts.count > 1 ? parts[1] : "")
        while fraction.hasSuffix("0") { fraction.removeLast() }
        return fraction.isEmpty ? whole : "\(whole).\(fraction)"
    }

    /// Thousands separators: 2240 → "2,240".
    public static func grouped(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = posix
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A weight in the display unit without the unit: "140", "63.5"; "BW" for bodyweight (nil).
    public static func weight(_ kg: Double?, unit: WeightUnit, decimals: Int = 1) -> String {
        guard let kg else { return "BW" }
        return number(unit.fromKilograms(kg), decimals: decimals)
    }

    /// "140 lb" / "BW".
    public static func weightWithUnit(_ kg: Double?, unit: WeightUnit, decimals: Int = 1) -> String {
        guard let kg else { return "BW" }
        return "\(number(unit.fromKilograms(kg), decimals: decimals)) \(unit.label)"
    }

    /// An e1RM score: kg → unit with one decimal ("177.3"); bodyweight scores are reps ("8 reps").
    public static func score(_ value: Double, bodyweight: Bool, unit: WeightUnit) -> String {
        bodyweight ? "\(Int(value.rounded())) reps" : String(format: "%.1f", unit.fromKilograms(value))
    }

    /// "140 × 8" / "BW × 8".
    public static func set(_ set: SetEntry, unit: WeightUnit) -> String {
        "\(weight(set.weight, unit: unit)) × \(set.reps)"
    }

    /// "Thu Sep 24"
    public static func shortDay(_ day: DayKey) -> String { formatted(day, "EEE MMM d") }
    /// "Thursday, September 24"
    public static func longDay(_ day: DayKey) -> String { formatted(day, "EEEE, MMMM d") }
    /// "Sep 24"
    public static func monthDay(_ day: DayKey) -> String { formatted(day, "MMM d") }
    /// "Sep"
    public static func month(_ day: DayKey) -> String { formatted(day, "MMM") }

    private static func formatted(_ day: DayKey, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.calendar = DayKey.utc
        formatter.timeZone = DayKey.utc.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: day.date(calendar: DayKey.utc))
    }

    /// "17:42" → "5:42 PM"; "" for unparseable input.
    public static func clock(_ hhmm: String) -> String {
        guard let minutes = ClockTime.minutes(hhmm) else { return "" }
        let h = minutes / 60, m = minutes % 60
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return String(format: "%d:%02d %@", hour12, m, h < 12 ? "AM" : "PM")
    }

    /// "5:40 – 6:44 PM" (drops the first AM/PM when both match), "" when unknown.
    public static func clockRange(start: String, end: String) -> String {
        let a = clock(start), b = clock(end)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty ? b : a }
        if a.suffix(2) == b.suffix(2) { return "\(a.dropLast(3)) – \(b)" }
        return "\(a) – \(b)"
    }

    /// "58 min", "1 h 5 min".
    public static func minutes(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : (minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min")
    }

    /// Elapsed / countdown clock: 1872 s → "31:12"; ≥ 1 h → "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Signed delta with one decimal: "+6.3", "−1.2" (true minus sign), "0.0".
    public static func delta(_ value: Double, decimals: Int = 1) -> String {
        let text = String(format: "%.\(decimals)f", abs(value))
        if (value * pow(10, Double(decimals))).rounded() == 0 { return text }
        return value > 0 ? "+\(text)" : "−\(text)"
    }
}
