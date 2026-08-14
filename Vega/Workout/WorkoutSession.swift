import Foundation

// The start/log/rest/summary sequence is adapted from wger Flutter's gym mode:
// lib/features/routines/widgets/gym_mode, revision 6eb6197923517a64487697d138caf60ea17216ef.
// The state model and Swift implementation are original to Vega.

nonisolated struct WorkoutSetStep: Equatable, Identifiable, Sendable {
    var id: String { "\(plan.slotEntryID)-\(setNumber)" }

    let plan: WorkoutExercisePlan
    let setNumber: Int
    let overallNumber: Int
    let totalSetCount: Int
    let previousLog: WorkoutSetLog?
}

nonisolated struct WorkoutSessionPlan: Equatable, Sendable {
    let day: PlannedWorkoutDay
    let completedLogsBySlot: [Int: [WorkoutSetLog]]
    let pendingSteps: [WorkoutSetStep]
    let completedSetCount: Int
    let totalSetCount: Int

    init(day: PlannedWorkoutDay, logs: [WorkoutSetLog]) {
        self.day = day
        totalSetCount = day.exercises.reduce(0) { $0 + $1.setCount }

        var completedSetCount = 0
        var completedLogsBySlot: [Int: [WorkoutSetLog]] = [:]
        var overallNumber = 0
        var pendingSteps: [WorkoutSetStep] = []

        for plan in day.exercises {
            let completedLogs = Array(
                logs.filter { $0.slotEntryID == plan.slotEntryID }.prefix(plan.setCount)
            )
            let completedForExercise = completedLogs.count
            completedLogsBySlot[plan.slotEntryID] = completedLogs
            completedSetCount += completedForExercise

            for setIndex in 0..<plan.setCount {
                overallNumber += 1
                guard setIndex >= completedForExercise else { continue }
                pendingSteps.append(
                    WorkoutSetStep(
                        plan: plan,
                        setNumber: setIndex + 1,
                        overallNumber: overallNumber,
                        totalSetCount: totalSetCount,
                        previousLog: completedLogs.last
                    )
                )
            }
        }

        self.completedSetCount = completedSetCount
        self.completedLogsBySlot = completedLogsBySlot
        self.pendingSteps = pendingSteps
    }

    var isComplete: Bool { pendingSteps.isEmpty }
}
