import SwiftUI
import ThubanGymCore

/// The main window (design: every artboard's frame): 52 pt title bar, 50 pt section bar (section tabs + the
/// section's own toolbar on the right), then the section's content. Also hosts the Exercise history sheet and the
/// save-error banner. Sections live in Views/<Area>/ and are only referenced here.
struct ShellView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var app = app
        let theme = app.theme
        VStack(spacing: 0) {
            TitleBar()
            SectionBar()
            if let problem = app.loadError ?? app.saveError {
                ProblemBanner(text: problem, isLoadError: app.loadError != nil)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bgColor)
        .environment(\.thubanTheme, theme)
        .environment(\.thubanTextScale, app.preferences.textSize.scale)
        .ignoresSafeArea()
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(item: Binding(get: { app.presentedExerciseId.map(ExerciseSheetItem.init) },
                             set: { app.presentedExerciseId = $0?.id })) { item in
            ExerciseHistorySheet(exerciseId: item.id)
                .environment(app)
                .environment(\.thubanTheme, app.theme)
                .environment(\.thubanTextScale, app.preferences.textSize.scale)
                .preferredColorScheme(app.theme.isDark ? .dark : .light)
        }
        .onChange(of: app.settingsRequest) { _, _ in openWindow(id: "settings") }
    }

    @ViewBuilder
    private var content: some View {
        if !app.isLoaded {
            Color.clear
        } else {
            switch app.section {
            case .today: TodayView()
            case .plan: PlanView()
            case .workouts: WorkoutsView()
            case .progress: ProgressScreen()
            }
        }
    }
}

private struct ExerciseSheetItem: Identifiable {
    var id: String
}

// MARK: - Title bar

/// [traffic lights] mark + serif "Thuban Gym" ……… status chip · Settings.
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: ThubanMetrics.trafficLightInset - 16)
            HStack(spacing: 9) {
                AppArtView(size: 20, theme: theme)
                Text("Thuban Gym")
                    .font(ThubanFont.display(18))
                    .kerning(-0.18)
                    .foregroundStyle(theme.inkColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Thuban Gym")

            Spacer(minLength: 8)

            StatusChip()
            ToolbarButton("Settings", icon: .settings) { app.openSettings() }
                .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.titleBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.panelColor)
        .thubanHairline(.bottom, color: theme.lineColor)
        .gesture(WindowDragGesture())
    }
}

/// "Pull in progress · 31:12" while a session runs; "Importing from Atlas…" during an import fetch.
struct StatusChip: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        if app.importPhase.isBusy {
            chip(dot: theme.accentColor, text: "Importing from Atlas…")
        } else if let workout = app.activeWorkout {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                chip(dot: theme.signalColor, text: "\(workout.name) in progress · \(GymFormat.elapsed(app.sessionElapsed(now: context.date)))")
            }
            .onTapGesture { app.section = .today }
        }
    }

    private func chip(dot: Color, text: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).monospacedDigit()
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.inkDimColor)
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section bar

/// Section tabs (Today / Plan / Workouts / Progress) on the left, the current section's toolbar on the right.
struct SectionBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            SectionTabs()
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                switch app.section {
                case .today: TodayToolbar()
                case .plan: PlanToolbar()
                case .workouts: WorkoutsToolbar()
                case .progress: ProgressToolbar()
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: ThubanMetrics.sectionBarHeight)
        .frame(maxWidth: .infinity)
        .background(theme.bgColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}

/// The segmented section nav: `panel2` track (padding 3, radius 9); active tab is a `panel` card with a `line2`
/// border and `ink` text; icons 15 pt.
struct SectionTabs: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppSection.allCases) { section in
                SectionTab(section: section, isActive: app.section == section) { app.section = section }
            }
        }
        .padding(3)
        .background(theme.panel2Color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

private struct SectionTab: View {
    @Environment(\.thubanTheme) private var theme
    var section: AppSection
    var isActive: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Icon(section.icon, size: 15)
                Text(section.label)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? theme.inkColor : theme.inkDimColor)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(isActive ? theme.panelColor : (hovering ? theme.panelColor.opacity(0.5) : .clear),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(isActive ? theme.line2Color : .clear, lineWidth: ThubanMetrics.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(section.label)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .help("\(section.label) (⌘\(String(section.shortcut)))")
    }
}

// MARK: - Banner

private struct ProblemBanner: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var text: String
    var isLoadError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(theme.negColor).frame(width: 7, height: 7)
            Text(isLoadError ? "Your data could not be read, so nothing will be saved until it is fixed. \(text)" : "Could not save: \(text)")
                .font(ThubanFont.small)
                .foregroundStyle(theme.negTextColor)
                .lineLimit(2)
            Spacer(minLength: 8)
            if isLoadError {
                ToolbarButton("Restore a backup", icon: .history) { app.openSettings(.data) }
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .background(theme.negSoftColor)
        .thubanHairline(.bottom, color: theme.lineColor)
    }
}
