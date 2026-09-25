import Foundation

/// How two copies of the log become one (iCloud sync, conflict versions, first enable). Pure functions over
/// `GymData`; unit-tested without iCloud.
///
/// The model:
/// - Every record has a stable id and an `updatedAt` stamp: workouts, exercises (id), sets (`SetEntry.id`),
///   completions (date|workout|ts), overrides (their date), extras (date|exercise). A merge is the UNION of both
///   sides by id; when both sides have a record, the later `updatedAt` wins (a tie is broken deterministically by
///   the record's JSON, so every device picks the same one).
/// - A deletion leaves a tombstone (`sync.deleted[key] = when`). A record survives only when it changed after its
///   tombstone, so a stale copy never resurrects a deleted item, while a restore (which re-stamps what it brings
///   back) does.
/// - Sets are merged one by one inside their row (exercise + day + side): two devices logging the same exercise
///   the same day keep every set. A logged set disappears only through an explicit delete (a tombstone).
/// - The plan, the gym settings and the running session are single values: last writer wins (`sync.*UpdatedAt`).
/// - List order (workouts, exercises) is a per-record `order` key, so a merge can sort without knowing who moved
///   what. Everything else is sorted canonically.
///
/// `merge` is commutative, associative and idempotent (`merge(x, x) == x` for a normalized `x`), so devices that
/// keep merging what they see converge on the same document and stop writing.
public enum GymMerge {
    /// Stamps are whole seconds: the store writes ISO 8601 dates without fractions, so a stamp survives a round trip
    /// through the file unchanged (otherwise the in-memory and on-disk copies would never compare equal).
    public static func stampDate(_ now: Date) -> Date {
        Date(timeIntervalSince1970: floor(now.timeIntervalSince1970))
    }

    // MARK: - Stamping a local change

    /// `new` is `old` after a local change (any mutation, an import, a restore). Returns `new` with the sync
    /// metadata that describes the change: new / changed records stamped `now`, removed ones tombstoned, moved list
    /// items re-keyed, new sets given ids, single values stamped when they changed. Then normalized.
    public static func stamp(_ new: GymData, from old: GymData, now: Date) -> GymData {
        let t = stampDate(now)
        var d = new
        var deleted = old.sync.deleted
        for (key, date) in new.sync.deleted { deleted[key] = max(deleted[key] ?? date, date) }

        // Order keys first, so a moved record counts as changed.
        rekey(&d.workouts, known: Set(old.workouts.map(\.id)))
        rekey(&d.exercises, known: Set(old.exercises.map(\.id)))

        stampRecords(&d.workouts, old: old.workouts, key: { SyncKey.workout($0.id) }, at: t, deleted: &deleted)
        stampRecords(&d.exercises, old: old.exercises, key: { SyncKey.exercise($0.id) }, at: t, deleted: &deleted)
        stampRecords(&d.completions, old: old.completions, key: { SyncKey.completion($0.id) }, at: t, deleted: &deleted)
        stampRecords(&d.overrides, old: old.overrides, key: { SyncKey.override($0.date) }, at: t, deleted: &deleted)
        stampRecords(&d.extras, old: old.extras, key: { SyncKey.extra($0.id) }, at: t, deleted: &deleted)
        stampSets(&d.logs, old: old.logs, at: t, deleted: &deleted)

        d.sync.planUpdatedAt = d.plan == old.plan ? old.sync.planUpdatedAt : t
        d.sync.settingsUpdatedAt = d.settings == old.settings ? old.sync.settingsUpdatedAt : t
        d.sync.sessionUpdatedAt = d.activeSession == old.activeSession ? old.sync.sessionUpdatedAt : t
        d.sync.deleted = deleted
        normalize(&d)
        return d
    }

    // MARK: - Merging two copies

