import Foundation

nonisolated struct WorkoutDashboard: Equatable, Sendable {
    let routines: [WorkoutRoutine]
    let today: PlannedWorkoutDay?
    let logs: [WorkoutSetLog]

    static let empty = WorkoutDashboard(routines: [], today: nil, logs: [])
}

nonisolated struct WorkoutRoutine: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let start: String
    let end: String
    let days: [PlannedWorkoutDay]
}

nonisolated struct PlannedWorkoutDay: Equatable, Identifiable, Sendable {
    var id: String { "\(routineID)-\(date)-\(dayID)" }

    let routineID: Int
    let routineName: String
    let dayID: Int
    let name: String
    let date: String
    let iteration: Int
    let isRest: Bool
    let exercises: [WorkoutExercisePlan]
}

nonisolated struct WorkoutExercisePlan: Equatable, Identifiable, Sendable {
    var id: Int { slotEntryID }

    let slotEntryID: Int
    let exerciseID: Int
    let name: String
    let setCount: Int
    let targetRepetitions: String?
    let targetWeight: String?
    let repetitionsUnitID: Int?
    let weightUnitID: Int?
    let prescription: String
    let comment: String?
}

nonisolated struct WorkoutSetLog: Equatable, Identifiable, Sendable {
    let id: String
    let date: Date?
    let routineID: Int?
    let iteration: Int?
    let slotEntryID: Int?
    let exerciseID: Int
    let repetitions: String?
    let weight: String?
}

nonisolated struct WorkoutSetInput: Equatable, Sendable {
    let repetitions: String
    let weight: String
}
