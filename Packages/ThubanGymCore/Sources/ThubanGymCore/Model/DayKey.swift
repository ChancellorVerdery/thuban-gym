import Foundation

/// A calendar day as `yyyy-MM-dd` (Atlas's date format). Pure value: arithmetic runs in a fixed UTC Gregorian
/// calendar, so it is immune to DST and time zones. Only `today(now:calendar:)` and `date(hour:minute:)` touch
/// the user's local calendar.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int

    public var id: String { rawValue }

    public init(year: Int, month: Int, day: Int) {
        // Normalise out-of-range components (e.g. day 32) through the calendar.
        let date = DayKey.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
        let c = DayKey.utc.dateComponents([.year, .month, .day], from: date)
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    /// Parses `yyyy-MM-dd` (also tolerates a trailing time part: `2026-09-24T…`). `nil` for anything else.
    public init?(_ raw: String) {
        let head = raw.trimmingCharacters(in: .whitespaces).prefix(10)
        let parts = head.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
        guard self.month == m, self.day == d else { return nil } // rejects 2026-02-30
    }

    public var rawValue: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var description: String { rawValue }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: Codable as a plain string

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a yyyy-MM-dd date: \(raw)"))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    // MARK: Arithmetic

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var utcNoon: Date {
        DayKey.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date(timeIntervalSince1970: 0)
    }

    public func adding(days: Int) -> DayKey {
        let date = DayKey.utc.date(byAdding: .day, value: days, to: utcNoon) ?? utcNoon
        let c = DayKey.utc.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year ?? year, month: c.month ?? month, day: c.day ?? day)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: DayKey) -> Int {
        DayKey.utc.dateComponents([.day], from: utcNoon, to: other.utcNoon).day ?? 0
    }

    public var weekday: Weekday {
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        let w = DayKey.utc.component(.weekday, from: utcNoon)
        return Weekday.allCases[(w + 5) % 7]
    }

    /// Every day from `self` through `end` inclusive (empty when `end < self`).
    public func through(_ end: DayKey) -> [DayKey] {
        guard self <= end else { return [] }
        return (0...days(to: end)).map { adding(days: $0) }
    }

    // MARK: Local calendar bridges

    /// Today in the user's calendar (or the one given).
    public static func today(now: Date = Date(), calendar: Calendar = .current) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return DayKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// This day at a local wall-clock time.
    public func date(hour: Int = 12, minute: Int = 0, calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? utcNoon
    }
}

/// Monday-first weekdays with Atlas's keys (`mon` … `sun`).
public enum Weekday: String, CaseIterable, Codable, Sendable, Identifiable {
    case mon, tue, wed, thu, fri, sat, sun

    public var id: String { rawValue }

    /// "Mon"
    public var short: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// "Monday"
    public var name: String {
        switch self {
        case .mon: return "Monday"
        case .tue: return "Tuesday"
        case .wed: return "Wednesday"
        case .thu: return "Thursday"
        case .fri: return "Friday"
        case .sat: return "Saturday"
        case .sun: return "Sunday"
        }
    }
}

/// `HH:mm` wall-clock helpers (Atlas stores session start/end and opening hours this way).
public enum ClockTime {
    /// Minutes since midnight for `H:mm` / `HH:mm`; nil for anything else (including "").
    public static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m),
              parts[1].count == 2 else { return nil }
        return h * 60 + m
    }

    /// `HH:mm` for a date in the given calendar.
    public static func string(from date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `HH:mm` for minutes since midnight (wraps past 24 h).
    public static func string(minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// Session length in minutes from start/end strings; crossing midnight wraps (Atlas's rule). nil when either is
    /// missing or the length is zero.
    public static func duration(start: String?, end: String?) -> Int? {
        guard let s = minutes(start), let e = minutes(end) else { return nil }
        let length = (e - s + 1440) % 1440
        return length > 0 ? length : nil
    }
}
