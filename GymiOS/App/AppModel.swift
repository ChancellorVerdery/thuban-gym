import Foundation
import Observation
import SwiftUI
import ThubanGymCore
import UIKit
import os

/// The iPhone / iPad root model. The Mac target has its own `AppModel` with the same core surface (`data`, `today`,
/// `mutate`, `lastFinish`, `focusedExerciseId`), so the shared `Shared/Model/AppModel+*.swift` extensions — every
/// query and every write — compile unchanged against either. This class adds what only the phone has: tabs, the
/// full-screen session, the rest timer and gym.json import / export through Files.
@MainActor
@Observable
final class AppModel {
    nonisolated static let logger = Logger(subsystem: "org.thuban.gym.ios", category: "app")

    // MARK: Domain (same contract as the Mac model)

    private(set) var data: GymData = .empty
    private(set) var today: DayKey = .today()
    private(set) var isLoaded = false
    /// gym.json exists but cannot be read: the app runs on empty data and never saves over the file.
    private(set) var loadError: String?
    var saveError: String?
    /// The last finished session ("Review and edit sets" undoes it).
    var lastFinish: FinishReceipt?
    /// The exercise the session logger shows (nil = the first unfinished one).
    var focusedExerciseId: String?

    @ObservationIgnored let store: GymStore

    // MARK: Preferences and theme

    var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            if preferences.theme != oldValue.theme { recomputeTheme() }
        }
    }
    /// The system appearance (the root view reports it; only used in Auto mode).
    private(set) var systemIsDark = false
    private(set) var theme: ResolvedTheme = ThemeResolver.resolve(.default, systemIsDark: false)
    var themeSelection: ThemeSelection { preferences.theme }

    // MARK: Navigation

    var tab: PhoneTab = .today
    var showSettings = false
    var todayPath: [PhoneRoute] = []
    var planPath: [PhoneRoute] = []
    var workoutsPath: [PhoneRoute] = []
    var progressPath: [PhoneRoute] = []
    /// iPad sidebar selection.
    var padSection: PadSection = .today

    // MARK: Session (GymiOS/Session/*)

    /// The full-screen logger is up (iPhone). The session itself lives in `data.activeSession`.
    var sessionPresented = false
    var sessionStage: SessionStage = .logging
    var rest: RestCountdown?
    /// What the rest screen's Undo removes.
    var lastLogged: LoggedSet?
    /// Smoke run only: asks the logger to focus a field (so the screenshot shows the number pad).
    var smokeFocus: String?
    /// A logged set being corrected in the logger (tap a done row); nil = logging the next set.
    var editingSet: LoggedSet?

    @ObservationIgnored let alerts = RestAlerts()
    @ObservationIgnored var restTask: Task<Void, Never>?
    @ObservationIgnored private var preferencesSaveTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(store: GymStore = GymStore()) {
        self.store = store
        preferences = Preferences.load()
        systemIsDark = UIScreen.main.traitCollection.userInterfaceStyle == .dark
        theme = ThemeResolver.resolve(preferences.theme, systemIsDark: systemIsDark)
    }

    // MARK: Lifecycle

    func load() {
        guard !isLoaded else { return }
        today = .today()
        do {
            data = try store.load()
        } catch {
            loadError = error.localizedDescription
            Self.logger.error("load failed: \(error.localizedDescription, privacy: .public)")
        }
        if loadError == nil, !store.exists, PhoneSmoke.isEnabled || ProcessInfo.processInfo.environment["THUBAN_GYM_SEED"] == "sample" {
            data = SampleData.make(today: today, now: Date())
            persist()
        }
        rollover()
        observeDayChanges()
        alerts.smoke = PhoneSmoke.isEnabled
        isLoaded = true
    }

    func refreshDay() {
        let now = DayKey.today()
        if now != today { today = now }
        rollover()
    }

    private func rollover() {
        guard loadError == nil else { return }
        var copy = data
        copy.rollover(to: today)
        if copy != data {
            data = copy
            persist()
        }
    }

    private func observeDayChanges() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.NSCalendarDayChanged, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshDay()
                    self?.restTick()
                }
            })
        }
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPreferences() }
        })
    }

    // MARK: Writing

    /// THE write path (same as the Mac): change a copy, publish, save atomically.
    @discardableResult
    func mutate<T>(_ change: (inout GymData) throws -> T) rethrows -> T {
        var copy = data
        let result = try change(&copy)
        if copy != data {
            data = copy
            persist()
        }
        return result
    }

    /// Replaces the whole document (import). Callers snapshot first.
    func replaceData(_ newData: GymData) {
        data = newData
        lastFinish = nil
        loadError = nil
        focusedExerciseId = nil
        cancelRest()
        lastLogged = nil
        editingSet = nil
        persist()
        rollover()
    }

    private func persist() {
        guard loadError == nil else { return }
        do {
            try store.save(data, today: today)
            if saveError != nil { saveError = nil }
        } catch {
            saveError = error.localizedDescription
            Self.logger.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
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

    // MARK: Theme

    func setAppearanceMode(_ mode: AppearanceMode) {
        var selection = themeSelection
        selection.mode = mode
        preferences.theme = selection
    }

    func selectScheme(id: String) {
        var selection = themeSelection
        selection.schemeId = id
        preferences.theme = selection
    }

    func setSystemIsDark(_ dark: Bool) {
        guard dark != systemIsDark else { return }
        systemIsDark = dark
        recomputeTheme()
    }

    private func recomputeTheme() {
        let resolved = ThemeResolver.resolve(themeSelection, systemIsDark: systemIsDark)
        if resolved != theme { theme = resolved }
    }

    /// nil in Auto (follow the system).
    var preferredColorScheme: SwiftUI.ColorScheme? {
        switch themeSelection.mode {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// The scheme currently selected (a preset; a custom scheme made on the Mac shows as "Custom").
    var schemeLabel: String {
        SchemePresets.scheme(id: themeSelection.schemeId)?.label ?? (themeSelection.custom?.label ?? "Custom")
    }
}

// MARK: - Navigation types

enum PhoneTab: String, CaseIterable, Hashable, Identifiable {
    case today, plan, workouts, progress
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: IconName {
        switch self {
        case .today: return .kettlebell
        case .plan: return .calendar
        case .workouts: return .today   // the dumbbell
        case .progress: return .progress
        }
    }
}

enum PadSection: String, CaseIterable, Hashable, Identifiable {
    case today, plan, workouts, progress, settings
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: IconName {
        switch self {
        case .today: return .kettlebell
        case .plan: return .calendar
        case .workouts: return .today
        case .progress: return .progress
        case .settings: return .sliders
        }
    }
}

/// Pushed screens.
enum PhoneRoute: Hashable {
    case exercise(String)
    case workout(String)
}

enum SessionStage: Equatable {
    case logging
    case resting
    case finished(WorkoutSummary)
}

/// A set that was logged (for Undo and for editing).
struct LoggedSet: Equatable {
    var exerciseId: String
    var date: DayKey
    var side: Side?
    var index: Int
    var set: SetEntry
}
