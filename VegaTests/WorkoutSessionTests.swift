import Foundation
import Testing

@testable import Vega

nonisolated struct WorkoutSessionTests {
    @Test
    func startsAtFirstIncompleteSetAndKeepsOverallProgress() {
        let day = Self.day
        let logs = [
            Self.log(id: "one", slotEntryID: 7),
            Self.log(id: "two", slotEntryID: 7),
        ]

        let session = WorkoutSessionPlan(day: day, logs: logs)

        #expect(session.completedSetCount == 2)
        #expect(session.totalSetCount == 5)
        #expect(session.pendingSteps.map(\.id) == ["7-3", "8-1", "8-2"])
        #expect(session.pendingSteps.map(\.overallNumber) == [3, 4, 5])
        #expect(session.pendingSteps.first?.previousLog?.id == "two")
        #expect(session.completedLogsBySlot[7]?.map(\.id) == ["one", "two"])
        #expect(session.completedLogsBySlot[8]?.isEmpty == true)
    }

    @Test
    func recognizesCompletedWorkout() {
        let logs = [
            Self.log(id: "one", slotEntryID: 7),
            Self.log(id: "two", slotEntryID: 7),
            Self.log(id: "three", slotEntryID: 7),
            Self.log(id: "four", slotEntryID: 8),
            Self.log(id: "five", slotEntryID: 8),
        ]

        let session = WorkoutSessionPlan(day: Self.day, logs: logs)

        #expect(session.isComplete)
        #expect(session.completedSetCount == session.totalSetCount)
        #expect(session.completedLogsBySlot[7]?.count == 3)
        #expect(session.completedLogsBySlot[8]?.count == 2)
    }

    private static let day = PlannedWorkoutDay(
        routineID: 42,
        routineName: "Strength base",
        dayID: 3,
        name: "Upper body",
        date: FixtureWorkoutStore.now,
        iteration: 2,
        isRest: false,
        exercises: [
            plan(slotEntryID: 7, name: "Bench press", setCount: 3),
            plan(slotEntryID: 8, name: "Barbell row", setCount: 2),
        ]
    )

    private static func plan(
        slotEntryID: Int,
        name: String,
        setCount: Int
    ) -> WorkoutExercisePlan {
        WorkoutExercisePlan(
            slotEntryID: slotEntryID,
            exerciseID: slotEntryID,
            name: name,
            setCount: setCount,
            targetRepetitions: "8",
            targetWeight: "60",
            repetitionsUnitID: 1,
            weightUnitID: 1,
            repetitionsIncrement: 1,
            weightIncrement: 2.5,
            restSeconds: 90,
            prescription: "\(setCount) sets · 8 reps · 60 kg",
            comment: nil
        )
    }

    private static func log(id: String, slotEntryID: Int) -> WorkoutSetLog {
        WorkoutSetLog(
            id: id,
            date: FixtureWorkoutStore.now,
            routineID: 42,
            iteration: 2,
            slotEntryID: slotEntryID,
            exerciseID: slotEntryID,
            repetitions: "8",
            weight: "60",
            repetitionsUnitID: 1,
            weightUnitID: 1
        )
    }
}
