import Foundation

actor FixtureWorkoutStore: WorkoutDataStore {
    private var logs: [WorkoutSetLog]
    private var nextID = 3

    init() {
        logs = [
            WorkoutSetLog(
                id: "fixture-log-1",
                date: Self.now,
                routineID: 42,
                iteration: 2,
                slotEntryID: 7,
                exerciseID: 123,
                repetitions: "8",
                weight: "60",
                repetitionsUnitID: 1,
                weightUnitID: 1
            ),
            WorkoutSetLog(
                id: "fixture-log-2",
                date: Self.now,
                routineID: 42,
                iteration: 2,
                slotEntryID: 7,
                exerciseID: 123,
                repetitions: "8",
                weight: "60",
                repetitionsUnitID: 1,
                weightUnitID: 1
            ),
        ]
    }

    func dashboard(for date: Date, calendar: Calendar) -> WorkoutDashboard {
        let todayDate = calendar.startOfDay(for: date)
        let nextDate = calendar.date(byAdding: .day, value: 2, to: todayDate) ?? todayDate
        let today = PlannedWorkoutDay(
            routineID: 42,
            routineName: "Strength base",
            dayID: 3,
            name: "Upper body",
            date: todayDate,
            iteration: 2,
            isRest: false,
            exercises: [
                WorkoutExercisePlan(
                    slotEntryID: 7,
                    exerciseID: 123,
                    name: "Barbell bench press",
                    setCount: 3,
                    targetRepetitions: "8",
                    targetWeight: "60",
                    repetitionsUnitID: 1,
                    weightUnitID: 1,
                    repetitionsIncrement: 1,
                    weightIncrement: 2.5,
                    restSeconds: 120,
                    prescription: "3 sets · 8 reps · 60 kg",
                    comment: "Controlled reps"
                ),
                WorkoutExercisePlan(
                    slotEntryID: 8,
                    exerciseID: 456,
                    name: "Barbell row",
                    setCount: 3,
                    targetRepetitions: "10",
                    targetWeight: "45",
                    repetitionsUnitID: 1,
                    weightUnitID: 1,
                    repetitionsIncrement: 1,
                    weightIncrement: 2.5,
                    restSeconds: 90,
                    prescription: "3 sets · 10 reps · 45 kg",
                    comment: nil
                ),
            ]
        )
        let next = PlannedWorkoutDay(
            routineID: 42,
            routineName: "Strength base",
            dayID: 4,
            name: "Lower body",
            date: nextDate,
            iteration: 2,
            isRest: false,
            exercises: [
                WorkoutExercisePlan(
                    slotEntryID: 9,
                    exerciseID: 789,
                    name: "Back squat",
                    setCount: 3,
                    targetRepetitions: "5",
                    targetWeight: "80",
                    repetitionsUnitID: 1,
                    weightUnitID: 1,
                    repetitionsIncrement: 1,
                    weightIncrement: 2.5,
                    restSeconds: 120,
                    prescription: "3 sets · 5 reps · 80 kg",
                    comment: nil
                )
            ]
        )
        return WorkoutDashboard(
            routines: [
                WorkoutRoutine(
                    id: 42,
                    name: "Strength base",
                    description: "Three focused sessions each week",
                    start: "2026-08-01",
                    end: "2026-10-31",
                    days: [today, next]
                ),
                WorkoutRoutine(
                    id: 77,
                    name: "Travel routine",
                    description: "Bodyweight backup plan",
                    start: "2026-07-01",
                    end: "2026-12-31",
                    days: []
                ),
            ],
            today: today,
            logs: logs,
            weightUnits: [
                WorkoutWeightUnit(id: 1, name: "kg"),
                WorkoutWeightUnit(id: 2, name: "lb"),
                WorkoutWeightUnit(id: 3, name: "Body Weight"),
                WorkoutWeightUnit(id: 4, name: "Plates"),
            ],
            repetitionUnits: [
                WorkoutRepetitionUnit(id: 1, name: "Repetitions"),
                WorkoutRepetitionUnit(id: 2, name: "Until failure"),
            ]
        )
    }

    func createSet(
        for plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) {
        logs.append(
            WorkoutSetLog(
                id: "fixture-log-\(nextID)",
                date: Self.now,
                routineID: day.routineID,
                iteration: day.iteration,
                slotEntryID: plan.slotEntryID,
                exerciseID: plan.exerciseID,
                repetitions: input.repetitions,
                weight: input.weight,
                repetitionsUnitID: input.repetitionsUnitID ?? plan.repetitionsUnitID,
                weightUnitID: input.weightUnitID ?? plan.weightUnitID
            )
        )
        nextID += 1
    }

    func updateSet(id: String, input: WorkoutSetInput) {
        guard let index = logs.firstIndex(where: { $0.id == id }) else { return }
        let log = logs[index]
        logs[index] = WorkoutSetLog(
            id: log.id,
            date: log.date,
            routineID: log.routineID,
            iteration: log.iteration,
            slotEntryID: log.slotEntryID,
            exerciseID: log.exerciseID,
            repetitions: input.repetitions,
            weight: input.weight,
            repetitionsUnitID: input.repetitionsUnitID ?? log.repetitionsUnitID,
            weightUnitID: input.weightUnitID ?? log.weightUnitID
        )
    }

    func deleteSet(id: String) {
        logs.removeAll { $0.id == id }
    }

    nonisolated static let now = Date(timeIntervalSince1970: 1_786_492_800)
}