    /// The union of two copies (see the type's documentation). Neither side is ever discarded wholesale.
    public static func merge(_ first: GymData, _ second: GymData) -> GymData {
        var a = first, b = second
        a.assignLegacyIdentity()
        b.assignLegacyIdentity()

        var d = GymData()
        d.version = max(a.version, b.version)
        var deleted = a.sync.deleted
        for (key, date) in b.sync.deleted { deleted[key] = max(deleted[key] ?? date, date) }

        d.workouts = union(a.workouts, b.workouts) { $0.id }
        d.exercises = union(a.exercises, b.exercises) { $0.id }
        d.completions = union(a.completions, b.completions) { $0.id }
        d.overrides = union(a.overrides, b.overrides) { $0.date.rawValue }
        d.extras = union(a.extras, b.extras) { $0.id }
        d.logs = mergeLogs(a.logs, b.logs)

        (d.plan, d.sync.planUpdatedAt) = pick(a.plan, a.sync.planUpdatedAt, b.plan, b.sync.planUpdatedAt)
        (d.settings, d.sync.settingsUpdatedAt) = pick(a.settings, a.sync.settingsUpdatedAt, b.settings, b.sync.settingsUpdatedAt)
        (d.activeSession, d.sync.sessionUpdatedAt) = pick(a.activeSession, a.sync.sessionUpdatedAt, b.activeSession, b.sync.sessionUpdatedAt)

        d.lastRollover = [a.lastRollover, b.lastRollover].compactMap { $0 }.max()
        let aImport = (a.importedAt ?? .distantPast, a.importSource ?? "")
        let bImport = (b.importedAt ?? .distantPast, b.importSource ?? "")
        if aImport >= bImport {
            (d.importedAt, d.importSource) = (a.importedAt, a.importSource)
        } else {
            (d.importedAt, d.importSource) = (b.importedAt, b.importSource)
        }
        d.sync.deleted = deleted
        normalize(&d)
        return d
    }

    // MARK: - Normal form

    /// Applies the tombstones, repairs references to deleted workouts / exercises, expires old overrides / extras
    /// (and their tombstones) exactly like the day rollover does, and sorts every list canonically. Idempotent and
    /// time-independent, so two devices normalizing the same content get byte-identical documents.
    public static func normalize(_ d: inout GymData) {
        d.version = max(d.version, GymData.currentVersion)
        let tombstones = d.sync.deleted
        func alive(_ key: String, _ updated: Date?) -> Bool {
            guard let gone = tombstones[key] else { return true }
            return (updated ?? .distantPast) > gone
        }
        d.workouts.removeAll { !alive(SyncKey.workout($0.id), $0.updatedAt) }
        d.exercises.removeAll { !alive(SyncKey.exercise($0.id), $0.updatedAt) }
        d.completions.removeAll { !alive(SyncKey.completion($0.id), $0.updatedAt) }
        d.overrides.removeAll { !alive(SyncKey.override($0.date), $0.updatedAt) }
        d.extras.removeAll { !alive(SyncKey.extra($0.id), $0.updatedAt) }
        for row in d.logs.indices {
            d.logs[row].sets.removeAll { set in set.id.map { !alive(SyncKey.set($0), set.updatedAt) } ?? false }
        }
        d.logs.removeAll { $0.sets.isEmpty }

        // A record that won against its tombstone clears it (a local document never holds both).
        var deleted = tombstones
        for w in d.workouts { deleted[SyncKey.workout(w.id)] = nil }
        for e in d.exercises { deleted[SyncKey.exercise(e.id)] = nil }
        for c in d.completions { deleted[SyncKey.completion(c.id)] = nil }
        for o in d.overrides { deleted[SyncKey.override(o.date)] = nil }
        for x in d.extras { deleted[SyncKey.extra(x.id)] = nil }
        for row in d.logs { for set in row.sets { if let id = set.id { deleted[SyncKey.set(id)] = nil } } }

        // References to a workout / exercise deleted on another device (what `deleteWorkout` does locally).
        let goneWorkouts = Set(deleted.keys.filter { $0.hasPrefix("w:") }.map { String($0.dropFirst(2)) })
        if !goneWorkouts.isEmpty {
            d.exercises.removeAll { goneWorkouts.contains($0.workoutId) }
            for (day, id) in d.plan.weekly where goneWorkouts.contains(id) { d.plan.weekly[day] = nil }
            if d.plan.cycle.contains(where: goneWorkouts.contains) {
                let pointer = d.plan.normalizedPosition
                let removedBefore = d.plan.cycle.prefix(pointer).filter(goneWorkouts.contains).count
                d.plan.cycle.removeAll(where: goneWorkouts.contains)
                d.plan.position = d.plan.cycle.isEmpty ? 0 : (pointer - removedBefore) % d.plan.cycle.count
            }
            if let session = d.activeSession, goneWorkouts.contains(session.workoutId) { d.activeSession = nil }
        }
        // Overrides / extras never point at something that is gone (`deleteWorkout` / `deleteExercise` invariant).
        let liveWorkouts = Set(d.workouts.map(\.id))
        let liveExercises = Set(d.exercises.map(\.id))
        d.overrides.removeAll { $0.workoutId.map { !liveWorkouts.contains($0) } ?? false }
        d.extras.removeAll { !liveExercises.contains($0.exerciseId) }

        // Expiry (the rollover's 90-day window, anchored on the document's own `lastRollover`).
        if let last = d.lastRollover {
            let cutoff = last.adding(days: -GymData.overrideLifetimeDays)
            d.overrides.removeAll { $0.date < cutoff }
            d.extras.removeAll { $0.date < cutoff }
            for key in deleted.keys {
                if let day = SyncKey.day(ofDatedKey: key), day < cutoff { deleted[key] = nil }
            }
        }
        d.sync.deleted = deleted

        // Canonical order. Index as the last key keeps the sort stable for anything not yet identified.
        d.workouts = sorted(d.workouts) { ($0.order ?? .infinity, $0.id) < ($1.order ?? .infinity, $1.id) }
        d.exercises = sorted(d.exercises) { ($0.order ?? .infinity, $0.id) < ($1.order ?? .infinity, $1.id) }
        d.logs = sorted(d.logs) {
            ($0.date, $0.exerciseId, $0.side?.rawValue ?? "", $0.id) < ($1.date, $1.exerciseId, $1.side?.rawValue ?? "", $1.id)
        }
        for row in d.logs.indices {
            d.logs[row].sets = sorted(d.logs[row].sets) {
                ($0.loggedAt ?? .distantPast, $0.id ?? "") < ($1.loggedAt ?? .distantPast, $1.id ?? "")
            }
        }
        d.completions = sorted(d.completions) { ($0.date, $0.ts, $0.workoutId) < ($1.date, $1.ts, $1.workoutId) }
        d.overrides = sorted(d.overrides) { $0.date < $1.date }
        d.extras = sorted(d.extras) {
            ($0.date, $0.updatedAt ?? .distantPast, $0.exerciseId) < ($1.date, $1.updatedAt ?? .distantPast, $1.exerciseId)
        }
    }

