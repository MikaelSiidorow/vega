import Foundation
import SwiftUI

// The start/log/rest/summary sequence is adapted from wger Flutter's gym mode:
// lib/features/routines/widgets/gym_mode, revision 6eb6197923517a64487697d138caf60ea17216ef.
// This view uses native SwiftUI structure and controls rather than porting Flutter widgets.

struct WorkoutSessionView: View {
    @Bindable var model: WorkoutScreenModel
    let session: WorkoutSessionPlan
    let weightUnits: [WorkoutWeightUnit]
    let repetitionUnits: [WorkoutRepetitionUnit]

    @Environment(\.dismiss) private var dismiss
    @State private var phase = Phase.overview
    @State private var currentStepIndex = 0
    @State private var completedInSession = 0
    @State private var startedAt: Date?
    @State private var restEnd = Date()
    @State private var lastInputByExercise: [Int: WorkoutSetInput] = [:]
    @State private var inputByStep: [String: WorkoutSetInput] = [:]

    private enum Phase: Equatable {
        case overview
        case logging
        case resting
        case summary
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .overview:
                    overview
                case .logging:
                    setLogging
                case .resting:
                    restTimer
                case .summary:
                    summary
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("close-workout-session")
                }
                ToolbarItem(placement: .principal) {
                    Text(navigationTitle)
                        .font(.headline)
                }
            }
        }
        .interactiveDismissDisabled(phase != .overview && phase != .summary)
        .accessibilityIdentifier("focused-workout")
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VegaSpacing.spacious) {
                VStack(alignment: .leading, spacing: VegaSpacing.small) {
                    Text(session.day.name)
                        .font(.largeTitle.bold())
                    Text(session.day.routineName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(
                        session.day.date,
                        format: .dateTime.weekday(.wide).month(.wide).day()
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: VegaSpacing.standard) {
                    summaryHeader
                    ForEach(session.day.exercises) { plan in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: VegaSpacing.compact) {
                                Text(plan.name)
                                    .font(.headline)
                                Text(plan.prescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(completedCount(for: plan))/\(plan.setCount)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if plan.id != session.day.exercises.last?.id {
                            Divider()
                        }
                    }
                }
                .vegaCard()

                if session.isComplete {
                    Label(
                        "All prescribed sets are already logged",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vegaCard()
                }

                Button {
                    guard !session.isComplete else {
                        phase = .summary
                        return
                    }
                    startedAt = Date()
                    phase = .logging
                } label: {
                    Label(
                        session.isComplete ? "Review workout" : "Begin workout",
                        systemImage: session.isComplete ? "checkmark.circle" : "play.fill"
                    )
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("begin-workout")
            }
            .padding(VegaSpacing.comfortable)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("workout-session-overview")
    }

    @ViewBuilder private var setLogging: some View {
        if let step = currentStep {
            ScrollView {
                VStack(alignment: .leading, spacing: VegaSpacing.spacious) {
                    sessionProgress(step)

                    VStack(alignment: .leading, spacing: VegaSpacing.small) {
                        Text(step.plan.name)
                            .font(.largeTitle.bold())
                        Text("Set \(step.setNumber) of \(step.plan.setCount)")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        if let comment = step.plan.comment {
                            Text(comment)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }

                    targetAndPrevious(step)

                    WorkoutSetEntryForm(
                        plan: step.plan,
                        previousLog: step.previousLog,
                        suggestedInput: lastInputByExercise[step.plan.slotEntryID],
                        weightUnits: weightUnits,
                        repetitionUnits: repetitionUnits,
                        submitTitle: "Complete set",
                        submitSystemImage: "checkmark.circle.fill"
                    ) { input in
                        let didSave = await model.createSet(
                            for: step.plan,
                            day: session.day,
                            input: input
                        )
                        guard didSave else { return false }
                        lastInputByExercise[step.plan.slotEntryID] = input
                        inputByStep[step.id] = input
                        completedInSession += 1
                        if currentStepIndex + 1 >= session.pendingSteps.count {
                            phase = .summary
                        } else {
                            restEnd = Date().addingTimeInterval(TimeInterval(step.plan.restSeconds))
                            phase = .resting
                        }
                        return true
                    }
                    .id(step.id)
                }
                .padding(VegaSpacing.comfortable)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .accessibilityIdentifier("workout-set-step-\(step.id)")
        }
    }

    private var restTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let secondsRemaining = restSecondsRemaining(at: context.date)
            VStack(spacing: VegaSpacing.spacious) {
                Spacer()
                Text("Rest")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("workout-rest")
                Text(restDescription(at: context.date))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("workout-rest-timer")
                if let nextStep {
                    VStack(spacing: VegaSpacing.compact) {
                        Text("Up next")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(nextStep.plan.name)
                            .font(.title2.weight(.semibold))
                        Text("Set \(nextStep.setNumber) of \(nextStep.plan.setCount)")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    advanceAfterRest()
                } label: {
                    Label(
                        secondsRemaining > 0 ? "Skip rest" : "Next set",
                        systemImage: secondsRemaining > 0 ? "forward.fill" : "arrow.right"
                    )
                    .labelStyle(.titleAndIcon)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("advance-workout-after-rest")
            }
            .padding(VegaSpacing.spacious)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VegaSpacing.spacious) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                VStack(spacing: VegaSpacing.small) {
                    Text("Workout complete")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("workout-session-summary")
                    Text(session.day.name)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: VegaSpacing.standard) {
                    summaryMetric(
                        title: "Sets",
                        value:
                            "\(session.completedSetCount + completedInSession)/\(session.totalSetCount)"
                    )
                    summaryMetric(title: "Exercises", value: "\(session.day.exercises.count)")
                }

                if let startedAt {
                    VStack(alignment: .leading, spacing: VegaSpacing.small) {
                        Text("Duration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(startedAt, style: .timer)
                            .font(.title.weight(.semibold).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .vegaCard()
                }

                VStack(alignment: .leading, spacing: VegaSpacing.standard) {
                    Text("Completed sets")
                        .font(.title2.bold())
                    ForEach(session.day.exercises) { plan in
                        summaryExercise(plan)
                    }
                }
            }
            .padding(VegaSpacing.comfortable)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Finish")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("finish-workout")
            .padding(.horizontal, VegaSpacing.comfortable)
            .padding(.vertical, VegaSpacing.standard)
            .background(.bar)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var navigationTitle: String {
        switch phase {
        case .overview:
            "Today's workout"
        case .logging:
            "Current set"
        case .resting:
            "Rest timer"
        case .summary:
            "Summary"
        }
    }

    private var currentStep: WorkoutSetStep? {
        guard session.pendingSteps.indices.contains(currentStepIndex) else { return nil }
        return session.pendingSteps[currentStepIndex]
    }

    private var nextStep: WorkoutSetStep? {
        let index = currentStepIndex + 1
        guard session.pendingSteps.indices.contains(index) else { return nil }
        return session.pendingSteps[index]
    }

    private var summaryHeader: some View {
        HStack {
            Text("Plan")
                .font(.title3.weight(.bold))
            Spacer()
            Text("\(session.completedSetCount)/\(session.totalSetCount) sets logged")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func completedCount(for plan: WorkoutExercisePlan) -> Int {
        let pending = session.pendingSteps.count { $0.plan.slotEntryID == plan.slotEntryID }
        return plan.setCount - pending
    }

    private func sessionProgress(_ step: WorkoutSetStep) -> some View {
        VStack(alignment: .leading, spacing: VegaSpacing.small) {
            HStack {
                Text("Set \(step.overallNumber) of \(step.totalSetCount)")
                    .font(.headline.monospacedDigit())
                Spacer()
                if let startedAt {
                    Text(startedAt, style: .timer)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            VegaProgressBar(
                value: Double(step.overallNumber - 1) / Double(max(step.totalSetCount, 1)),
                height: 8
            )
        }
    }

    private func targetAndPrevious(_ step: WorkoutSetStep) -> some View {
        HStack(alignment: .top, spacing: VegaSpacing.standard) {
            VStack(alignment: .leading, spacing: VegaSpacing.compact) {
                Text("Target")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(step.plan.prescription)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let previous = step.previousLog {
                VStack(alignment: .leading, spacing: VegaSpacing.compact) {
                    Text("Previous")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(logDescription(previous))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .vegaCard()
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: VegaSpacing.small) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vegaCard()
    }

    private func summaryExercise(_ plan: WorkoutExercisePlan) -> some View {
        VStack(alignment: .leading, spacing: VegaSpacing.standard) {
            VStack(alignment: .leading, spacing: VegaSpacing.compact) {
                Text(plan.name)
                    .font(.headline)
                    .accessibilityIdentifier(
                        "workout-summary-exercise-\(plan.slotEntryID)"
                    )
                Text(plan.prescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(0..<plan.setCount, id: \.self) { setIndex in
                HStack(alignment: .firstTextBaseline) {
                    Text("Set \(setIndex + 1)")
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(summaryDescription(for: plan, setIndex: setIndex))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(
                    "workout-summary-set-\(plan.slotEntryID)-\(setIndex + 1)"
                )
            }
        }
        .vegaCard()
    }

    private func summaryDescription(
        for plan: WorkoutExercisePlan,
        setIndex: Int
    ) -> String {
        let completedLogs = session.completedLogsBySlot[plan.slotEntryID] ?? []
        if completedLogs.indices.contains(setIndex) {
            return logDescription(completedLogs[setIndex])
        }

        let stepID = "\(plan.slotEntryID)-\(setIndex + 1)"
        guard let input = inputByStep[stepID] else { return "Not logged" }
        return setDescription(
            repetitions: input.repetitions,
            weight: input.weight,
            repetitionsUnitID: input.repetitionsUnitID,
            weightUnitID: input.weightUnitID
        )
    }

    private func logDescription(_ log: WorkoutSetLog) -> String {
        setDescription(
            repetitions: log.repetitions,
            weight: log.weight,
            repetitionsUnitID: log.repetitionsUnitID,
            weightUnitID: log.weightUnitID
        )
    }

    private func setDescription(
        repetitions: String?,
        weight: String?,
        repetitionsUnitID: Int?,
        weightUnitID: Int?
    ) -> String {
        let repetitionUnit =
            repetitionUnits.first { $0.id == repetitionsUnitID }?.name ?? "reps"
        let weightUnit = weightUnits.first { $0.id == weightUnitID }?.name ?? "kg"
        let repetitionsDescription = measurementDescription(
            value: repetitions,
            unit: repetitionUnit,
            unitIsShortcut: repetitionUnit.localizedCaseInsensitiveContains("failure")
        )
        let weightDescription = measurementDescription(
            value: weight,
            unit: weightUnit,
            unitIsShortcut: weightUnit.localizedCaseInsensitiveContains("body weight")
        )
        return "\(repetitionsDescription) · \(weightDescription)"
    }

    private func measurementDescription(
        value: String?,
        unit: String,
        unitIsShortcut: Bool
    ) -> String {
        if unitIsShortcut { return unit }
        return value.map { "\($0) \(unit)" } ?? unit
    }

    private func restDescription(at date: Date) -> String {
        let seconds = restSecondsRemaining(at: date)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func restSecondsRemaining(at date: Date) -> Int {
        max(0, Int(restEnd.timeIntervalSince(date).rounded(.up)))
    }

    private func advanceAfterRest() {
        currentStepIndex += 1
        phase = .logging
    }
}

struct WorkoutSetEntryForm: View {
    let plan: WorkoutExercisePlan
    let previousLog: WorkoutSetLog?
    let suggestedInput: WorkoutSetInput?
    let weightUnits: [WorkoutWeightUnit]
    let repetitionUnits: [WorkoutRepetitionUnit]
    let submitTitle: String
    let submitSystemImage: String
    let save: (WorkoutSetInput) async -> Bool

    @State private var repetitions: String
    @State private var weight: String
    @State private var repetitionUnitID: Int?
    @State private var weightUnitID: Int?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case repetitions
        case weight
    }

    init(
        plan: WorkoutExercisePlan,
        previousLog: WorkoutSetLog?,
        suggestedInput: WorkoutSetInput?,
        weightUnits: [WorkoutWeightUnit],
        repetitionUnits: [WorkoutRepetitionUnit],
        submitTitle: String,
        submitSystemImage: String,
        save: @escaping (WorkoutSetInput) async -> Bool
    ) {
        self.plan = plan
        self.previousLog = previousLog
        self.suggestedInput = suggestedInput
        self.weightUnits = weightUnits
        self.repetitionUnits = repetitionUnits
        self.submitTitle = submitTitle
        self.submitSystemImage = submitSystemImage
        self.save = save

        _repetitions = State(
            initialValue: suggestedInput?.repetitions ?? previousLog?.repetitions
                ?? plan.targetRepetitions ?? ""
        )
        _weight = State(
            initialValue: suggestedInput?.weight ?? previousLog?.weight ?? plan.targetWeight ?? ""
        )
        _repetitionUnitID = State(
            initialValue: suggestedInput?.repetitionsUnitID ?? previousLog?.repetitionsUnitID
                ?? plan.repetitionsUnitID
        )
        _weightUnitID = State(
            initialValue: suggestedInput?.weightUnitID ?? previousLog?.weightUnitID
                ?? plan.weightUnitID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VegaSpacing.comfortable) {
            Text("Your result")
                .font(.title2.weight(.bold))

            valueSection(
                title: "Repetitions",
                value: $repetitions,
                increment: plan.repetitionsIncrement,
                unitPicker: AnyView(repetitionUnitPicker),
                isShortcut: isUntilFailure,
                shortcutLabel: "Until failure",
                identifier: "workout-repetitions",
                field: .repetitions
            )

            valueSection(
                title: "Weight",
                value: $weight,
                increment: plan.weightIncrement,
                unitPicker: AnyView(weightUnitPicker),
                isShortcut: isBodyWeight,
                shortcutLabel: "Body weight",
                identifier: "workout-weight",
                field: .weight
            )

            Button {
                isSaving = true
                Task {
                    let didSave = await save(input)
                    if !didSave { isSaving = false }
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(submitTitle, systemImage: submitSystemImage)
                        .labelStyle(.titleAndIcon)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isValid || isSaving)
            .accessibilityIdentifier("save-workout-set")
        }
        .vegaCard()
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
    }

    private var repetitionUnitPicker: some View {
        Picker("Repetition unit", selection: $repetitionUnitID) {
            ForEach(repetitionUnits) { unit in
                Text(unit.name).tag(Optional(unit.id))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("workout-repetition-unit")
    }

    private var weightUnitPicker: some View {
        Picker("Weight unit", selection: $weightUnitID) {
            ForEach(weightUnits) { unit in
                Text(unit.name).tag(Optional(unit.id))
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("workout-weight-unit")
    }

    private func valueSection(
        title: String,
        value: Binding<String>,
        increment: Decimal,
        unitPicker: AnyView,
        isShortcut: Bool,
        shortcutLabel: String,
        identifier: String,
        field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: VegaSpacing.small) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                unitPicker
            }
            if isShortcut {
                Label(shortcutLabel, systemImage: "figure.strengthtraining.traditional")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VegaSpacing.comfortable)
                    .background(
                        Color(uiColor: .tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .accessibilityIdentifier(identifier)
            } else {
                HStack(spacing: VegaSpacing.standard) {
                    Button("Decrease \(title.lowercased())", systemImage: "minus") {
                        value.wrappedValue = adjusted(value.wrappedValue, by: -increment)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    TextField(title, text: value)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: field)
                        .accessibilityIdentifier(identifier)

                    Button("Increase \(title.lowercased())", systemImage: "plus") {
                        value.wrappedValue = adjusted(value.wrappedValue, by: increment)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(VegaSpacing.small)
                .background(
                    Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }

    private var isUntilFailure: Bool {
        repetitionUnits.first { $0.id == repetitionUnitID }?.name.localizedCaseInsensitiveContains(
            "failure"
        ) == true
    }

    private var isBodyWeight: Bool {
        weightUnits.first { $0.id == weightUnitID }?.name.localizedCaseInsensitiveContains(
            "body weight"
        ) == true
    }

    private var input: WorkoutSetInput {
        WorkoutSetInput(
            repetitions: isUntilFailure ? nil : normalized(repetitions),
            weight: isBodyWeight ? "1" : normalized(weight),
            repetitionsUnitID: repetitionUnitID,
            weightUnitID: weightUnitID
        )
    }

    private var isValid: Bool {
        let validRepetitions = isUntilFailure || positiveDecimal(repetitions)
        let validWeight = isBodyWeight || nonnegativeDecimal(weight)
        return validRepetitions && validWeight
    }

    private func positiveDecimal(_ value: String) -> Bool {
        guard let value = decimal(value) else { return false }
        return value > 0
    }

    private func nonnegativeDecimal(_ value: String) -> Bool {
        guard let value = decimal(value) else { return false }
        return value >= 0
    }

    private func adjusted(_ value: String, by change: Decimal) -> String {
        let current = decimal(value) ?? 0
        return NSDecimalNumber(decimal: max(0, current + change)).stringValue
    }

    private func decimal(_ value: String) -> Decimal? {
        Decimal(string: normalized(value) ?? "", locale: Locale(identifier: "en_US_POSIX"))
    }

    private func normalized(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: ",",
            with: "."
        )
        return value.isEmpty ? nil : value
    }
}
