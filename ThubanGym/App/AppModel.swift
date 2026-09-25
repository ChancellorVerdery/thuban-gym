import AppKit
import Foundation
import Observation
import ThubanGymCore
import os

/// Root model. Owns the domain document (`data`, persisted by `store` after every change), the preferences, the
/// resolved theme, navigation, and the import state. Views read it with `@Environment(AppModel.self)` and change
/// things ONLY through its methods (AppModel+Mutations.swift) — never by editing `data` themselves.
///
/// Files: queries in AppModel+Queries.swift, writes in AppModel+Mutations.swift, the Atlas import and backups in
/// AppModel+Import.swift. Rules live in the core package (PlanEngine, Scoring, Stats, GymData mutations).
@MainActor
@Observable
final class AppModel {
    static let logger = Logger(subsystem: "org.thuban.gym", category: "app")

    // MARK: Domain

    /// The whole local database. Read freely; write only through `mutate` (or the named APIs built on it).
    private(set) var data: GymData = .empty
    /// Today in the user's calendar. Updated at midnight / on wake, which also runs the rollover.
    private(set) var today: DayKey = .today()
    private(set) var isLoaded = false
    /// Set when gym.json exists but cannot be read; the app then runs on empty data WITHOUT saving over it.
    private(set) var loadError: String?
    /// Last failed save (shown as a banner by the shell).
    var saveError: String?
    /// The last finished session, so Today can offer "Resume session" (undo). Cleared by the next mutation of a
    /// session or after the user dismisses the banner.
    var lastFinish: FinishReceipt?

    @ObservationIgnored let store: GymStore
    /// iCloud sync of the document (status, switch, "Sync now" in Settings ▸ Data & storage).
    let sync: GymSync
    /// Swappable for tests / previews; the import runs ssh through it.
    @ObservationIgnored var commandRunner: CommandRunner = ProcessRunner()

