import AppKit
import SwiftUI
import ThubanGymCore

/// Settings → Data & storage: where the file lives and what is in it, the backups (restore after confirming),
/// and Export. OWNER: Engineer C (Progress + Settings/Import).
struct DataSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @State private var backups: [GymStore.Backup] = []
    @State private var pendingRestore: GymStore.Backup?
    @State private var message: (text: String, tone: SettingsNote.Tone)?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsPaneHeader(eyebrow: nil, title: "Data & storage",
                               caption: "Everything lives in one file on this Mac. With iCloud Sync on, it is shared with your iPhone through your own iCloud; nothing is sent anywhere else.")

            SyncSettingsGroup()

            SettingsGroup("On this Mac") {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(app.dataFolder.path(percentEncoded: false))
                            .font(ThubanFont.mono(12.5))
                            .foregroundStyle(theme.inkDimColor)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Show in Finder") { app.revealDataFolder() }.buttonStyle(SecondaryButtonStyle(height: 30))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    HStack(spacing: 0) {
                        count(app.workouts.count, "workouts")
                        count(app.data.exercises.count, "exercises")
                        count(app.sessionCount(), "sessions")
                        count(app.data.logs.reduce(0) { $0 + $1.sets.count }, "sets")
                    }
                    .padding(.vertical, 12)
                    .thubanHairline(.top, color: theme.lineColor)
                    if let source = app.data.importSource {
                        Text(importLine(source))
                            .font(ThubanFont.small)
                            .foregroundStyle(theme.inkDimColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .thubanHairline(.top, color: theme.lineColor)
                    }
                }
                .thubanPanel(padding: 0)
            }

            SettingsGroup("Backups", caption: "A copy is saved before the first change of each day (the last \(GymStore.dailyBackupsKept) are kept) and before every import or restore.") {
                if backups.isEmpty {
                    SettingsNote(text: "No backups yet. The first one is made with tomorrow's first change.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(backups.prefix(12).enumerated()), id: \.element.id) { index, backup in
                            BackupRow(backup: backup) { pendingRestore = backup }
                                .thubanHairline(.top, color: index == 0 ? .clear : theme.lineColor)
                        }
                    }
                    .thubanPanel(padding: 0)
                    if backups.count > 12 {
                        SettingsNote(text: "\(backups.count - 12) older backups are in the backups folder.")
                    }
                }
            }

            SettingsGroup("Export", caption: "Saves everything as one JSON file (the same format as gym.json). Weights are in kg.") {
                HStack(spacing: 12) {
                    Button("Export…", action: export).buttonStyle(SecondaryButtonStyle(height: 32))
                    if let message { SettingsNote(text: message.text, tone: message.tone) }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: app.data) { _, _ in reload() }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible, presenting: pendingRestore) { backup in
            Button("Restore", role: .destructive) { restore(backup) }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("Replaces everything here with the copy from \(Self.dateText(backup.created)). What is here now is saved as a backup first."
                 + (app.iCloudSyncEnabled && app.syncStatus.isOn ? " With iCloud Sync on, your iPhone gets the restored log too." : ""))
        }
    }

    private func count(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(GymFormat.grouped(value)).font(ThubanFont.display(20)).foregroundStyle(theme.inkColor).monospacedDigit()
            Text(label).font(ThubanFont.small).foregroundStyle(theme.inkDimColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    private func importLine(_ source: String) -> String {
        let from = source.hasPrefix("file:") ? "the file \(source.dropFirst(5))" : source.replacingOccurrences(of: "atlas:", with: "Atlas on ")
        guard let at = app.data.importedAt else { return "Imported from \(from)." }
        return "Imported from \(from) on \(Self.dateText(at))."
    }

    private func reload() { backups = app.backups() }

    private func restore(_ backup: GymStore.Backup) {
        do {
            try app.restoreBackup(backup.url)
            message = ("Restored the copy from \(Self.dateText(backup.created)).", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
        reload()
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Thuban Gym \(formatter.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try app.exportData(to: url)
            message = ("Saved \(url.lastPathComponent).", .positive)
        } catch {
            message = (error.localizedDescription, .negative)
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

private struct BackupRow: View {
    @Environment(\.thubanTheme) private var theme
    var backup: GymStore.Backup
    var restore: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Chip(kindLabel, kind: backup.label == "daily" ? .neutral : .accent)
                .frame(width: 120, alignment: .leading)
            Text(DataSettings.dateText(backup.created))
                .font(ThubanFont.body(14))
                .foregroundStyle(theme.inkColor)
            Spacer(minLength: 8)
            Text(ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
                .font(ThubanFont.mono(12.5))
                .foregroundStyle(theme.inkFaintColor)
            Button("Restore…", action: restore).buttonStyle(GhostButtonStyle(height: 28, horizontalPadding: 10))
                .accessibilityLabel("Restore backup from \(DataSettings.dateText(backup.created))")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private var kindLabel: String {
        switch backup.label {
        case "daily": return "Daily"
        case "before-import": return "Before import"
        case "before-restore": return "Before restore"
        case "before-icloud": return "Before iCloud"
        case "before-sync-migration": return "Before update"
        default: return backup.label.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
