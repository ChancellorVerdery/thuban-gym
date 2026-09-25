import AppKit
import Foundation
import ThubanGymCore

/// A fetched / loaded import waiting for the user's confirmation.
struct ImportPreview: Equatable {
    var summary: ImportSummary
    var data: GymData
    /// "atlas:beelink" or "file:<name>".
    var source: String
    /// The local document is not empty, so applying replaces something (confirm, and a backup is made first).
    var replacesExisting: Bool
    /// What is here now, for the "replaces …" line.
    var localWorkouts: Int
    var localSets: Int
    var localSessions: Int
}

/// Settings → Import from Atlas state machine: idle → fetching → preview → applying → done (or failed).
enum ImportPhase: Equatable {
    case idle
    /// ssh / file read in flight (cancellable with `cancelImport()`).
    case fetching
    /// Decoded and converted; nothing written yet. Show the counts and ask to apply.
    case preview(ImportPreview)
    case applying
    /// Applied. `backup` is the snapshot of what was replaced (nil when there was nothing).
    case done(ImportSummary, backup: URL?)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .fetching, .applying: return true
        default: return false
        }
    }
}

/// Atlas import (read-only on the Atlas side, preview before replacing) and local backups.
extension AppModel {
    /// Importer configured from Settings (host + email) and `commandRunner`.
    var atlasImporter: AtlasImporter {
        AtlasImporter(host: preferences.atlasHost, email: preferences.atlasEmail, runner: commandRunner)
    }

    /// Step 1 (Atlas): runs the read-only SQL over ssh, converts, and moves to `.preview`. Nothing is written.
    func fetchAtlasPreview() {
        startImport(source: "atlas:\(preferences.atlasHost)") { [atlasImporter] in
            try await atlasImporter.fetch()
        }
    }

    /// Step 1 (file): reads a saved Atlas JSON document (same shape the SQL returns) and moves to `.preview`.
    func loadImportFile(_ url: URL) {
        startImport(source: "file:\(url.lastPathComponent)") {
            try AtlasImporter.document(fromFile: url)
        }
    }

    /// Asks for a file with an open panel, then `loadImportFile`.
    func chooseImportFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .plainText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an Atlas gym export (JSON)"
        if panel.runModal() == .OK, let url = panel.url { loadImportFile(url) }
    }

    /// Step 2: snapshots the current document ("before-import"), replaces it with the preview, runs the rollover.
    func applyImport() {
        guard case .preview(let preview) = importPhase else { return }
        importPhase = .applying
        do {
            let backup = try store.snapshot(label: "before import")
            var incoming = preview.data
            incoming.importSource = preview.source
            replaceData(incoming)
            importPhase = .done(preview.summary, backup: backup)
        } catch {
            importPhase = .failed(error.localizedDescription)
        }
    }

    /// Cancels a running fetch, or dismisses a preview / result.
    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importPhase = .idle
    }

    private func startImport(source: String, load: @escaping @Sendable () async throws -> AtlasDocument) {
        importTask?.cancel()
        importPhase = .fetching
        importTask = Task { @MainActor [weak self] in
            do {
                let document = try await load()
                try Task.checkCancellation()
                let converted = try AtlasImporter.convert(document, source: source)
                guard let self else { return }
                self.importPhase = .preview(ImportPreview(
                    summary: converted.summary, data: converted.data, source: source,
                    replacesExisting: !self.data.isEmpty,
                    localWorkouts: self.data.workouts.count,
                    localSets: self.data.logs.reduce(0) { $0 + $1.sets.count },
                    localSessions: Stats.sessionCount(self.data)))
            } catch is CancellationError {
                self?.importPhase = .idle
            } catch {
                self?.importPhase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Backups and data

    var dataFolder: URL { store.directory }

    /// Daily backups and labelled snapshots, newest first.
    func backups() -> [GymStore.Backup] { store.backups() }

    /// Replaces the document with a backup (after snapshotting the current one as "before-restore").
    func restoreBackup(_ url: URL) throws {
        let restored = try store.read(backup: url)
        try store.snapshot(label: "before restore")
        replaceData(restored)
    }

    /// Writes the current document to `url` (Settings → Data & storage → Export).
    func exportData(to url: URL) throws {
        try JSONFile.write(data, to: url)
    }

    func revealDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }
}