    // MARK: Preferences & theme

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            if preferences.theme != oldValue.theme { recomputeTheme() }
            if preferences.iCloudSync != oldValue.iCloudSync, isLoaded { sync.setEnabled(preferences.iCloudSync) }
        }
    }
    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)
    var themeSelection: ThemeSelection { preferences.theme }

    // MARK: Navigation

    var section: AppSection = .today {
        didSet { if section != oldValue { preferences.lastSection = section.rawValue } }
    }
    /// Exercise history sheet (design: "Barbell Row history"). Set to an exercise id to present it.
    var presentedExerciseId: String?
    /// Bumped to open the Settings window (the shell observes it); `settingsPane` picks the pane.
    var settingsRequest = 0
    var settingsPane: SettingsPane?

    // MARK: Per-section UI state shared between a section's view and its toolbar (views own everything else as @State)

    /// Today: the exercise card that is expanded / receives the next logged set (nil = first unfinished).
    var focusedExerciseId: String?
    /// Workouts: the workout open in the editor (the toolbar's Duplicate / Delete act on it).
    var selectedWorkoutId: String?
    /// Progress (and the Exercise sheet): the 3M / 6M / All range.
    var progressRange: ProgressRange = .all

    // MARK: Import (AppModel+Import.swift)

    var importPhase: ImportPhase = .idle
    @ObservationIgnored var importTask: Task<Void, Never>?

    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var preferencesSaveTask: Task<Void, Never>?

    init(store: GymStore = GymStore()) {
        self.store = store
        sync = GymSync(local: store)
        preferences = Preferences.load()
        systemIsDark = Self.currentSystemIsDark()
        theme = ThemeResolver.resolve(preferences.theme, systemIsDark: systemIsDark)
        if let raw = preferences.lastSection, let saved = AppSection(rawValue: raw) { section = saved }
    }

    // MARK: Lifecycle

    /// Called once from the main window's `.task`: loads (or seeds) the document, runs the day rollover, starts
    /// observing appearance / day changes, then hands over to the smoke harness when it is enabled.
    func load() async {
        guard !isLoaded else { return }
        if appearanceObservation == nil { observeAppearance() }
        recomputeTheme()
        today = .today()
        do {
            // An older gym.json is snapshotted ("before sync migration") and saved in the current format once.
            let loaded = try store.loadMigrating()
            data = loaded.data
            if loaded.migrated {
                data = data.stamped(from: data)
                saveLocal()
            }
        } catch {
            loadError = error.localizedDescription
            Self.logger.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
        if loadError == nil, !store.exists, Self.shouldSeedSample {
            var sample = SampleData.make(today: today, now: Date())
            sample.assignLegacyIdentity()
            data = sample.stamped(from: .empty)
            saveLocal()
        }
        rollover()
        observeDayChanges()
        isLoaded = true
        startSync()
        SmokeHarness.startIfEnabled(app: self)
    }

    /// `THUBAN_GYM_SEED=sample` (or a smoke run) seeds an EMPTY home with `SampleData`. Never replaces a file.
    static var shouldSeedSample: Bool {
        SmokeHarness.isEnabled || ProcessInfo.processInfo.environment["THUBAN_GYM_SEED"] == "sample"
    }

    /// Re-reads the calendar day and runs the rollover (rest auto-complete, override expiry) when it changed.
    func refreshDay() {
        let now = DayKey.today()
        if now != today { today = now }
        rollover()
        if isLoaded { sync.syncNow() }
    }

    private func rollover() {
        guard loadError == nil else { return }
        var copy = data
        copy.rollover(to: today)
        if copy != data { commit(copy) }
    }

    private func observeDayChanges() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, NSApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshDay() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPreferences() }
        })
    }

    // MARK: Writing

    /// THE write path. Applies `change` to a copy of the document, publishes it, and saves atomically. Every named
    /// mutation (logSet, complete, skip …) is a thin wrapper around this. Returns what `change` returns.
    @discardableResult
    func mutate<T>(_ change: (inout GymData) throws -> T) rethrows -> T {
        var copy = data
        let result = try change(&copy)
        if copy != data { commit(copy) }
        return result
    }

    /// Publishes a changed document with its sync stamps (what changed, what was deleted) and saves it.
    private func commit(_ changed: GymData) {
        data = changed.stamped(from: data)
        persist()
    }

    /// Replaces the whole document (import, restore). Callers snapshot first.
    /// With iCloud Sync on this replaces the log on the other devices too: whatever is not in `newData` is
    /// recorded as deleted.
    func replaceData(_ newData: GymData) {
        let wasUnreadable = loadError != nil
        var incoming = newData
        incoming.assignLegacyIdentity() // an import's sets get the same ids on every device
        data = incoming.stamped(from: data)
        lastFinish = nil
        loadError = nil
        persist()
        rollover()
        if wasUnreadable, isLoaded { sync.block(nil) }
    }

    /// Saves locally (the offline cache / backups) and queues an iCloud merge.
    private func persist() {
        // A document that failed to load is never overwritten by the empty fallback.
        guard loadError == nil else { return }
        saveLocal()
        sync.requestSync(data)
    }

    private func saveLocal() {
        guard loadError == nil else { return }
        do {
            try store.save(data, today: today)
            if saveError != nil { saveError = nil }
        } catch {
            saveError = error.localizedDescription
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }


    // MARK: iCloud sync (core GymSync; Settings rows in Shared/Model/AppModel+Sync.swift)

    /// Connects the sync controller after the first load: it reads the current document through `currentData`
    /// and hands every merged shared copy to `adoptSynced`.
    private func startSync() {
        sync.currentData = { [weak self] in
            guard let self, self.isLoaded, self.loadError == nil else { return nil }
            return self.data
        }
        sync.onMerged = { [weak self] merged in self?.adoptSynced(merged) }
        sync.block(loadError == nil ? nil : .localUnreadable)
        sync.setEnabled(preferences.iCloudSync)
    }

    /// A merged copy of the shared file arrived. Merge it into what is here NOW (a set logged while the sync ran
    /// is kept), save the local cache, run the rollover, and push again only when this copy still differs.
    func adoptSynced(_ merged: GymData) {
        guard isLoaded, loadError == nil else { return }
        let combined = GymMerge.merge(data, merged)
        if combined != data {
            data = combined
            saveLocal()
            rollover()
        }
        if data != merged { sync.requestSync(data) }
    }

    // MARK: Preferences

    private func persistPreferences() {
        preferencesSaveTask?.cancel()
        let snapshot = preferences
        preferencesSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            do { try Preferences.save(snapshot) } catch { Self.logger.error("preferences save failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    func flushPreferences() {
        guard let pending = preferencesSaveTask else { return }
        pending.cancel()
        preferencesSaveTask = nil
        try? Preferences.save(preferences)
    }

    // MARK: Settings window

    func openSettings(_ pane: SettingsPane? = nil) {
        settingsPane = pane
        settingsRequest += 1
    }

    // MARK: Theme

    func setThemeSelection(_ selection: ThemeSelection) { preferences.theme = selection }

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = themeSelection
        selection.mode = mode
        setThemeSelection(selection)
    }

    func selectScheme(id: String) {
        var selection = themeSelection
        selection.schemeId = id
        if id == ThubanScheme.customId, selection.custom == nil { selection.custom = SchemePresets.default.asCustom() }
        setThemeSelection(selection)
    }

    private func observeAppearance() {
        appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let dark = Self.currentSystemIsDark()
                if dark != self.systemIsDark {
                    self.systemIsDark = dark
                    self.recomputeTheme()
                }
            }
        }
    }

    /// True when macOS itself is dark (independent of any override applied to `NSApp.appearance`).
    static func currentSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(themeSelection, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
        switch themeSelection.mode {
        case .auto: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
        AppIconRenderer.apply(theme: resolved)
    }
}
