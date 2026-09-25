import SwiftUI
import ThubanGymCore

/// Logging a set (boards Logging + LoggingDark): the exercise, last time, the set table, weight and reps cards with
/// ± steppers, the live e1RM against last time, and "Log set 3 · start rest". Tapping a number opens the NATIVE
/// number pad (decimal pad for weight, number pad for reps) with a Done bar; the quick ±2.5 / ±5 / Same chips sit
/// above the keyboard in the page while the weight is being typed.
struct LoggingView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.thubanTheme) private var theme
    var item: SessionExercise
    /// iPad: the panel sits in the split view (no bottom inset; the Log button row is laid out by the caller).
    var embedded = false

    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var focus: LogField?
    @State private var historyId: String?

    enum LogField: Hashable { case weight, reps }

    private var exercise: Exercise { item.exercise }
    private var unit: WeightUnit { app.unit }
    private var date: DayKey { app.sessionDay }
    private var side: Side? { app.editingSet?.side ?? SessionLogic.nextSide(app.data, exercise: exercise, on: date) }
    private var slots: [SetSlot] { SessionLogic.slots(app.data, exercise: exercise, on: date) }
    private var currentSlot: SetSlot? { slots.first { $0.state == .current } }
    private var stepDisplay: Double { unit == .kg ? 2.5 : 5 }

    /// The typed set, in kg.
    private var draft: SetDraft {
        let display = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        return SetDraft(weightKg: display > 0 ? unit.toKilograms(display) : (exercise.bodyweight ? nil : 0), reps: Int(repsText) ?? 0)
    }

    /// Changes whenever the row being logged changes, so the fields refill.
    private var draftKey: String {
        "\(exercise.id)|\(side?.rawValue ?? "-")|\(slots.filter { $0.state == .done }.count)|\(app.editingSet.map { "\($0.index)" } ?? "")|\(unit.rawValue)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleBlock
                if focus == nil {
                    setTable.padding(.top, 16)
                }
                numberCards.padding(.top, focus == nil ? 12 : 16)
                e1rmLine.padding(.top, 12)
                if focus == .weight {
                    quickChips.padding(.top, 12)
                }
            }
            .padding(.horizontal, PhoneMetrics.gutter)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !embedded { bottomBar }
        }
        .onChange(of: draftKey, initial: true) { _, _ in refill() }
        .onChange(of: app.smokeFocus, initial: true) { _, field in
            guard let field else { return }
            focus = field == "reps" ? .reps : (field == "weight" ? .weight : nil)
            app.smokeFocus = nil
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focus == .weight {
                    Button("Reps") { focus = .reps }
                }
                Spacer()
                Button("Done") { focus = nil }.fontWeight(.semibold)
            }
        }
        .sheet(item: Binding(get: { historyId.map(IdentifiedString.init) }, set: { historyId = $0?.id })) { value in
            NavigationStack {
                ExerciseHistoryScreen(exerciseId: value.id, backTitle: nil)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { historyId = nil } } }
            }
            .phoneChrome()
        }
    }

    // MARK: Title

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                Text(exercise.name)
                    .font(PhoneFont.serif(30, relativeTo: .title1))
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                if let spec = exercise.targetSpec { PhoneChip(focus == nil ? spec.display : "Set \((currentSlot?.index ?? 0) + 1) of \(spec.sets)", kind: .neutral, mono: true) }
                if let side { PhoneChip(side.label, kind: .signal) }
                Spacer(minLength: 4)
                IconButton(.history, label: "\(exercise.name) history") { historyId = exercise.id }
                    .padding(.trailing, -10)
            }
            Text(lastTimeLine)
                .font(.subheadline)
                .foregroundStyle(theme.inkDimColor)
                .lineLimit(2)
        }
    }

    private var lastTimeLine: String {
        let done = slots.filter { $0.state == .done }
        if focus != nil, !done.isEmpty, let todays = app.session(exerciseId: exercise.id, on: date) {
            let last = app.previousSession(exerciseId: exercise.id, before: date).flatMap { $0.allSets.last }
            return "Sets 1–\(done.count) \(PhoneFormat.session(todays, unit: unit))" + (last.map { " · last time \(GymFormat.set($0, unit: unit))" } ?? "")
        }
        guard let last = app.previousSession(exerciseId: exercise.id, before: date) else { return "First time. Pick a weight you can do for every set." }
        return "Last time \(GymFormat.shortDay(last.date)) · \(PhoneFormat.session(last, unit: unit))"
    }

    // MARK: Set table

    private var setTable: some View {
        let best = SessionLogic.references(app.data, exerciseId: exercise.id, before: date).best
        return Card {
            HStack(spacing: 0) {
                Text("Set").frame(width: 44, alignment: .leading)
                Text("Weight × reps")
                Spacer()
                Text("e1RM")
            }
            .font(PhoneFont.micro)
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(theme.inkDimColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 34)
            Hairline()
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                if index > 0 && slot.state != .current && slots[index - 1].state != .current { Hairline() }
                row(slot, best: best)
            }
        }
    }

    @ViewBuilder
    private func row(_ slot: SetSlot, best: Double?) -> some View {
        switch slot.state {
        case .done:
            let score = doneScore(slot)
            let gain = best.map { score > $0 + 1e-9 } ?? false
            Button {
                guard !exercise.unilateral, let set = slot.logged else { return }
                app.editingSet = LoggedSet(exerciseId: exercise.id, date: date, side: nil, index: slot.index, set: set)
            } label: {
                HStack(spacing: 0) {
                    Text("\(slot.index + 1)").frame(width: 44, alignment: .leading).foregroundStyle(theme.inkDimColor)
                    Text(doneText(slot)).foregroundStyle(theme.inkColor)
                    Spacer(minLength: 8)
                    Text(app.score(score, bodyweight: slot.logged?.weight == nil))
                        .foregroundStyle(gain ? theme.posTextColor : theme.inkColor)
                    Icon(.check, size: 13, lineWidth: 2.2)
                        .foregroundStyle(theme.posTextColor)
                        .frame(width: 28, height: 28)
                        .background(theme.posSoftColor, in: Circle())
                        .padding(.leading, 12)
                }
                .font(PhoneFont.mono(16, relativeTo: .body))
                .padding(.horizontal, 16)
                .frame(minHeight: 52)
                .background(app.editingSet?.index == slot.index && app.editingSet?.exerciseId == exercise.id ? theme.accentTintColor : .clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Set \(slot.index + 1), \(doneText(slot)), logged")
            .accessibilityHint(exercise.unilateral ? "" : "Edit this set")
            .contextMenu {
                Button("Delete set \(slot.index + 1)", role: .destructive) { deleteSet(slot) }
            }
        case .current:
            HStack(spacing: 0) {
                Text("\(slot.index + 1)").frame(width: 44, alignment: .leading)
                Text(currentText).foregroundStyle(theme.inkColor).fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(app.score(draft.e1RM, bodyweight: draft.entry.weight == nil)).foregroundStyle(theme.inkDimColor)
                Text(app.editingSet == nil ? "NOW" : "EDIT")
                    .font(PhoneFont.micro).kerning(0.6)
                    .foregroundStyle(theme.brassInkColor)
                    .padding(.leading, 12)
            }
            .font(PhoneFont.mono(16, relativeTo: .body))
            .foregroundStyle(theme.brassInkColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(theme.accentTintColor)
            .overlay(alignment: .top) { Rectangle().fill(theme.accentColor).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(theme.accentColor).frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Set \(slot.index + 1), now")
        case .upcoming:
            HStack(spacing: 0) {
                Text("\(slot.index + 1)").frame(width: 44, alignment: .leading)
                Text("\(GymFormat.weight(draft.entry.weight, unit: unit)) × \(draft.reps)")
                Spacer(minLength: 8)
                if let previous = slot.previous {
                    Text("last \(GymFormat.weight(previous.weight, unit: unit))×\(previous.reps)").font(PhoneFont.mono(13))
                }
                Circle().strokeBorder(theme.line2Color, lineWidth: 1).frame(width: 28, height: 28).padding(.leading, 12)
            }
            .font(PhoneFont.mono(16, relativeTo: .body))
            .foregroundStyle(theme.inkFaintColor)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Set \(slot.index + 1), to do")
        }
    }

    private var currentText: String {
        if exercise.unilateral, let current = currentSlot, let left = current.logged {
            return "L \(GymFormat.set(left, unit: unit)) · R …"
        }
        return "\(GymFormat.weight(draft.entry.weight, unit: unit)) × \(draft.reps)"
    }

    private func doneText(_ slot: SetSlot) -> String {
        guard let left = slot.logged else { return "" }
        if let right = slot.loggedRight {
            return left == right ? GymFormat.set(left, unit: unit) + " L/R" : "L \(GymFormat.set(left, unit: unit)) · R \(GymFormat.set(right, unit: unit))"
        }
        return GymFormat.set(left, unit: unit)
    }

    private func doneScore(_ slot: SetSlot) -> Double {
        let left = slot.logged.map(Scoring.e1RM) ?? 0
        guard let right = slot.loggedRight else { return left }
        return min(left, Scoring.e1RM(right))
    }

    private func deleteSet(_ slot: SetSlot) {
        if exercise.unilateral {
            if let left = slot.logged { app.deleteSet(LoggedSet(exerciseId: exercise.id, date: date, side: .left, index: slot.index, set: left)) }
            if let right = slot.loggedRight { app.deleteSet(LoggedSet(exerciseId: exercise.id, date: date, side: .right, index: slot.index, set: right)) }
        } else if let set = slot.logged {
            app.deleteSet(LoggedSet(exerciseId: exercise.id, date: date, side: nil, index: slot.index, set: set))
        }
    }

    // MARK: Weight and reps

    private var numberCards: some View {
        HStack(spacing: 12) {
            numberCard(field: .weight, label: "Weight", text: $weightText, unitLabel: weightIsBodyweight ? "" : unit.label,
                       keyboard: .decimalPad, caption: "Steps of \(GymFormat.number(stepDisplay)) \(unit.label)",
                       minus: { bumpWeight(-stepDisplay) }, plus: { bumpWeight(stepDisplay) },
                       minusLabel: "\(GymFormat.number(stepDisplay)) \(unit.label) less", plusLabel: "\(GymFormat.number(stepDisplay)) \(unit.label) more")
            numberCard(field: .reps, label: "Reps", text: $repsText, unitLabel: "reps", keyboard: .numberPad,
                       caption: exercise.targetSpec.map { $0.repsLow == $0.repsHigh ? "Target \($0.repsLow)" : "Target \($0.repsLow)–\($0.repsHigh)" } ?? "Reps",
                       minus: { bumpReps(-1) }, plus: { bumpReps(1) }, minusLabel: "One fewer rep", plusLabel: "One more rep")
        }
    }

    private var weightIsBodyweight: Bool { exercise.bodyweight && (Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0 }

    private func numberCard(field: LogField, label: String, text: Binding<String>, unitLabel: String, keyboard: UIKeyboardType,
                            caption: String, minus: @escaping () -> Void, plus: @escaping () -> Void,
                            minusLabel: String, plusLabel: String) -> some View {
        let focused = focus == field
        let compact = focus != nil
        return VStack(alignment: compact ? .leading : .center, spacing: compact ? 2 : 8) {
            Eyebrow(label, color: focused ? theme.brassInkColor : theme.inkDimColor)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField(field == .weight && exercise.bodyweight ? "BW" : "0", text: text)
                    .keyboardType(keyboard)
                    .focused($focus, equals: field)
                    .font(PhoneFont.serif(compact ? 40 : 52, relativeTo: .largeTitle))
                    .foregroundStyle(theme.inkColor)
                    .tint(theme.accentColor)
                    .multilineTextAlignment(compact ? .leading : .center)
                    .fixedSize()
                    .accessibilityLabel(label)
                    .accessibilityValue(text.wrappedValue.isEmpty ? (field == .weight && exercise.bodyweight ? "Bodyweight" : "0") : "\(text.wrappedValue) \(unitLabel)")
                if !unitLabel.isEmpty {
                    Text(unitLabel).font(.subheadline.weight(.medium)).foregroundStyle(theme.inkDimColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
            .contentShape(Rectangle())
            .onTapGesture { focus = field }
            if !compact {
                HStack(spacing: 12) {
                    StepButton(icon: .minus, label: minusLabel, action: minus)
                    StepButton(icon: .plus, label: plusLabel, action: plus)
                }
                Text(caption).font(.footnote).foregroundStyle(theme.inkFaintColor)
            }
        }
        .padding(compact ? 14 : 16)
        .frame(maxWidth: .infinity)
        .background(focused ? theme.accentTintColor.opacity(theme.isDark ? 0.5 : 1) : theme.panelColor,
                    in: RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.cardRadius, style: .continuous)
            .strokeBorder(focused ? theme.accentColor : theme.lineColor, lineWidth: focused ? 2 : 1))
    }

    private func bumpWeight(_ delta: Double) {
        let current = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = max(0, current + delta)
        weightText = next == 0 && exercise.bodyweight ? "" : PhoneFormat.fieldWeight(next)
    }

    private func bumpReps(_ delta: Int) {
        repsText = String(max(0, (Int(repsText) ?? 0) + delta))
    }

    // MARK: e1RM and quick chips

    private var e1rmLine: some View {
        let refs = SessionLogic.references(app.data, exerciseId: exercise.id, before: date)
        let bodyweight = draft.entry.weight == nil
        let reference = focus == nil ? (refs.last, "last") : (refs.best, "best")
        let delta = reference.0.map { draft.e1RM - $0 }
        return HStack(spacing: 10) {
            Text("This set").font(.subheadline).foregroundStyle(theme.inkDimColor)
            Text(bodyweight ? "\(draft.reps) reps" : "e1RM \(app.score(draft.e1RM, bodyweight: false)) \(unit.label)")
                .font(PhoneFont.mono(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            if let delta {
                let text = bodyweight ? "\(delta >= 0 ? "+" : "−")\(Int(abs(delta).rounded())) vs \(reference.1)"
                                      : "\(GymFormat.delta(unit.fromKilograms(delta))) vs \(reference.1)"
                PhoneChip(text, kind: GymFormat.tone(for: unit.fromKilograms(delta)) == .pos ? .pos : .neutral)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var quickChips: some View {
        HStack(spacing: 8) {
            chip("−\(GymFormat.number(stepDisplay))", label: "Minus \(GymFormat.number(stepDisplay))") { bumpWeight(-stepDisplay) }
            chip("−\(GymFormat.number(stepDisplay / 2))", label: "Minus \(GymFormat.number(stepDisplay / 2))") { bumpWeight(-stepDisplay / 2) }
            chip("+\(GymFormat.number(stepDisplay / 2))", label: "Plus \(GymFormat.number(stepDisplay / 2))") { bumpWeight(stepDisplay / 2) }
            chip("+\(GymFormat.number(stepDisplay))", label: "Plus \(GymFormat.number(stepDisplay))") { bumpWeight(stepDisplay) }
            if let same = sameAsLast {
                chip("Same", label: "Same as last time, \(GymFormat.weight(same, unit: unit))", wide: true) {
                    weightText = PhoneFormat.fieldWeight(unit.fromKilograms(same))
                }
            }
        }
    }

    /// Last time's weight for this set number.
    private var sameAsLast: Double? { currentSlot?.previous?.weight }

    private func chip(_ text: String, label: String, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(PhoneFont.mono(15, relativeTo: .subheadline, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(theme.panelColor, in: RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: PhoneMetrics.controlRadius, style: .continuous).strokeBorder(theme.line2Color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: wide ? 90 : .infinity)
        .accessibilityLabel(label)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if focus == nil { upNext }
            logButton
        }
        .padding(.horizontal, PhoneMetrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(theme.bgColor)
    }

    var upNext: some View {
        let next = SessionLogic.nextExercise(app.data, items: app.sessionItems.filter { $0.id != exercise.id }, after: nil, on: date)
        return HStack(spacing: 8) {
            Eyebrow("Up next", color: theme.inkFaintColor)
            Text(next.map { "\($0.exercise.name) · \($0.exercise.targetSpec?.display ?? $0.exercise.target)\($0.exercise.unilateral ? " L / R" : "")" } ?? "Last exercise")
                .font(.footnote).foregroundStyle(theme.inkDimColor).lineLimit(1)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Icon(.clock, size: 14)
                Text(PhoneFormat.rest(app.restSeconds(for: app.sessionWorkout?.id))).font(PhoneFont.mono(13))
            }
            .foregroundStyle(theme.inkDimColor)
            .accessibilityLabel("Rest \(PhoneFormat.rest(app.restSeconds(for: app.sessionWorkout?.id)))")
        }
        .padding(.horizontal, 4)
    }

    var logButton: some View {
        Button {
            focus = nil
            app.logSet(exercise, draft: draft)
        } label: {
            HStack(spacing: 10) {
                Icon(.check, size: 18, lineWidth: 2.2)
                Text(logTitle)
            }
        }
        .buttonStyle(PhonePrimaryStyle())
        .disabled(draft.reps <= 0)
    }

    private var logTitle: String {
        let number = (app.editingSet?.index ?? currentSlot?.index ?? 0) + 1
        if app.editingSet != nil { return "Save set \(number)" }
        if side == .left { return "Log set \(number) · left" }
        let base = side == .right ? "Log set \(number) · right" : "Log set \(number)"
        return app.preferences.restAutoStart ? base + " · start rest" : base
    }

    // MARK: Draft

    private func refill() {
        let suggestion: SetDraft
        if let editing = app.editingSet, editing.exerciseId == exercise.id {
            suggestion = SetDraft(weightKg: editing.set.weight, reps: editing.set.reps)
        } else {
            suggestion = SessionLogic.suggestion(app.data, exercise: exercise, on: date, side: side)
        }
        if let kg = suggestion.weightKg, kg > 0 {
            weightText = PhoneFormat.fieldWeight(unit.fromKilograms(kg))
        } else {
            weightText = exercise.bodyweight || suggestion.weightKg == nil ? "" : "0"
        }
        repsText = suggestion.reps > 0 ? String(suggestion.reps) : ""
    }
}

struct IdentifiedString: Identifiable, Hashable {
    var id: String
}