    // MARK: - Pieces

    private static func stampRecords<R: SyncRecord>(_ records: inout [R], old: [R], key: (R) -> String, at t: Date,
                                                     deleted: inout [String: Date]) {
        var previous = [String: R]()
        for record in old { previous[key(record)] = record }
        var present = Set<String>()
        for index in records.indices {
            let k = key(records[index])
            present.insert(k)
            deleted[k] = nil
            if let before = previous[k], before == records[index] { continue }
            records[index].updatedAt = t
        }
        for k in previous.keys where !present.contains(k) { deleted[k] = t }
    }

    private static func stampSets(_ logs: inout [LogEntry], old: [LogEntry], at t: Date, deleted: inout [String: Date]) {
        var previous = [String: SetEntry]()
        for row in old { for set in row.sets { if let id = set.id { previous[id] = set } } }
        var present = Set<String>()
        for row in logs.indices {
            for index in logs[row].sets.indices {
                var set = logs[row].sets[index]
                if set.id == nil {
                    set.id = GymID.make("gs")
                    set.loggedAt = t
                    set.updatedAt = t
                } else if let before = previous[set.id!], before == set {
                    present.insert(set.id!)
                    continue
                } else {
                    set.updatedAt = t
                }
                let id = set.id!
                present.insert(id)
                deleted[SyncKey.set(id)] = nil
                logs[row].sets[index] = set
            }
        }
        for id in previous.keys where !present.contains(id) { deleted[SyncKey.set(id)] = t }
    }

    /// Re-keys list items whose `order` no longer fits their array position (moved, inserted, duplicated). Keeps the
    /// longest run of existing keys that is still increasing, and gives the others keys between their neighbours,
    /// so a move changes only the moved record. Items not in `known` (new) always get a fresh key.
    private static func rekey<R: OrderedRecord>(_ items: inout [R], known: Set<String>) {
        let n = items.count
        guard n > 0 else { return }
        let keys: [Double?] = items.map { known.contains($0.id) ? $0.order : nil }
        var length = [Int](repeating: 0, count: n)
        var previous = [Int](repeating: -1, count: n)
        var end = -1
        for i in 0..<n {
            guard let ki = keys[i] else { continue }
            length[i] = 1
            for j in 0..<i {
                if let kj = keys[j], kj < ki, length[j] + 1 > length[i] {
                    length[i] = length[j] + 1
                    previous[i] = j
                }
            }
            if end < 0 || length[i] > length[end] { end = i }
        }
        var keep = Set<Int>()
        var cursor = end
        while cursor >= 0 { keep.insert(cursor); cursor = previous[cursor] }

        var last: Double?
        for i in 0..<n {
            if keep.contains(i) { last = keys[i]; continue }
            let next = ((i + 1)..<n).first(where: keep.contains).flatMap { keys[$0] }
            let key: Double
            switch (last, next) {
            case (nil, nil): key = 0
            case (let l?, nil): key = l + 1
            case (nil, let x?): key = x - 1
            case (let l?, let x?): key = (l + x) / 2
            }
            if items[i].order != key { items[i].order = key }
            last = key
        }
        // Gaps exhausted by many moves (never in practice): renumber everything.
        if zip(items, items.dropFirst()).contains(where: { ($0.order ?? 0) >= ($1.order ?? 0) }) {
            for i in items.indices { items[i].order = Double(i) }
        }
    }

