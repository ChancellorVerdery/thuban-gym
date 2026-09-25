import SwiftUI
import ThubanGymCore

/// One exercise in today's session (design: Main.dc.html). Collapsed it is a 54 pt row (badge, name, target, what
/// was logged or last time, status); expanded it is the set table — Set / Previous / Weight × Reps / e1RM / check,
/// L and R columns for unilateral exercises — with Add set, the rest hint and History. OWNER: Engineer A.
struct TodayExerciseCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    @Environment(\.thubanTextScale) private var textScale

    var item: SessionExercise
    var number: Int
    var date: DayKey
    var isFocused: Bool
    var isUpNext: Bool
    var isExpanded: Bool

    /// Rows added with "Add set" beyond the target and what is logged.
    @State private var addedRows = 0
    /// Typed values on rows that are not logged yet, keyed "w|L|2" / "r||0".
    @State private var drafts: [String: String] = [:]

    private var exercise: Exercise { item.exercise }

    var body: some View {
        Group {
            if isExpanded { expanded } else { collapsed }
        }
        .background(theme.panelColor, in: RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ThubanMetrics.cardRadius, style: .continuous)
            .strokeBorder(isFocused ? theme.line2Color : theme.lineColor, lineWidth: ThubanMetrics.hairline))
    }

    // MARK: Derived

    private var logged: Int { app.todayLoggedSets(exercise, on: date) }
    private var target: Int { app.todayTargetSets(exercise) }
    private var isDone: Bool { target > 0 && logged >= target }
    private var todaySession: ExerciseSession? { app.session(exerciseId: exercise.id, on: date) }
    private var previous: ExerciseSession? { app.previousSession(exerciseId: exercise.id, before: date) }
    private var isBodyweight: Bool { exercise.bodyweight }
    private var unitLabel: String { app.unit.label }

    private var badgeStyle: TodayCardBadge.Style {
        if isDone { return .done }
        return isFocused ? .focused : .idle
    }

    // MARK: Collapsed

    private var collapsed: some View {
        HStack(spacing: 12) {
            TodayCardBadge(number: number, style: badgeStyle)
            Text(exercise.name)
                .font(.system(size: 15 * textScale, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
            chips
            Text(collapsedSummary)
                .font(ThubanFont.mono(13 * textScale))
                .foregroundStyle(theme.inkFaintColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 6)
            Spacer(minLength: 8)
            collapsedStatus
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .contentShape(Rectangle())
        .onTapGesture { app.focusedExerciseId = exercise.id }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(exercise.name), \(collapsedStatusText)")
        .accessibilityAction { app.focusedExerciseId = exercise.id }
        .contextMenu { cardMenu }
    }

    @ViewBuilder
    private var chips: some View {
        if let spec = exercise.targetSpec { TodayMonoChip(text: spec.display) }
        else if !exercise.target.isEmpty { TodayMonoChip(text: exercise.target) }
        if exercise.unilateral { Chip("L / R", kind: .signal) }
        if item.isExtra { Chip("Extra · from \(item.sourceWorkout?.name ?? "another workout")", kind: .warn) }
    }

    private var collapsedSummary: String {
        if let todaySession { return summary(of: todaySession, prefix: "") }
        if let previous { return summary(of: previous, prefix: "last ") }
        return exercise.targetSpec.map { "target \($0.display)" } ?? ""
    }

    /// "BW × 8 · 8 · 7 · 7", "last 40 × 15 · 15 · 13", "L 60 × 10 · 10 · 9  R 60 × 10 · 10 · 10".
    private func summary(of session: ExerciseSession, prefix: String) -> String {
        func line(_ sets: [SetEntry]) -> String {
            guard let first = sets.first else { return "" }
            if sets.allSatisfy({ $0.weight == first.weight }) {
                return "\(app.weight(first.weight)) × " + sets.map { String($0.reps) }.joined(separator: " · ")
            }
            return sets.map { GymFormat.set($0, unit: app.unit) }.joined(separator: " · ")
        }
        if !session.left.isEmpty || !session.right.isEmpty {
            var parts: [String] = []
            if !session.left.isEmpty { parts.append("L " + line(session.left)) }
            if !session.right.isEmpty { parts.append("R " + line(session.right)) }
            if !session.sets.isEmpty { parts.append(line(session.sets)) }
            return prefix + parts.joined(separator: "  ")
        }
        return prefix + line(session.sets)
    }

    private var collapsedStatusText: String {
        if isDone { return "done" }
        if logged > 0 { return "\(logged) of \(target) sets" }
        return "not started"
    }

    @ViewBuilder
    private var collapsedStatus: some View {
        HStack(spacing: 10) {
            if isDone, let todaySession {
                if isBodyweight || todaySession.topWeight == nil {
                    Text("Best \(todaySession.allSets.map(\.reps).max() ?? 0) reps")
                    if let previous {
                        let change = todaySession.totalReps - previous.totalReps
                        Text(repChangeText(change)).fontWeight(.semibold)
                            .foregroundStyle(change >= 0 ? theme.posTextColor : theme.negTextColor)
                    }
                } else {
                    Text("Best \(app.score(todaySession.score, bodyweight: false)) \(unitLabel)")
                    if let previous {
                        let change = app.unit.fromKilograms(todaySession.score) - app.unit.fromKilograms(previous.score)
                        Text(GymFormat.delta(change)).fontWeight(.semibold)
                            .foregroundStyle(change >= 0 ? theme.posTextColor : theme.negTextColor)
                    }
                }
            } else if logged > 0 {
                Text("\(logged) of \(target) sets")
            } else if isUpNext {
                Text("Up next")
            } else {
                Text("Not started")
            }
            if item.isExtra { removeExtraButton }
        }
        .font(.system(size: 13 * textScale))
        .foregroundStyle(theme.inkDimColor)
        .fixedSize()
    }

    private func repChangeText(_ change: Int) -> String {
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return "\(sign)\(abs(change)) total rep\(abs(change) == 1 ? "" : "s")"
    }

    private var removeExtraButton: some View {
        IconButton(.close, label: "Remove \(exercise.name) from today", size: 28, iconSize: 14) {
            if app.focusedExerciseId == exercise.id { app.focusedExerciseId = nil }
            app.removeExtra(exerciseId: exercise.id, date: date)
        }
    }

    @ViewBuilder
    private var cardMenu: some View {
        Button("Show history") { app.presentedExerciseId = exercise.id }
        if !isFocused { Button("Log sets") { app.focusedExerciseId = exercise.id } }
        if logged > 0 {
            Divider()
            Button("Clear today's sets", role: .destructive) { app.clearLogs(exerciseId: exercise.id, date: date) }
        }
        if item.isExtra {
            Divider()
            Button("Remove from today") { app.removeExtra(exerciseId: exercise.id, date: date) }
        }
    }

    // MARK: Expanded

    private var expanded: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            if exercise.unilateral { unilateralTable } else { bilateralTable }
            footer
        }
        .contextMenu { cardMenu }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            TodayCardBadge(number: number, style: badgeStyle)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 10) {
                    Button { app.presentedExerciseId = exercise.id } label: {
                        Text(exercise.name)
                            .font(ThubanFont.display(19 * textScale))
                            .foregroundStyle(theme.inkColor)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(exercise.name) history")
                    .accessibilityLabel("\(exercise.name) history")
                    chips
                    if todaySession?.isBest == true { Chip("New e1RM best", kind: .pos) }
                }
                Text(lastTimeLine)
                    .font(.system(size: 13 * textScale))
                    .foregroundStyle(theme.inkFaintColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            headerScore
            if item.isExtra { removeExtraButton }
        }
    }

    /// "Last time, Sun Sep 20 · 135 lb × 8, 8, 8, 7 · e1RM 171.0".
    private var lastTimeLine: String {
        guard let previous else {
            return exercise.targetSpec.map { "First time · target \($0.display)" } ?? "First time"
        }
        func list(_ sets: [SetEntry]) -> String {
            guard let first = sets.first else { return "" }
            if sets.allSatisfy({ $0.weight == first.weight }) {
                return "\(app.weightWithUnit(first.weight)) × " + sets.map { String($0.reps) }.joined(separator: ", ")
            }
            return sets.map { GymFormat.set($0, unit: app.unit) }.joined(separator: ", ")
        }
        if !previous.left.isEmpty || !previous.right.isEmpty {
            var parts = ["Last time"]
            if !previous.left.isEmpty { parts.append("L " + list(previous.left)) }
            if !previous.right.isEmpty { parts.append("R " + list(previous.right)) }
            return parts.joined(separator: " · ")
        }
        let score = isBodyweight || previous.topWeight == nil
            ? "best \(previous.allSets.map(\.reps).max() ?? 0) reps"
            : "e1RM \(app.score(previous.score, bodyweight: false))"
        return "Last time, \(GymFormat.shortDay(previous.date)) · \(list(previous.sets)) · \(score)"
    }

    @ViewBuilder
    private var headerScore: some View {
        if let todaySession {
            let bodyweight = isBodyweight || todaySession.topWeight == nil
            VStack(alignment: .trailing, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(bodyweight ? String(Int(todaySession.score.rounded())) : app.score(todaySession.score, bodyweight: false))
                        .font(ThubanFont.display(22))
                        .foregroundStyle(theme.inkColor)
                        .monospacedDigit()
                    Text(bodyweight ? "reps best" : "\(unitLabel) e1RM")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                }
                if let previous {
                    let change = bodyweight ? todaySession.score - previous.score
                        : app.unit.fromKilograms(todaySession.score) - app.unit.fromKilograms(previous.score)
                    Text("\(GymFormat.delta(change)) vs last · index \(String(format: "%.1f", todaySession.index))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(change >= 0 ? theme.posTextColor : theme.negTextColor)
                } else {
                    Text("index \(String(format: "%.1f", todaySession.index))")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.inkDimColor)
                }
            }
            .fixedSize()
        } else if isUpNext {
            Text("Up next").font(.system(size: 13)).foregroundStyle(theme.inkDimColor)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                addedRows += 1
            } label: {
                HStack(spacing: 7) { Icon(.plus, size: 15); Text("Add set") }
            }
            .buttonStyle(GhostButtonStyle(height: 30, horizontalPadding: 14))
            .accessibilityLabel("Add a set to \(exercise.name)")
            Text("Rest \(GymFormat.elapsed(TimeInterval(app.restSeconds(for: item.sourceWorkout?.id ?? exercise.workoutId)))) between sets")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkFaintColor)
            Spacer(minLength: 8)
            Button { app.presentedExerciseId = exercise.id } label: {
                HStack(spacing: 7) { Icon(.history, size: 15); Text("History") }
            }
            .buttonStyle(GhostButtonStyle(height: 30, tinted: true, horizontalPadding: 12))
            .accessibilityLabel("\(exercise.name) history")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .thubanHairline(.top, color: theme.lineColor)
    }

    // MARK: Table plumbing

    private func columnHeader(_ text: String, width: CGFloat? = nil, alignment: Alignment = .leading) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(theme.inkFaintColor)
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func setNumber(_ index: Int) -> some View {
        Text(String(index + 1))
            .font(ThubanFont.mono(14, weight: .semibold))
            .foregroundStyle(theme.inkDimColor)
            .frame(width: 44, alignment: .leading)
    }

    private func previousText(_ text: String) -> some View {
        Text(text)
            .font(ThubanFont.mono(13.5))
            .foregroundStyle(theme.inkFaintColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ field: String, _ side: Side?, _ index: Int) -> String { "\(field)|\(side?.rawValue ?? "")|\(index)" }

    /// Display-unit text for a stored weight ("140", "" for bodyweight).
    private func weightText(_ kg: Double?) -> String {
        guard let kg else { return "" }
        return GymFormat.number(app.unit.fromKilograms(kg), decimals: 2).replacingOccurrences(of: ",", with: "")
    }

    /// What an open row is pre-filled with: today's last set on that side, else last time's set at that position,
    /// else the progression target, else the target reps at bodyweight.
    private func suggestion(side: Side?, index: Int, logged: [SetEntry], previous: [SetEntry]) -> SetEntry {
        if let last = logged.last { return last }
        if previous.indices.contains(index) { return previous[index] }
        if let last = previous.last { return last }
        if let next = app.nextTarget(exerciseId: exercise.id) { return SetEntry(weight: next.weightKg, reps: next.reps) }
        return SetEntry(weight: nil, reps: exercise.targetSpec?.repsHigh ?? 8)
    }

    private func rowCount(loggedCount: Int) -> Int {
        max(target, loggedCount) + addedRows
    }

    private func typedSet(side: Side?, index: Int, fallback: SetEntry) -> SetEntry {
        let weightText = drafts[key("w", side, index)]
        let repsText = drafts[key("r", side, index)]
        let displayWeight: Double? = weightText.map(TodayInput.weight) ?? app.displayValue(fallback.weight)
        let reps = repsText.flatMap(TodayInput.reps) ?? fallback.reps
        return SetEntry(weight: app.kilograms(fromDisplay: displayWeight), reps: reps)
    }

    /// After a set is checked: start the rest timer and, when nothing is running yet, the planned session.
    private func afterLogging() {
        TodayRestClock.shared.start(seconds: app.restSeconds(for: app.activeSession?.workoutId ?? exercise.workoutId))
        if date == app.today, app.activeSession == nil {
            let plan = app.todayPlan
            if plan.status == .planned || plan.status == .swapped { app.startSession() }
        }
        app.focusedExerciseId = exercise.id
    }

    private func clearDrafts(side: Side?, index: Int) {
        drafts[key("w", side, index)] = nil
        drafts[key("r", side, index)] = nil
    }

    // MARK: Bilateral table

    private var bilateralTable: some View {
        let loggedSets = app.sets(exerciseId: exercise.id, date: date, side: nil)
        let previousSets = previous?.sets ?? previous?.allSets ?? []
        let count = rowCount(loggedCount: loggedSets.count)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                columnHeader("Set", width: 44)
                columnHeader("Previous")
                columnHeader("Weight", width: 96, alignment: .trailing)
                Color.clear.frame(width: 16, height: 1)
                columnHeader("Reps", width: 76, alignment: .trailing)
                columnHeader("e1RM", width: 96, alignment: .trailing)
                Color.clear.frame(width: 32, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            ForEach(0..<count, id: \.self) { index in
                bilateralRow(index: index, logged: loggedSets, previous: previousSets)
            }
        }
    }

    private func bilateralRow(index: Int, logged: [SetEntry], previous: [SetEntry]) -> some View {
        let isLogged = logged.indices.contains(index)
        let fallback = isLogged ? logged[index] : suggestion(side: nil, index: index, logged: logged, previous: previous)
        let shown = isLogged ? logged[index] : typedSet(side: nil, index: index, fallback: fallback)
        let previousText = previous.indices.contains(index) ? GymFormat.set(previous[index], unit: app.unit) : "—"
        return HStack(spacing: 12) {
            setNumber(index)
            self.previousText(previousText)
            TodayNumberField(
                value: isLogged ? weightText(logged[index].weight) : (drafts[key("w", nil, index)] ?? weightText(fallback.weight)),
                placeholder: "BW", suffix: unitLabel, width: 96,
                accessibilityLabel: "Set \(index + 1) weight in \(app.unit == .kg ? "kilograms" : "pounds")",
                isSuggestion: !isLogged && drafts[key("w", nil, index)] == nil, live: !isLogged
            ) { text in
                if isLogged {
                    app.updateSet(exerciseId: exercise.id, date: date, index: index,
                                  weightKg: app.kilograms(fromDisplay: TodayInput.weight(text)), reps: logged[index].reps)
                } else {
                    drafts[key("w", nil, index)] = text
                }
            }
            Text("×").foregroundStyle(theme.inkFaintColor).frame(width: 16)
            TodayNumberField(
                value: isLogged ? String(logged[index].reps) : (drafts[key("r", nil, index)] ?? String(fallback.reps)),
                width: 76, accessibilityLabel: "Set \(index + 1) reps",
                isSuggestion: !isLogged && drafts[key("r", nil, index)] == nil, live: !isLogged
            ) { text in
                if isLogged {
                    if let reps = TodayInput.reps(text) {
                        app.updateSet(exerciseId: exercise.id, date: date, index: index, weightKg: logged[index].weight, reps: reps)
                    }
                } else {
                    drafts[key("r", nil, index)] = text
                }
            } onSubmit: {
                if !isLogged { toggleBilateral(index: index, logged: logged, fallback: fallback) }
            }
            Text(isLogged ? e1RMText(shown) : "—")
                .font(ThubanFont.mono(13.5))
                .foregroundStyle(theme.inkDimColor)
                .frame(width: 96, alignment: .trailing)
            TodayCheckButton(isDone: isLogged, label: isLogged ? "Mark set \(index + 1) not done" : "Mark set \(index + 1) done") {
                toggleBilateral(index: index, logged: logged, fallback: fallback)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .thubanHairline(.top, color: theme.lineColor)
        .contextMenu { rowMenu(index: index, isLogged: isLogged, loggedCount: logged.count, sides: [nil]) }
    }

    private func e1RMText(_ set: SetEntry) -> String {
        set.weight == nil ? "\(set.reps) reps" : app.score(Scoring.e1RM(set), bodyweight: false)
    }

    private func toggleBilateral(index: Int, logged: [SetEntry], fallback: SetEntry) {
        if logged.indices.contains(index) {
            app.removeSet(exerciseId: exercise.id, date: date, index: index)
            return
        }
        let set = typedSet(side: nil, index: index, fallback: fallback)
        app.logSet(exerciseId: exercise.id, date: date, weightKg: set.weight, reps: set.reps)
        clearDrafts(side: nil, index: index)
        if logged.count + 1 > target, addedRows > 0 { addedRows -= 1 }
        afterLogging()
    }

    @ViewBuilder
    private func rowMenu(index: Int, isLogged: Bool, loggedCount: Int, sides: [Side?]) -> some View {
        if isLogged {
            Button("Delete set \(index + 1)", role: .destructive) {
                for side in sides { app.removeSet(exerciseId: exercise.id, date: date, side: side, index: index) }
            }
        } else if addedRows > 0, index >= max(target, loggedCount) {
            Button("Remove this row") { addedRows -= 1 }
        }
    }

    // MARK: Unilateral table

    private var unilateralTable: some View {
        let left = app.sets(exerciseId: exercise.id, date: date, side: .left)
        let right = app.sets(exerciseId: exercise.id, date: date, side: .right)
        let previousLeft = previous?.left ?? []
        let previousRight = previous?.right ?? []
        let count = rowCount(loggedCount: max(left.count, right.count))
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                columnHeader("Set", width: 44)
                columnHeader("Previous L / R")
                columnHeader("Left", width: 190)
                columnHeader("Right", width: 190)
                Color.clear.frame(width: 32, height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            ForEach(0..<count, id: \.self) { index in
                unilateralRow(index: index, left: left, right: right, previousLeft: previousLeft, previousRight: previousRight)
            }
        }
    }

    private func compact(_ sets: [SetEntry], _ index: Int) -> String {
        guard sets.indices.contains(index) else { return "—" }
        return "\(app.weight(sets[index].weight))×\(sets[index].reps)"
    }

    private func unilateralRow(index: Int, left: [SetEntry], right: [SetEntry], previousLeft: [SetEntry], previousRight: [SetEntry]) -> some View {
        let done = left.indices.contains(index) && right.indices.contains(index)
        let previousText = previousLeft.isEmpty && previousRight.isEmpty ? "—" : "\(compact(previousLeft, index)) / \(compact(previousRight, index))"
        return HStack(spacing: 12) {
            setNumber(index)
            self.previousText(previousText)
            sideCell(.left, index: index, logged: left, previous: previousLeft)
            sideCell(.right, index: index, logged: right, previous: previousRight)
            TodayCheckButton(isDone: done, label: done ? "Mark set \(index + 1) not done" : "Mark set \(index + 1) done") {
                toggleUnilateral(index: index, left: left, right: right, previousLeft: previousLeft, previousRight: previousRight)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .thubanHairline(.top, color: theme.lineColor)
        .contextMenu { rowMenu(index: index, isLogged: done, loggedCount: max(left.count, right.count), sides: [.left, .right]) }
    }

    private func sideCell(_ side: Side, index: Int, logged: [SetEntry], previous: [SetEntry]) -> some View {
        let isLogged = logged.indices.contains(index)
        let fallback = isLogged ? logged[index] : suggestion(side: side, index: index, logged: logged, previous: previous)
        return HStack(spacing: 6) {
            Text(side.rawValue)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(theme.brassInkColor)
                .frame(width: 12, alignment: .leading)
            TodayNumberField(
                value: isLogged ? weightText(logged[index].weight) : (drafts[key("w", side, index)] ?? weightText(fallback.weight)),
                placeholder: "BW", suffix: unitLabel, width: 72,
                accessibilityLabel: "Set \(index + 1) \(side.label.lowercased()) weight",
                isSuggestion: !isLogged && drafts[key("w", side, index)] == nil, live: !isLogged
            ) { text in
                if isLogged {
                    app.updateSet(exerciseId: exercise.id, date: date, side: side, index: index,
                                  weightKg: app.kilograms(fromDisplay: TodayInput.weight(text)), reps: logged[index].reps)
                } else {
                    drafts[key("w", side, index)] = text
                }
            }
            Text("×").foregroundStyle(theme.inkFaintColor)
            TodayNumberField(
                value: isLogged ? String(logged[index].reps) : (drafts[key("r", side, index)] ?? String(fallback.reps)),
                width: 50, accessibilityLabel: "Set \(index + 1) \(side.label.lowercased()) reps",
                isSuggestion: !isLogged && drafts[key("r", side, index)] == nil, live: !isLogged
            ) { text in
                if isLogged {
                    if let reps = TodayInput.reps(text) {
                        app.updateSet(exerciseId: exercise.id, date: date, side: side, index: index, weightKg: logged[index].weight, reps: reps)
                    }
                } else {
                    drafts[key("r", side, index)] = text
                }
            }
        }
        .frame(width: 190, alignment: .leading)
    }

    private func toggleUnilateral(index: Int, left: [SetEntry], right: [SetEntry], previousLeft: [SetEntry], previousRight: [SetEntry]) {
        let done = left.indices.contains(index) && right.indices.contains(index)
        if done {
            app.removeSet(exerciseId: exercise.id, date: date, side: .left, index: index)
            app.removeSet(exerciseId: exercise.id, date: date, side: .right, index: index)
            return
        }
        var newMax = max(left.count, right.count)
        for (side, logged, previous) in [(Side.left, left, previousLeft), (Side.right, right, previousRight)] where !logged.indices.contains(index) {
            newMax = max(newMax, logged.count + 1)
            let fallback = suggestion(side: side, index: index, logged: logged, previous: previous)
            let set = typedSet(side: side, index: index, fallback: fallback)
            app.logSet(exerciseId: exercise.id, date: date, side: side, weightKg: set.weight, reps: set.reps)
            clearDrafts(side: side, index: index)
        }
        let grew = max(target, newMax) - max(target, max(left.count, right.count))
        if grew > 0 { addedRows = max(0, addedRows - grew) }
        afterLogging()
    }
}
