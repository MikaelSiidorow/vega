import Foundation

nonisolated struct WorkoutDashboard: Equatable, Sendable {
    let routines: [WorkoutRoutine]
    let today: PlannedWorkoutDay?
    let logs: [WorkoutSetLog]
    let weightUnits: [WorkoutWeightUnit]
    let repetitionUnits: [WorkoutRepetitionUnit]

    static let empty = WorkoutDashboard(
        routines: [],
        today: nil,
        logs: [],
        weightUnits: [],
        repetitionUnits: []
    )
}

nonisolated struct WorkoutWeightUnit: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct WorkoutRepetitionUnit: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
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
    var id: String { "\(routineID)-\(dayID)-\(iteration)-\(date.timeIntervalSinceReferenceDate)" }

    let routineID: Int
    let routineName: String
    let dayID: Int
    let name: String
    let date: Date
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
    let repetitionsIncrement: Decimal
    let weightIncrement: Decimal
    let restSeconds: Int
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
    let repetitionsUnitID: Int?
    let weightUnitID: Int?
}

nonisolated struct WorkoutSetInput: Equatable, Sendable {
    let repetitions: String?
    let weight: String?
    let repetitionsUnitID: Int?
    let weightUnitID: Int?

    init(
        repetitions: String?,
        weight: String?,
        repetitionsUnitID: Int? = nil,
        weightUnitID: Int? = nil
    ) {
        self.repetitions = repetitions
        self.weight = weight
        self.repetitionsUnitID = repetitionsUnitID
        self.weightUnitID = weightUnitID
    }
}
