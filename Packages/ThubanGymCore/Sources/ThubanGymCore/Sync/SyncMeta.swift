import Foundation

/// Sync bookkeeping stored in the document (`gym.json` key `sync`). Record stamps live on the records themselves
/// (`updatedAt`); this holds the stamps of the single-value parts and the tombstones.
public struct SyncMeta: Codable, Hashable, Sendable {
    /// Last change of `plan` (type, weekly, cycle, pointer): last writer wins.
    public var planUpdatedAt: Date?
    /// Last change of `settings`.
    public var settingsUpdatedAt: Date?
    /// Last change of `activeSession` (started / finished / discarded).
    public var sessionUpdatedAt: Date?
    /// Deleted records, `SyncKey` → when. A record survives a merge only when it changed AFTER its tombstone, so a
    /// stale copy on another device can never bring a deleted workout, set or override back.
    public var deleted: [String: Date]

    public init(planUpdatedAt: Date? = nil, settingsUpdatedAt: Date? = nil, sessionUpdatedAt: Date? = nil, deleted: [String: Date] = [:]) {
        self.planUpdatedAt = planUpdatedAt
        self.settingsUpdatedAt = settingsUpdatedAt
        self.sessionUpdatedAt = sessionUpdatedAt
        self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey { case planUpdatedAt, settingsUpdatedAt, sessionUpdatedAt, deleted }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        planUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .planUpdatedAt)
        settingsUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .settingsUpdatedAt)
        sessionUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .sessionUpdatedAt)
        deleted = try c.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
    }
}

/// Tombstone keys: `<kind>:<id>`.
public enum SyncKey {
    public static func workout(_ id: String) -> String { "w:\(id)" }
    public static func exercise(_ id: String) -> String { "e:\(id)" }
    public static func set(_ id: String) -> String { "s:\(id)" }
    public static func completion(_ id: String) -> String { "c:\(id)" }
    /// Overrides are keyed by their date (one per day).
    public static func override(_ date: DayKey) -> String { "o:\(date.rawValue)" }
    public static func extra(_ id: String) -> String { "x:\(id)" }

    /// The day an override / extra tombstone is about (they expire with their record).
    static func day(ofDatedKey key: String) -> DayKey? {
        guard key.hasPrefix("o:") || key.hasPrefix("x:") else { return nil }
        return DayKey(String(key.dropFirst(2).prefix(10)))
    }
}

extension GymData {
    /// Deterministic sync identity for data that has none yet (a format-1 file, an Atlas conversion, sample data):
    /// each set without an id gets `<log id>~NNN` (its position), each workout / exercise without an order key gets
    /// its array position. Two devices doing this to copies of the same data produce the same ids, so a merge
    /// matches them instead of duplicating them. Never changes anything that already has an identity.
    public mutating func assignLegacyIdentity() {
        for row in logs.indices {
            for index in logs[row].sets.indices where logs[row].sets[index].id == nil {
                logs[row].sets[index].id = "\(logs[row].id)~\(String(format: "%03d", index))"
            }
        }
        for index in workouts.indices where workouts[index].order == nil { workouts[index].order = Double(index) }
        for index in exercises.indices where exercises[index].order == nil { exercises[index].order = Double(index) }
    }
}