    private static func union<R: SyncRecord>(_ a: [R], _ b: [R], key: (R) -> String) -> [R] {
        var chosen = [String: R]()
        var order = [String]()
        for record in a + b {
            let k = key(record)
            if let existing = chosen[k] {
                chosen[k] = newer(existing, record)
            } else {
                chosen[k] = record
                order.append(k)
            }
        }
        return order.compactMap { chosen[$0] }
    }

    private static func mergeLogs(_ a: [LogEntry], _ b: [LogEntry]) -> [LogEntry] {
        var rows = [String: LogEntry]()
        var order = [String]()
        for row in a + b {
            let k = "\(row.exerciseId)|\(row.date.rawValue)|\(row.side?.rawValue ?? "")"
            guard var existing = rows[k] else {
                rows[k] = row
                order.append(k)
                continue
            }
            existing.id = min(existing.id, row.id)
            existing.sets = union(existing.sets, row.sets) { $0.id ?? "" }
            rows[k] = existing
        }
        // A single row may itself hold the same set twice only if it came from two merged rows; dedupe anyway.
        return order.compactMap { k in
            rows[k].map { row in
                var row = row
                row.sets = union(row.sets, []) { $0.id ?? "" }
                return row
            }
        }
    }

    /// The later stamp wins; a tie between different records is broken by their JSON (deterministic everywhere).
    private static func newer<R: SyncRecord>(_ x: R, _ y: R) -> R {
        let tx = x.updatedAt ?? .distantPast, ty = y.updatedAt ?? .distantPast
        if tx != ty { return tx > ty ? x : y }
        if x == y { return x }
        return firstWinsTie(x, y) ? x : y
    }

    private static func pick<T: Hashable & Encodable>(_ x: T, _ tx: Date?, _ y: T, _ ty: Date?) -> (T, Date?) {
        let ax = tx ?? .distantPast, ay = ty ?? .distantPast
        if ax != ay { return ax > ay ? (x, tx) : (y, ty) }
        if x == y { return (x, tx) }
        return firstWinsTie(x, y) ? (x, tx) : (y, ty)
    }

    private static func firstWinsTie<T: Encodable>(_ x: T, _ y: T) -> Bool {
        let ex = (try? JSONFile.encoder.encode([x])) ?? Data()
        let ey = (try? JSONFile.encoder.encode([y])) ?? Data()
        return !ex.lexicographicallyPrecedes(ey)
    }

    private static func sorted<T>(_ items: [T], by less: (T, T) -> Bool) -> [T] {
        items.enumerated().sorted { lhs, rhs in
            if less(lhs.element, rhs.element) { return true }
            if less(rhs.element, lhs.element) { return false }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: - Record protocols

protocol SyncRecord: Hashable, Encodable {
    var updatedAt: Date? { get set }
}

protocol OrderedRecord {
    var id: String { get }
    var order: Double? { get set }
}

extension Workout: SyncRecord, OrderedRecord {}
extension Exercise: SyncRecord, OrderedRecord {}
extension Completion: SyncRecord {}
extension PlanOverride: SyncRecord {}
extension PlanExtra: SyncRecord {}
extension SetEntry: SyncRecord {}

extension GymData {
    /// This document after a local change from `old`, with its sync metadata (see `GymMerge.stamp`).
    public func stamped(from old: GymData, now: Date = Date()) -> GymData {
        GymMerge.stamp(self, from: old, now: now)
    }

    /// The union of this document and another copy (see `GymMerge.merge`).
    public func merged(with other: GymData) -> GymData {
        GymMerge.merge(self, other)
    }
}
