# Thuban Gym — architecture contract

Native macOS app (SwiftUI, macOS 15+, Xcode 26, Swift 5 language mode, XcodeGen, ad-hoc signing unless a team is
set — see "iCloud sync", no Keychain),
plus an iPhone / iPad app (target `GymiOS`, see "iOS app" at the end) built on the same core and shared sources.
A local training log: the plan (weekly or a cycle), today's session with set logging, workouts and their
exercises, progress (e1RM indexes and a strength score), and a one-time read-only import from the Atlas gym plugin.
Sibling of Thuban Canvas / Study: same theme engine (Atlas colour schemes, Brass default, auto / light / dark),
typography and component vocabulary. The design canvas (HTML mockups, 1440×900) is the spec for layout, copy and
hierarchy: `~/.claude/jobs/bd9882f5/tmp/design/gym/project/*.dc.html` — Main (Today), Plan, Workouts, Progress,
Exercise (history sheet), Import (settings), TodayDark. Reproduce them natively; take colours only from theme tokens.

Three engineers build the UI in parallel from this document without talking to each other:

| Engineer | Owns (create/edit freely) |
|---|---|
| **A — Today + Exercise sheet** | `ThubanGym/Views/Today/**`, `ThubanGym/Views/Exercise/**` |
| **B — Plan + Workouts** | `ThubanGym/Views/Plan/**`, `ThubanGym/Views/Workouts/**` |
| **C — Progress + Settings/Import** | `ThubanGym/Views/Progress/**`, `ThubanGym/Views/Settings/**` (all panes; the chrome may be restyled) |

Everything else is **shared and frozen**: `App/**`, `Views/Shell/**`, `Views/Components/**`, `Views/Theme/**`,
`Packages/ThubanGymCore/Sources/**` (existing files), `project.yml`, `scripts/**`. Do not edit shared files — the
three branches must merge without conflicts. If you need something more:

- A new helper view → put it in your own folder (prefix it with your area, e.g. `TodaySetRow`, `PlanDayCell`).
- A new read-only query → an `extension AppModel` in a new file in YOUR folder (`Views/Today/AppModel+Today.swift`).
  Build it from `data` / `today` and the core's public functions.
- A new domain rule → a NEW file in the core (`Packages/ThubanGymCore/Sources/ThubanGymCore/<Area>/…`) with tests in
  a NEW test file (`Tests/ThubanGymCoreTests/<Area>Tests.swift`). Never change an existing core signature.
- A new write → compose existing mutations, or call `app.mutate { data in … }` with `GymData`'s public mutating API.
  Never assign to `app.data` fields directly (it is `private(set)`).

## Layout

