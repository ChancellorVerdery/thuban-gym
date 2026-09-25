import Foundation
import SwiftUI
import ThubanGymCore
import UniformTypeIdentifiers

/// Settings ▸ Data: the phone keeps its own gym.json (same format as the Mac); a file moves the log between them.
extension AppModel {
    /// A file picked in "Import gym.json…", decoded but not applied yet.
    struct PendingImport: Identifiable {
        var id = UUID()
        var fileName: String
        var data: GymData
        var contents: GymTransfer.Contents
    }

    /// Reads a picked file (security-scoped URL from `fileImporter`).
    func readImport(_ url: URL) throws -> PendingImport {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let bytes: Data
        do { bytes = try Data(contentsOf: url) } catch {
            throw ThubanError.store("\(url.lastPathComponent) could not be opened: \(error.localizedDescription)")
        }
        let decoded = try GymTransfer.decode(bytes)
        return PendingImport(fileName: url.lastPathComponent, data: decoded.data,
                             contents: GymTransfer.contents(decoded.data, format: decoded.format))
    }

    /// Snapshots the phone's own document ("before-import"), then replaces it. Returns the snapshot's URL.
    @discardableResult
    func applyImport(_ pending: PendingImport) throws -> URL? {
        let backup = try store.snapshot(label: "before import")
        var incoming = pending.data
        incoming.importedAt = Date()
        incoming.importSource = "file:\(pending.fileName)"
        replaceData(incoming)
        return backup
    }

    /// The document for "Export gym.json…".
    var exportDocument: GymJSONDocument { GymJSONDocument(data: data) }

    /// What the phone holds now (Settings ▸ Data footnote).
    var localContents: GymTransfer.Contents { GymTransfer.contents(data) }
}

/// gym.json as a `FileDocument` for `fileExporter` (the share sheet / Files / AirDrop).
struct GymJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: GymData

    init(data: GymData) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = try GymTransfer.decode(bytes).data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try GymTransfer.encode(data))
    }
}
