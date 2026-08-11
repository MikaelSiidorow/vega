import Foundation
import SwiftUI

struct WorkoutsView: View {
    @Bindable var model: WorkoutScreenModel
    let instanceName: String
    let signOut: () -> Void

    @State private var editor: WorkoutSetEditorContext?
    @State private var pendingDeletion: WorkoutSetLog?

    var body: some View {
        Group {
            switch model.phase {
            case .idle, .loading:
                ProgressView("Loading workouts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t load workouts", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { Task { await model.load() } }
                }
            case .loaded(let dashboard):
                dashboardView(dashboard)
            }
        }
        .navigationTitle("Workouts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Text(instanceName)
                    Button("Sign out", role: .destructive, action: signOut)
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $editor) { context in
            WorkoutSetForm(context: context) { input in
                let didSave: Bool
                if let log = context.log {
                    didSave = await model.updateSet(id: log.id, input: input)
                } else {
                    didSave = await model.createSet(
                        for: context.plan, day: context.day, input: input)
                }
                if didSave { editor = nil }
                return didSave
            }
        }
        .alert(
            "Delete this set?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            )
        ) {
            Button("Delete set", role: .destructive) {
                guard let id = pendingDeletion?.id else { return }
                pendingDeletion = nil
                Task { await model.deleteSet(id: id) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This permanently removes the recorded set.")
        }
        .alert(
            "Couldn’t change workout",
            isPresented: Binding(
                get: { model.mutationErrorMessage != nil },
                set: { if !$0 { model.mutationErrorMessage = nil } }
            )
        ) {
            Button("OK") { model.mutationErrorMessage = nil }
        } message: {
            Text(model.mutationErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private func dashboardView(_ dashboard: WorkoutDashboard) -> some View {
        if dashboard.routines.isEmpty {
            ContentUnavailableView(
                "No workout routines",
                systemImage: "dumbbell.fill",
                description: Text("Create a routine in wger to see its training days here.")
            )
        } else {
            List {
                Section("Today") {
                    if let today = dashboard.today {
                        if today.isRest || today.exercises.isEmpty {
                            Label("Rest day", systemImage: "bed.double.fill")
                        } else {
                            todayHeader(today)
                            ForEach(today.exercises) { plan in
                                exercisePlan(plan, day: today, logs: dashboard.logs)
                            }
                        }
                    } else {
                        ContentUnavailableView(
                            "Nothing planned today",
                            systemImage: "calendar",
                            description: Text("Your routines have no workout scheduled for today.")
                        )
                    }
                }

                Section("Routines") {
                    ForEach(dashboard.routines) { routine in
                        NavigationLink {
                            RoutinePlanView(routine: routine)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(routine.name)
                                    .font(.body.weight(.medium))
                                if let description = routine.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Text("\(routine.days.count) scheduled days")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("workout-routine-\(routine.id)")
                    }
                }
            }
            .accessibilityIdentifier("workout-dashboard")
            .refreshable { await model.load() }
        }
    }

    private func todayHeader(_ day: PlannedWorkoutDay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(day.name)
                .font(.title3.weight(.semibold))
            Text("\(day.routineName) · iteration \(day.iteration)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("today-workout")
    }

    private func exercisePlan(
        _ plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        logs: [WorkoutSetLog]
    ) -> some View {
        let completed = logs.filter { $0.slotEntryID == plan.slotEntryID }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name)
                        .font(.headline)
                        .accessibilityIdentifier("workout-exercise-\(plan.slotEntryID)")
                    Text(plan.prescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(completed.count)/\(plan.setCount)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let comment = plan.comment {
                Text(comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !completed.isEmpty {
                HStack {
                    Label("Logged today", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Correct a set")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            ForEach(Array(completed.enumerated()), id: \.element.id) { index, log in
                HStack {
                    Label("Set \(index + 1)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text(logDescription(log))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("workout-log-\(log.id)")
                    Button("Edit set", systemImage: "pencil") {
                        editor = WorkoutSetEditorContext(day: day, plan: plan, log: log)
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Edit logged set \(index + 1)")
                    .accessibilityIdentifier("edit-workout-log-\(log.id)")
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        pendingDeletion = log
                    }
                    .accessibilityIdentifier("delete-workout-log-\(log.id)")
                }
            }
            if completed.count < plan.setCount {
                Button("Log set", systemImage: "plus.circle.fill") {
                    editor = WorkoutSetEditorContext(day: day, plan: plan, log: nil)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("log-workout-set-\(plan.slotEntryID)")
            }
        }
        .padding(.vertical, 5)
    }

    private func logDescription(_ log: WorkoutSetLog) -> String {
        "\(log.repetitions ?? "—") reps · \(log.weight ?? "—") kg"
    }
}

private struct RoutinePlanView: View {
    let routine: WorkoutRoutine

    var body: some View {
        List {
            if let description = routine.description {
                Text(description)
                    .foregroundStyle(.secondary)
            }
            ForEach(routine.days) { day in
                Section {
                    if day.isRest {
                        Label("Rest day", systemImage: "bed.double.fill")
                    } else {
                        ForEach(day.exercises) { exercise in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name)
                                    .font(.body.weight(.medium))
                                Text(exercise.prescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        Text(
                            day.date,
                            format: .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                        )
                        Text(" · \(day.name)")
                    }
                }
            }
        }
        .navigationTitle(routine.name)
        .accessibilityIdentifier("routine-plan")
    }
}

private struct WorkoutSetEditorContext: Identifiable {
    var id: String { log?.id ?? "new-\(plan.slotEntryID)" }

    let day: PlannedWorkoutDay
    let plan: WorkoutExercisePlan
    let log: WorkoutSetLog?
}

private struct WorkoutSetForm: View {
    let context: WorkoutSetEditorContext
    let save: (WorkoutSetInput) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var repetitions: String
    @State private var weight: String
    @State private var isSaving = false

    init(
        context: WorkoutSetEditorContext,
        save: @escaping (WorkoutSetInput) async -> Bool
    ) {
        self.context = context
        self.save = save
        _repetitions = State(
            initialValue: context.log?.repetitions ?? context.plan.targetRepetitions ?? "")
        _weight = State(initialValue: context.log?.weight ?? context.plan.targetWeight ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Exercise", value: context.plan.name)
                    LabeledContent("Target", value: context.plan.prescription)
                }
                Section("Completed set") {
                    TextField("Repetitions", text: $repetitions)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("workout-repetitions")
                    TextField("Weight (kg)", text: $weight)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("workout-weight")
                }
            }
            .navigationTitle(context.log == nil ? "Log set" : "Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            _ = await save(
                                WorkoutSetInput(
                                    repetitions: normalized(repetitions),
                                    weight: normalized(weight)
                                )
                            )
                            isSaving = false
                        }
                    }
                    .disabled(!isValid || isSaving)
                    .accessibilityIdentifier("save-workout-set")
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var isValid: Bool {
        guard let repetitions = decimal(repetitions), repetitions > 0,
            let weight = decimal(weight), weight >= 0
        else { return false }
        return true
    }

    private func decimal(_ value: String) -> Decimal? {
        Decimal(string: normalized(value), locale: Locale(identifier: "en_US_POSIX"))
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(
            of: ",",
            with: "."
        )
    }
}