```
project.yml                  XcodeGen; sources are directory globs. ThubanGym.xcodeproj is generated, NOT committed.
                             Targets: ThubanGym (macOS) and GymiOS (iOS); both compile Shared/.
Shared/                      Platform-neutral app sources compiled into BOTH targets:
  Model/    AppModel+Queries, AppModel+Mutations, AppModel+Today, AppModel+Progress (extensions of each target's own
            `AppModel`), SharedRoutes (ProgressRange, ThubanScheme)
  Theme/    ThemeEnvironment (tokens → Color, fonts, modifiers; NSColor bits fenced to macOS), DeltaTone+Theme
  Art/      AppArt + AppArtSource (the mark), Icon (line icons + Glyph)
GymiOS/                      The iOS app (see "iOS app").
Packages/ThubanGymCore/      SwiftPM library + tests (swift test)
  Model/    Models (Workout, Exercise, SetEntry, LogEntry, Completion, ActiveSession, GymSettings, Plan,
            PlanOverride, PlanExtra, GymID), DayKey (yyyy-MM-dd value type, Weekday, ClockTime), Units
            (WeightUnit conversion, TargetSpec "3×8", GymFormat), GymData (the document + lookups),
            GymData+Mutations (every write, pure and deterministic)
  Plan/     PlanEngine (planned workout per date, projection, PlanDay / DayStatus, usages, durations, sessions)
  Scoring/  Scoring (Epley e1RM, session scores, indexes, strength score + series, ExerciseHistory, NextTarget),
            Stats (recent sessions, adherence, exercise progress, counts)
  Store/    GymStore (gym.json, atomic writes, daily backups, snapshots), Preferences (preferences.json),
            AppPaths (THUBAN_GYM_HOME), JSONFile
  Import/   AtlasImporter (SQL, ssh command, fetch, convert, ImportSummary), AtlasDocument (tolerant rows),
            CommandRunner / ProcessRunner (Process behind a protocol, macOS only; tests use FixtureRunner;
            DefaultCommandRunner gives iOS an always-failing runner)
  Sync/     SyncMeta (tombstones, single-value stamps, SyncKey, assignLegacyIdentity), GymMerge (stamp / merge /
            normalize), CloudDocumentStore (coordinated read-merge-write + NSFilePresenter + conflict versions),
            CloudLocator (container, off reasons), GymSync (the apps' controller, status, SyncState)
  Session/  SessionLogic (set slots, suggestions, progress segments, next exercise, RestCountdown), WorkoutSummary
  Store/    … GymTransfer (gym.json import / export between devices: decode with validation, encode, contents)
  Sample/   SampleData (deterministic realistic data for smoke / THUBAN_GYM_SEED=sample)
  Theme/    Copied from Thuban Canvas — ColorScheme, SchemePresets, ThemeSelection, ThemeResolver, ResolvedTheme …
ThubanGym/
  App/      ThubanGymApp (scenes, menus ⌘1–⌘4, ⌘,), AppModel (+Queries, +Mutations, +Import), Routes (AppSection,
            SettingsPane, ProgressRange, ThubanScheme alias), AppIconRenderer (live dock icon), SmokeHarness,
            Smoke/SmokeScenes (registry)
  Views/Shell       ShellView: TitleBar (mark + serif "Thuban Gym", StatusChip, Settings), SectionBar (SectionTabs +
                    the section's toolbar), content switch, Exercise sheet host, error banner
  Views/Today       TodayView, TodayToolbar, TodaySmokeScenes                    (A)
  Views/Exercise    ExerciseHistorySheet, ExerciseSmokeScenes                   (A)
  Views/Plan        PlanView, PlanToolbar, PlanSmokeScenes                      (B)
  Views/Workouts    WorkoutsView, WorkoutsToolbar, WorkoutsSmokeScenes          (B)
  Views/Progress    ProgressScreen, ProgressToolbar, ProgressSmokeScenes        (C)
  Views/Settings    SettingsView (nav), SettingsChrome, SettingsPaneHeader, ImportSettings, UnitsSettings,
                    AppearanceSettings (working), PlanSettings, DataSettings, AboutSettings, SettingsSmokeScenes (C)
  Views/Components  Buttons, Chip, SegmentedPicker, ToggleChip, EmptyState, ProgressBar, Common
                    (Icon, AppArt and ThemeEnvironment moved to Shared/)
  Resources         Assets.xcassets (static AppIcon from scripts/make_app_icon.sh), entitlements
scripts/   build.sh, test.sh, smoke.sh, install.sh, regen.sh, make_app_icon.sh
```

Each placeholder file (`TodayView`, `PlanToolbar`, …) carries a TODO describing its artboard. Replace the body; keep
the type name (the shell references it). Split into as many files as you like inside your folder.

## Data

`GymData` is ONE Codable value (`~/Library/Application Support/Thuban Gym/gym.json`, or `$THUBAN_GYM_HOME/gym.json`).
Why a JSON document and not SQLite: a few thousand sets is < 1 MB, so rewriting it per change is ~1 ms; `.atomic`
writes (temp file + rename) cannot tear; every rule is a pure function over a value type and unit-tested without a
database; backups are file copies. `GymStore` makes a daily backup before the first write of each day (14 kept) and
labelled snapshots before an import / restore (20 kept) in `backups/`. `preferences.json` (theme, text size, Atlas
host/email, last section) is separate and never touched by an import.

