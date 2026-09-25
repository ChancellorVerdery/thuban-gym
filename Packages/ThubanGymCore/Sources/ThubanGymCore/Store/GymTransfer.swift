import Foundation

/// Moving the log between devices as a file: the Mac's `gym.json` (Settings ▸ Data ▸ Export) is AirDropped or saved
/// to Files, and the iPhone imports it (and exports its own the same way). The file is exactly the store's format.
public enum GymTransfer {
    /// Suggested file name for an export.
    public static let fileName = "gym.json"

    /// What a file holds, for the confirmation before it replaces the local document.
    public struct Contents: Hashable, Sendable {
        public var workouts: Int
        public var exercises: Int
        public var sets: Int
        public var sessions: Int
        public var firstDay: DayKey?
        public var lastDay: DayKey?
        /// "gym.json" for the Thuban format, "atlas" for an Atlas export (converted on import).
        public var format: String
    }

    /// Decodes a Thuban `gym.json`, or an Atlas export (the Mac importer's JSON), into a document. Throws
    /// `ThubanError.invalid` for anything else, instead of accepting a file that merely happens to be JSON (the
    /// document decoder is tolerant and would read `{}` as an empty log).
    public static func decode(_ bytes: Data, now: Date = Date()) throws -> (data: GymData, format: String) {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: bytes) } catch {
            throw ThubanError.invalid("That file is not JSON.")
        }
        guard let top = object as? [String: Any] else { throw ThubanError.invalid("That file is not a gym.json export.") }
        if (top["format"] as? String) == AtlasDocument.format {
            let document = try AtlasDocument.decode(bytes)
            guard document.userFound else { throw ThubanError.invalid("That file has no Atlas account in it.") }
            return (try AtlasImporter.convert(document, source: "file:atlas", now: now).data, "atlas")
        }
        let known: Set<String> = ["workouts", "exercises", "logs", "completions", "plan"]
        guard top["version"] != nil || !known.isDisjoint(with: top.keys) else {
            throw ThubanError.invalid("That file is not a gym.json export.")
        }
        do {
            let data = try JSONFile.decoder.decode(GymData.self, from: bytes)
            if data.version > GymData.currentVersion {
                throw ThubanError.invalid("That gym.json was written by a newer version of Thuban Gym.")
            }
            return (data, "gym.json")
        } catch let error as ThubanError {
            throw error
        } catch {
            throw ThubanError.invalid("That gym.json could not be read: \(error.localizedDescription)")
        }
    }

    /// The bytes of an export (same encoder as the store: pretty, sorted keys, ISO dates).
    public static func encode(_ data: GymData) throws -> Data {
        do { return try JSONFile.encoder.encode(data) } catch {
            throw ThubanError.store("gym.json could not be written: \(error.localizedDescription)")
        }
    }

    public static func contents(_ data: GymData, format: String = "gym.json") -> Contents {
        let days = Set(data.logs.map(\.date)).union(data.completions.map(\.date))
        return Contents(workouts: data.workouts.count, exercises: data.exercises.count,
                        sets: data.logs.reduce(0) { $0 + $1.sets.count },
                        sessions: data.completions.filter { !(data.workout($0.workoutId)?.isRest ?? false) }.count,
                        firstDay: days.min(), lastDay: days.max(), format: format)
    }
}