- `Workout {id, name, rest, flex, restSeconds?}` — array order = display order. `kind` (.training/.rest/.flex) is a
  computed view of the two flags (Atlas's own rest day has both true; rest wins).
- `Exercise {id, workoutId, name, unilateral, bodyweight, target "3×8"}` — order within a workout = array order.
  `targetSpec` parses the target (`sets`, `repsLow`, `repsHigh`, `display` "4 × 6–8").
- `LogEntry {exerciseId, date, side: nil | .left | .right, sets: [SetEntry{weight: kg?, reps}]}` — nil weight =
  bodyweight (scored by reps, shown "BW"). Unilateral exercises log one row per side.
- `Completion {workoutId, date, ts (epoch ms), start "HH:mm", end "HH:mm", auto}` — append-only (`auto` = rest slot
  completed at midnight). `durationMinutes` wraps midnight.
- `ActiveSession {workoutId, date, startedAt}` — the running session (persisted; survives relaunch).
- `GymSettings {unit, address, hours[weekday] {open, close}, defaultDuration, restSeconds}`.
- `Plan {type .weekly/.cycle, weekly["mon"…"sun"] → workoutId, cycle [workoutId], position}`.
- `PlanOverride {date, workoutId? (nil = skip), note?}`, `PlanExtra {date, exerciseId}` — expire after 90 days.

Units: storage is always kg. `unit` (kg / lbs, label "lb") is display only; conversion never rounds stored values.
Typed input → `app.kilograms(fromDisplay:)`; display → `app.weight(kg)` / `app.weightWithUnit(kg)` / `app.displayValue(kg)`.

### Rules (all in the core, all tested)

- **Planned workout** = override (skip / swap) > plan. Weekly: the weekday's workout. Cycle: today uses slot
  `position`; each later day WITHOUT an override takes the next slot. Skips and swaps never consume a slot and never
  move the pointer. Past days show what happened (completions), otherwise `.missed` / `.rest` / `.skipped`.
- **Completing** a workout records a completion and, in cycle mode, moves the pointer to the slot AFTER the nearest
  occurrence of that workout at/after the pointer ("Did Legs on a Pull day? The pointer jumps to Rest"). A workout
  not in the cycle (Upper, Flex) leaves the pointer alone. Weekly mode never touches `position`.
- **Starting** a session for something other than the plan records a swap override for today (so the projection and
  the Plan strip tell the truth); starting the planned workout records nothing.
- **Rollover** (launch, midnight, app activation): every passed cycle day with no completion and no override whose
  slot is a rest workout auto-completes (`auto: true`) and advances; missed training slots stay put; overrides /
  extras older than 90 days are dropped. First launch never back-fills.
- **Scoring**: set e1RM = Epley `w·(1+reps/30)` (bodyweight: reps). Session score = best set; unilateral with both
  sides = the WEAKER side's best. Index = 100 · score / first session's score. Strength score on a date = mean of every
  existing exercise's latest index (equal weight). Duration of a workout = mean of its timed completions, else
  `defaultDuration`.

## Data flow — how a view reads and writes

`AppModel` (`@MainActor @Observable`) is injected at the root: `@Environment(AppModel.self) private var app`, and the
theme with `@Environment(\.thubanTheme) private var theme`. Views are pure functions of `app`; there is no
per-view cache or view model to keep in sync. Every mutation saves immediately (atomic) — never call a "save".
For a `Binding` into the document, build it from a query + a mutation:
`Binding(get: { app.settings.defaultDuration }, set: { v in app.updateSettings { $0.defaultDuration = v } })`.
For a text field that edits a name, keep a local `@State` draft and commit on submit / focus loss (one write, not one
per keystroke). Live clocks (session elapsed, rest timer): `TimelineView(.periodic(from: .now, by: 1))`.

### Reads (`AppModel+Queries.swift`)

| API | Returns |
|---|---|
| `app.data`, `app.today`, `app.unit`, `app.settings`, `app.workouts`, `app.plan`, `app.isCycle`, `app.isFirstRun` | raw state |
| `app.workout(id)`, `app.exercise(id)`, `app.exercises(in: workoutId)` | lookups |
| `app.todayPlan`, `app.planDay(date)`, `app.plannedWorkout(on:)`, `app.planDays(from:count:)`, `app.planStrip` (14 days from `app.weekStart`) | `PlanDay {date, isToday, workout, status, source, plannedWorkout, cycleIndex, override, completions, extraExerciseIds}` |
| `app.cyclePosition(on:)` | `(index, count)` → "Cycle day 2 of 4" |
| `app.nextDate(of: workoutId, after:)` | "Legs moves to Sat Sep 26" |
| `app.usages(of: workoutId)` | `[WorkoutUsage]` (.cycle(index:), .weekly(day), .override(date)) → "Used in" |
| `app.workoutDuration(id)`, `app.upcomingOverrides`, `app.extraIds(on:)` | |
| `app.activeSession`, `app.activeWorkout`, `app.sessionElapsed(now:)`, `app.lastFinish` | running session / undo receipt |
| `app.sessionExercises(on: date, workoutId: nil)` | `[SessionExercise {exercise, isExtra, sourceWorkout}]` (workout's, then extras) |
| `app.sets(exerciseId:date:side:)`, `app.setCount(exerciseIds:on:)`, `PlanEngine.plannedSetCount(_:)` | "6 of 20 sets logged" |
| `app.previousSession(exerciseId:before:)`, `app.session(exerciseId:on:)` | `ExerciseSession {date, sets, left, right, score, topWeight, volume, totalReps, bestSet, isBest, topWeightChange, index}` |
| `app.history(exerciseId:)` | `ExerciseHistory {exercise, sessions (oldest first), isBodyweight, first, latest, best, index, score}` |
| `app.nextTarget(exerciseId:)` | `NextTarget {weightKg?, reps, sets, increase, incrementKg}` → "140 × 8 × 4 · then add 5 lb" |
| `app.strengthScore(on:)`, `app.strengthChange(days:)`, `app.strengthSeries(range)`, `app.weeklyStrengthSeries(range)` | strength score / series `[(date, score)]` |
| `app.recentSessions(limit:)`, `app.exerciseProgress()`, `app.adherence(days:)`, `app.sessionCount(since:)`, `app.averageDuration(since:)`, `app.firstActivity` | Progress numbers (`SessionSummary`, `ExerciseProgress`, `Adherence`) |
| `app.restSeconds(for: workoutId)` | rest timer seconds |
| `app.weight(kg)`, `app.weightWithUnit(kg)`, `app.score(value, bodyweight:)`, `app.kilograms(fromDisplay:)`, `app.displayValue(kg)` | unit-aware formatting / parsing |
| `GymFormat.shortDay/longDay/monthDay/clock/clockRange/minutes/elapsed/delta/grouped/set/number` | shared text formats ("Thu Sep 24", "5:40 – 6:44 PM", "31:12", "+6.3", "2,240", "BW × 8") |

### Writes (`AppModel+Mutations.swift`) — dates default to `app.today`, weights are kg

- Sets: `logSet(exerciseId:date:side:weightKg:reps:) -> index`, `updateSet(…index:…)`, `removeSet(…index:)`, `clearLogs(exerciseId:date:)`
- Session: `startSession(workoutId: nil = planned, at:)`, `finishSession(at:) -> FinishReceipt?` (sets `lastFinish`),
  `undoFinish()` ("Resume session"), `discardSession()`, `complete(workoutId:date:start:end:)`
- Overrides: `skip(date:note:)`, `swap(date:to:note:)`, `override(date:workoutId:note:)`, `clearOverride(date:)`
- Extras: `addExtra(exerciseId:date:)`, `removeExtra(exerciseId:date:)`
- Plan: `setPlanType(_:)`, `setWeekly(_ day:, workoutId:)`, `setCycle([ids])` (pointer follows its workout), `setCyclePosition(_:)`
- Workouts: `addWorkout(name:kind:)`, `updateWorkout(id) { $0.name = … }` (name / kind / restSeconds),
  `duplicateWorkout(id)`, `deleteWorkout(id)`, `moveWorkout(id, to:)`
- Exercises: `addExercise(to:name:target:unilateral:bodyweight:)`, `updateExercise(id) { … }`, `deleteExercise(id)`,
  `moveExercise(id, to:)`, `copyExercises(from:to:only:)`
- Settings in the document: `updateSettings { $0.address = … }`, `setUnit(_:)`
- Preferences / theme: `app.preferences.x = …` (auto-saved), `setAppearanceMode`, `selectScheme(id:)`, `setThemeSelection`
- Escape hatch: `app.mutate { data in data.… }` (any `GymData` public mutating API; saved once).

### Navigation and shared UI state (`AppModel`)

`app.section` (.today/.plan/.workouts/.progress; ⌘1–⌘4), `app.presentedExerciseId = id` opens the Exercise history
sheet (the shell hosts it), `app.openSettings(.importAtlas)` opens Settings on a pane. State a section's view shares
with its toolbar: `app.focusedExerciseId` (Today), `app.selectedWorkoutId` (Workouts), `app.progressRange` (Progress /
Exercise sheet). Everything else is local `@State`. Toolbars may own their own popovers / sheets (e.g. "Swap
workout" → a popover listing workouts, anchored on the button).

### Import and data (`AppModel+Import.swift`, core `Import/`)

`app.importPhase`: `.idle → .fetching → .preview(ImportPreview) → .applying → .done(summary, backup:)` or
`.failed(message)`. Calls: `app.fetchAtlasPreview()` (ssh, read-only), `app.loadImportFile(url)` /
`app.chooseImportFile()`, `app.applyImport()` (snapshots "before-import", replaces the document, runs the rollover),
`app.cancelImport()`. `ImportPreview {summary, data, source, replacesExisting, localWorkouts, localSets, localSessions}`;
`ImportSummary {workouts, workoutNames, exercises, unilateralExercises, bodyweightExercises, logRows, sets,
completions, firstSession, lastSession, overrides, extras, planType, cycleLength, pointerWorkout, pointerIndex,
weeklyDays, unit, warnings, email}`. Host / email: `app.preferences.atlasHost` / `.atlasEmail` (defaults "beelink" /
the user's address); `app.atlasImporter.commandDescription` shows the command. When `replacesExisting`, ask for
confirmation before `applyImport()`. Data: `app.dataFolder`, `app.revealDataFolder()`, `app.backups()`,
`app.restoreBackup(url)` (confirm first), `app.exportData(to:)`.

The importer runs `/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10 <host> docker exec -i stack-postgres-1 psql -U
atlas_user -d atlas -At` and feeds `AtlasImporter.sql(email:)` on stdin: `BEGIN TRANSACTION READ ONLY`, ONE
SELECT building a JSON document from every `gym.*` table for that `auth.users.email`, `ROLLBACK`. NEVER add anything
that writes to Atlas. Tests use `FixtureRunner`; the live dry run is `THUBAN_GYM_LIVE_ATLAS=1 scripts/test.sh`
(prints counts and workout names only; nothing is stored). Verified 2026-09-24: 7 workouts, 36 exercises
(7 unilateral), cycle of 7, pointer 0, lb, no logs / completions yet.

## Design rules

Quiet, precise, the artboards' hierarchy. Colours ONLY from `theme` — never a literal hex / `Color.red` in a view:
`bgColor` (page ground), `panelColor` (cards, title bar), `panel2Color` (tracks, hover, chips), `lineColor` (hairlines),
`line2Color` (control borders), `inkColor` / `inkDimColor` / `inkFaintColor` (text), `accentColor` (fills: primary
buttons, progress, chart line), `brassInkColor` (accent as text / icon), `accentTintColor` (selected fill),
`onAccentColor`, `signalColor` / `signalTextColor` / `signalSoftColor` (live things: in progress, swapped, the star),
`posColor` / `posTextColor` / `posSoftColor` (gains, done, PRs), `negColor` / `negTextColor` / `negSoftColor`
(losses, skipped, errors), `warnSoftColor`. Series colours in charts: accent (score), `line2` (baseline 100).
Dark mode is automatic — check `70-today-dark.png` against TodayDark.dc.html.

- Fonts: `ThubanFont.display(size)` (serif: titles 32, workout name 32–40, big numbers 30), `ThubanFont.body(size,
  weight:)` (15 body, 14 secondary, 13 small), `ThubanFont.small`, `ThubanFont.micro` / `Eyebrow` (12 pt uppercase
  eyebrows), `ThubanFont.mono(13)` for tabular numbers where the design uses mono; `.monospacedDigit()` on numbers
  that tick. Scale dense list text by `@Environment(\.thubanTextScale)`.
- Metrics (`ThubanMetrics`): cards radius 10, controls 8, chips 6, title bar 52, section bar 50, buttons 36 (toolbar
  32). 1 px hairlines, no shadows, no gradients, no emoji. Page padding 24–28 pt, like the artboards.
- Icons: `Icon(.today / .plan / .workouts / .progress / .settings / .skip / .swap / .plus / .check / .close / .trash
  / .dragHandle / .play / .history / .moon / .file / .download, size:)` — the design's own line icons, drawn from
  their SVG paths. Add a case with its `d` strings if you need another (in your own file: `extension IconName` cannot
  add cases, so ask via a comment and use an SF Symbol meanwhile). `Glyph(.chevronRight …)` for small affordances.
- App mark: `AppArtView(size:theme:)`.
- Components: `PrimaryButtonStyle` (`.thubanPrimary`), `.thubanSecondary`, `GhostButtonStyle` / `.thubanGhost`,
  `IconButton`, `ToolbarButton(label, icon:, kind: .ghost/.secondary/.primary)` + `ToolbarDivider` (section bar),
  `Chip(text, kind: .pos/.neg/.warn/.signal/.neutral/.accent, dot:)` + `Chip.status(DayStatus)` (Plan legend),
  `SegmentedPicker` (+ `SegmentedPickerHeight.standard/.toolbar/.card`), `ToggleChip`, `EmptyState`,
  `SectionPlaceholder`, `ProgressBar(value:)`, `Eyebrow`, `SectionHeader`, `PageHeader(eyebrow:title:subtitle:)`,
  `StatTile(label:value:unit:caption:captionTone:)`, `ListRowCard(isSelected:action:)`, `Hairline`, `SearchField`,
  modifiers `.thubanPanel(padding:)`, `.thubanHairline(edge, color:)`, `.thubanChip(kind:)`, `.thubanField()`.
  Settings chrome: `SettingsPaneHeader`, `SettingsGroup`, `SettingsRow`, `SettingsNote`, `ThubanToggle`.
- Charts: Swift Charts (`import Charts`) styled with theme tokens (no default colours, hairline grid in `lineColor`).
- Every control has an accessibility label; lists are keyboard-navigable; hit targets ≥ 28 pt.

### Section toolbars (right side of the section bar; each is its own file)

- Today: `Skip today` (ghost, .skip) · `Swap workout` (ghost, .swap) | `Add exercise` (secondary, .plus — pulls an
  exercise from another workout into today = `addExtra`).
- Plan: `Skip a day` · `Swap a day` (ghost; popovers with a date, a workout and an optional note).
- Workouts: `Duplicate` · `Delete` (ghost; act on `app.selectedWorkoutId`; delete confirms).
- Progress: `3M / 6M / All` (`SegmentedPicker` toolbar height, bound to `app.progressRange`) · `Units: lb` chip that
  toggles `app.setUnit`.

## Smoke screenshots

`SmokeHarness` (App/) seeds `SampleData` into a temp home (the design's world: Push / Pull / Legs / Rest cycle,
~8 months of lb history, Pull in progress 31 min, tomorrow skipped "Career fair", a swap to Upper in 5 days, Rear
Delt Fly extra today), sizes the window to 1440×900, then captures: `10-today … 13-progress`, every registered
scene (`30+`), `70-today-dark`, and every Settings pane (`80-settings-…`). Register extra states in YOUR area's file:

```swift
extension SmokeScenes {
    static var plan: [SmokeScene] {
        [SmokeScene(name: "plan-weekly") { app in app.section = .plan; app.setPlanType(.weekly) }
                    cleanup: { app in app.setPlanType(.cycle) }]
    }
}
```

`window: .main` (default), `.sheet` (the sheet attached to the main window) or `.settings`; `settle:` seconds before
capture. The Settings window has no title bar (`.hiddenTitleBar`); `cacheDisplay` draws its ScrollView blank, so the
harness captures that window with `screencapture -l` (falls back to `cacheDisplay` without Screen Recording permission). Always undo state in `cleanup` so later scenes start from the sample world. Look at your PNGs (Read tool)
and compare them with the artboards before you finish.

## Build / test / smoke

- `DERIVED=.build/DerivedData-<you> scripts/build.sh` — ALWAYS pass a private DerivedData (others build in
  parallel). Regenerates the Xcode project from project.yml first (new files are picked up automatically).
- `scripts/test.sh` — core tests (`swift test`). Add tests for any core logic you add.
- `DERIVED=.build/DerivedData-<you> scripts/smoke.sh .build/smoke-<you>` — builds, runs the smoke walk on a temp
  home (never your real data, never ssh), writes PNGs. It only stops the process it launched.
- `scripts/install.sh` — Release build → `/Applications/Thuban Gym.app` (lead only, after merging).
- `scripts/make_app_icon.sh` — regenerates the static AppIcon from `Shared/Art/AppArtSource.swift` (Brass on a dark plate).
- Manual run on sample data: `THUBAN_GYM_HOME=/tmp/gym-demo THUBAN_GYM_SEED=sample "<app>/Contents/MacOS/Thuban Gym"`.

Git: work on your own branch, small commits, messages ending with
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Do not merge to main and do not install.

## iOS app (target `GymiOS`)

Thuban Gym for iPhone and iPad: the planner / logger used AT the gym. Spec: the approved iOS design canvas
`~/.claude/jobs/bd9882f5/tmp/design/gym-ios/project/*.dc.html` (Main = Today, Plan, Workouts, Progress, Logging, Rest,
Finished, Exercise, WorkoutEditor, LoggingDark, IPad, Settings) with ONE change from the user: typed numbers use the
NATIVE iOS keypad (decimal pad for weight, number pad for reps, a keyboard toolbar with Reps/Weight · Done), not the
board's custom pad. The quick −5 / −2.5 / +2.5 / +5 / Same chips stay, in the page above the keyboard.

- Target: iOS 18+, iPhone + iPad, bundle `org.thuban.gym.ios`, product "Thuban Gym". `UIDesignRequiresCompatibility`
  keeps the classic bars (panel tab bar with a hairline, as drawn). Simulator builds are unsigned
  (`CODE_SIGNING_ALLOWED=NO`); device builds sign automatically with `DEVELOPMENT_TEAM`.
- Sources: `GymiOS/` + `Shared/`. `GymiOS/App/AppModel.swift` is the iOS root model: the SAME core surface as the Mac
  model (`data`, `today`, `mutate`, `lastFinish`, `focusedExerciseId`, `store`), so the shared query / mutation
  extensions compile unchanged; plus tabs and stacks (`tab`, `todayPath` …, `padSection`), the session flow
  (`sessionPresented`, `sessionStage` .logging / .resting / .finished(WorkoutSummary), `rest: RestCountdown`,
  `lastLogged`, `editingSet`) and the theme (`systemIsDark` reported by the root view).
- Layout: `App/` (GymPhoneApp + PhoneRoot + PhoneTabs, AppModel (+Session, +Transfer), RestAlerts, PhoneAppearance,
  PhoneSmoke), `Components/` (PhoneStyle: metrics, fonts, Card, Eyebrow, chips, buttons, PhoneSegmented, PageTitle,
  phoneChrome; PhoneFormat; NumberField), `Today/`, `Session/` (SessionCover + SessionHeader, LoggingView, RestView,
  FinishedView), `Plan/`, `Workouts/`, `Progress/` (ProgressScreen + StrengthChart on Swift Charts,
  ExerciseHistoryScreen), `Settings/` (SettingsSheet, GymImportModifier), `Pad/` (PadRoot: sidebar + detail; Today
  with a session = exercise list | logger / rest side by side when the detail is ≥ 760 pt wide).
- Theme: the 8 Atlas presets + Auto / Light / Dark from the same `ThemeResolver`, same token names. Presented content
  (sheets, the session cover) gets `.phoneChrome()` (theme, brass tint, the chosen mode). UIKit bars are styled once
  by `PhoneAppearance` with dynamic token colours and re-applied on a scheme change; page titles are drawn in the
  content (`PageTitle`, serif 34) because the UIKit large-title font does not survive SwiftUI's bar management.
  Fonts scale with Dynamic Type (`PhoneFont` uses `UIFontMetrics`; the root rebuilds on a size change).
- Session rules (all in the core, tested): `SessionLogic.slots` (done / current / upcoming with "last" values),
  `suggestion` (today's last set → progression target → last time → target reps), unilateral exercises log left
  then right (rest only after the pair), `progress`, `nextExercise`; `RestCountdown` is wall-clock based.
  Logging the first set starts today's session; "Log set · start rest" starts the rest when Settings says so.
- Rest alerts: a local notification (sound, time-sensitive) scheduled for the end of the rest, rescheduled on ±15 s,
  cancelled on skip / undo; a success haptic when the app is on screen. Permission is asked at the first rest. No
  push, no widgets, no Live Activities. "Keep the screen awake" disables the idle timer while the session is up.
- Data: the phone keeps its own gym.json (same `GymStore`, same format) in Application Support inside the app
  container. Settings ▸ Data ▸ "Import gym.json…" (`fileImporter`; `GymTransfer.decode` validates it, an Atlas
  export is converted too; a "before-import" snapshot is taken, then the document is replaced) and "Export
  gym.json…" (`fileExporter`), so the Mac's log moves over by AirDrop / Files. No Keychain; the app holds no
  credentials. The Atlas ssh import is Mac-only (`ProcessRunner` is fenced with `#if os(macOS)`); iOS never runs ssh.
- Preferences (core `Preferences`, tolerant): `restAutoStart`, `restAlert`, `keepScreenAwake` (default on).

### iOS scripts

- `scripts/ios_build.sh` — simulator build into `.build/DerivedData-iOS` (`CONFIG=Release` for Release).
- `scripts/ios_smoke.sh [out]` — boots its own simulators "Thuban Gym Smoke" (iPhone 17, iOS 26.5) and "Thuban Gym
  Smoke iPad" (iPad Air 11-inch; `IPAD=0` skips it), launches with `SIMCTL_CHILD_THUBAN_GYM_SMOKE=phone|ipad`. The
  app moves to a fresh temp home in its container, seeds SampleData and walks the screens; per screen it writes
  `<name>.ready` into `tmp/smoke-shots/` and the script answers with `simctl io screenshot` → `.build/ios-smoke/
  <name>.png` + `<name>.done`. Shots: 10–16 tabs / history / editor / settings, 20–22 logging, number pad, rest,
  30–31 finished / done, 40 first run, 70–75 dark Brass, 80–86 iPad (portrait: simctl cannot rotate the device).
- `scripts/ios_install.sh` — Release simulator build installed on "Thuban iPhone" (created when missing); a signed
  device build + `devicectl` install only when a paired iPhone shows up AND `DEVELOPMENT_TEAM` is set.
- `scripts/make_ios_icon.sh` — the 1024 single-size iOS AppIcon (Brass mark on the dark plate) from Shared/Art.

## iCloud sync

The Mac and the iPhone share ONE document through iCloud Documents: container `iCloud.org.thuban.gym`, file
`Documents/gym.json`, hidden (`NSUbiquitousContainerIsDocumentScopePublic` false — never shown in Finder / Files).
Each app keeps its local Application Support gym.json (backups, offline cache, the working copy); the shared file is
merged with it. Settings: Mac ▸ Data & storage ▸ iCloud Sync, iOS ▸ Settings ▸ Data (switch, status line
"Up to date · last synced 9:41 AM" / "Syncing…" / "Off: <reason>", Sync now). The switch is per device
(`Preferences.iCloudSync`, default on).

**Data model (format 2).** Every record has a stable id and an `updatedAt` stamp (whole seconds, so it survives
the file): workouts / exercises (id, plus an `order` key for list order), sets (`SetEntry.id` `gs-…`, `loggedAt`),
completions (date|workout|ts), overrides (their date), extras (date|exercise). `sync` holds the stamps of the plan,
the gym settings and the running session, and `deleted` = tombstones (`w:/e:/s:/c:/o:/x:` key → date). The pure
mutations do not know any of this: `AppModel.commit` calls `data.stamped(from: old)`, which diffs old vs new —
new / changed records get `now`, removed ones a tombstone, moved list items a new order key, new sets an id.
Format-1 files still load: the decoder gives sets `<log id>~NNN` ids and items their array position (deterministic,
so two devices migrating copies of the same old file agree); `GymStore.loadMigrating` snapshots the old file once
("before sync migration") and the app saves it as format 2. Imports (`replaceData`) get the same deterministic ids.

**Merge (`GymMerge.merge`, commutative, associative, idempotent).** Union by id; when both sides have a record the
later `updatedAt` wins (ties broken by the record's JSON, identically everywhere). A record survives only if it
changed after its tombstone, so a stale copy never resurrects a deletion while a restore (which re-stamps) does.
Sets merge one by one inside their row (exercise + day + side; two rows for the same key collapse into one), so a
set logged on either device is never dropped — only an explicit delete removes one. Plan, settings, running
session: last writer wins. Normal form: tombstones applied, references to deleted workouts / exercises removed (as
`deleteWorkout` does), overrides / extras and their tombstones older than `lastRollover − 90 d` expired, every list
sorted canonically — so devices converge byte-for-byte and stop writing. Replace-style actions (Atlas import,
gym.json import, restore) replace the log on every device (everything missing is tombstoned); their dialogs say so.
Known limits: a concurrent edit of the same record on two offline devices keeps only the later one; the cycle
pointer is part of the plan value (LWW); tombstones are kept (small) except expired override / extra ones.

**Flow.** `persist()` saves locally, then `sync.requestSync(data)`. `GymSync` (core, main actor) runs
`CloudDocumentStore.synchronize` on a serial background queue (coalesced): a coordinated `.forMerging` write that
reads the shared copy and every `NSFileVersion` conflict version, merges them with the local document, writes only
when the result differs, and marks the merged versions resolved (an unreadable version is left in place; an
unreadable or newer-format shared file is never overwritten — status "Sync failed: …"). The result goes to
`AppModel.adoptSynced`, which merges it into the CURRENT document (a set logged meanwhile is kept), saves locally,
runs the rollover and pushes again only if it still differs. Remote changes arrive through the file presenter, an
`NSMetadataQuery` on the container (which also starts downloads), app activation and Sync now. First sync on a
device: "before icloud" snapshot, then the same merge — a missing shared file is uploaded, an existing one merged.

**When it is off.** `CloudLocator` decides: `THUBAN_GYM_CLOUD_DIR` (a plain folder used as the container — the smoke
runs use a temp one; also handy for two Mac instances) → `THUBAN_GYM_HOME` set (test data: "test data folder in
use", never touches real iCloud) → the build's Info.plist `ThubanICloud` (YES only when signed with the entitlements:
"iCloud needs a signed build") → `ubiquityIdentityToken` ("not signed in to iCloud") → the container URL ("iCloud
Drive is not available"). An unreadable local gym.json blocks sync until a restore.

**Signing — how to turn it on.** Needs the paid team (iCloud containers are not available to free accounts).
1. Xcode ▸ Settings ▸ Accounts: add the Apple ID of the developer account.
2. `cp Config/Signing.example.xcconfig Config/Signing.xcconfig` (gitignored) and set `DEVELOPMENT_TEAM` to the team
   id (Accounts ▸ the team, or developer.apple.com ▸ Membership). `$DEVELOPMENT_TEAM` in the environment works too.
3. `scripts/install.sh` (Mac) and `scripts/ios_install.sh` (iPhone, cable + Developer Mode). With a team,
   `scripts/signing.sh` makes them sign automatically with `-allowProvisioningUpdates
   -allowProvisioningDeviceRegistration`, which registers the App IDs `org.thuban.gym` / `org.thuban.gym.ios`, the
   container `iCloud.org.thuban.gym`, this Mac and the iPhone, and downloads the profiles. If Xcode cannot create
   the container, add it once at developer.apple.com ▸ Identifiers ▸ iCloud Containers and enable iCloud (CloudKit
   / iCloud Documents) with it on both App IDs.
4. Both devices must be signed in to the same iCloud account with iCloud Drive on.

Mechanics: `Config/Base.xcconfig` (`THUBAN_SIGNED = NO`, `#include? "Signing.xcconfig"`), `Config/Mac.xcconfig` /
`Config/iOS.xcconfig` pick `CODE_SIGN_ENTITLEMENTS` (`ThubanGym.entitlements` vs `ThubanGym-iCloud.entitlements`
on the Mac, none vs `GymiOS/Resources/GymiOS-iCloud.entitlements` on iOS), style and identity from `THUBAN_SIGNED`.
Without a team every build is exactly as before (ad-hoc Mac, unsigned simulator) with the iCloud entitlements
stripped. Simulator builds (`ios_build.sh`, `ios_smoke.sh`) are always unsigned (`THUBAN_SIGNED=NO`). The Mac app
stays non-sandboxed. Tests: `Tests/…/SyncMergeTests` (rules, migration) and `SyncCloudTests` (two devices on one
temp folder, conflict versions, presenter, GymSync end to end) — no real iCloud.

