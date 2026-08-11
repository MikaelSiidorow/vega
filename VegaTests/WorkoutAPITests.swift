import Foundation
import Testing

@testable import Vega

nonisolated struct WorkoutAPITests {
    @Test
    func loadsRoutinesResolvedDaysExercisesAndTodaysLogs() async throws {
        let transport = WorkoutTransportStub(
            routinePages: [
                0: WgerPage(
                    values: [
                        WorkoutRoutineRecord(
                            id: 42,
                            name: "Strength",
                            description: nil,
                            start: "2026-08-01",
                            end: "2026-10-01"
                        )
                    ],
                    hasNextPage: false
                )
            ],
            days: [42: [Self.day]],
            exercises: [WorkoutExerciseRecord(id: 123, name: "Bench press")],
            weightUnits: [WorkoutWeightUnitRecord(id: 1, name: "kg")],
            repetitionUnits: [WorkoutRepetitionUnitRecord(id: 1, name: "Repetitions")],
            logPages: [
                0: WgerPage(
                    values: [Self.log],
                    hasNextPage: false
                )
            ]
        )
        let api = WorkoutAPI(client: WorkoutExecutor(), transport: transport)
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-12T12:00:00Z"))

        let dashboard = try await api.dashboard(for: date, calendar: Self.utcCalendar)

        #expect(dashboard.routines.map(\.name) == ["Strength"])
        #expect(dashboard.today?.name == "Upper body")
        #expect(dashboard.today?.date == Self.workoutDate)
        #expect(dashboard.today?.exercises.first?.name == "Bench press")
        #expect(dashboard.logs == [Self.log])
        #expect(dashboard.weightUnits.map(\.name) == ["kg"])
        #expect(dashboard.repetitionUnits.map(\.name) == ["Repetitions"])
        #expect(await transport.routineOffsets == [0])
        #expect(await transport.requestedRoutineIDs == [42])
        #expect(await transport.exerciseRequests == [[123]])
        #expect(await transport.requestedLogDates == ["2026-08-12"])
    }

    @Test
    func createsUpdatesAndDeletesSetLogs() async throws {
        let transport = WorkoutTransportStub(routinePages: [:])
        let api = WorkoutAPI(client: WorkoutExecutor(), transport: transport)
        let plan = WorkoutExercisePlan(
            slotEntryID: 7,
            exerciseID: 123,
            name: "Bench press",
            setCount: 3,
            targetRepetitions: "8",
            targetWeight: "60",
            repetitionsUnitID: 1,
            weightUnitID: 1,
            repetitionsIncrement: 1,
            weightIncrement: 2.5,
            restSeconds: 120,
            prescription: "3 × 8 × 60 kg",
            comment: nil
        )
        let day = PlannedWorkoutDay(
            routineID: 42,
            routineName: "Strength",
            dayID: 3,
            name: "Upper body",
            date: Self.workoutDate,
            iteration: 2,
            isRest: false,
            exercises: [plan]
        )

        try await api.createSet(
            for: plan,
            day: day,
            input: WorkoutSetInput(repetitions: "9", weight: "62.5")
        )
        try await api.updateSet(
            id: "log-id",
            input: WorkoutSetInput(repetitions: "10", weight: "65")
        )
        try await api.deleteSet(id: "log-id")

        #expect(
            await transport.createdInputs == [WorkoutSetInput(repetitions: "9", weight: "62.5")])
        #expect(await transport.updatedLogIDs == ["log-id"])
        #expect(await transport.deletedLogIDs == ["log-id"])
    }

    private static let day = WorkoutDayRecord(
        dayID: 3,
        name: "Upper body",
        date: "2026-08-12",
        iteration: 2,
        isRest: false,
        sets: [
            WorkoutSetRecord(
                slotEntryID: 7,
                exerciseID: 123,
                setCount: 3,
                targetRepetitions: "8",
                targetWeight: "60",
                repetitionsUnitID: 1,
                weightUnitID: 1,
                repetitionsIncrement: "1.00",
                weightIncrement: "2.50",
                rest: "120",
                prescription: "3 × 8 × 60 kg",
                comment: ""
            )
        ]
    )

    private static let log = WorkoutSetLog(
        id: "log-id",
        date: nil,
        routineID: 42,
        iteration: 2,
        slotEntryID: 7,
        exerciseID: 123,
        repetitions: "8",
        weight: "60",
        repetitionsUnitID: 1,
        weightUnitID: 1
    )

    private static let workoutDate = Date(timeIntervalSince1970: 1_786_492_800)

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

private nonisolated struct WorkoutExecutor: AuthenticatedRequestExecuting {
    func perform<Value: Sendable>(
        _ operation: @Sendable (InstanceURL, AuthenticationSession) async throws -> Value
    ) async throws -> Value {
        try await operation(
            InstanceURL("wger.example"),
            AuthenticationSession(accessToken: "access", refreshToken: "refresh")
        )
    }
}

private actor WorkoutTransportStub: WorkoutTransport {
    let routinePages: [Int: WgerPage<WorkoutRoutineRecord>]
    let days: [Int: [WorkoutDayRecord]]
    let exercisesValue: [WorkoutExerciseRecord]
    let weightUnitValues: [WorkoutWeightUnitRecord]
    let repetitionUnitValues: [WorkoutRepetitionUnitRecord]
    let logPages: [Int: WgerPage<WorkoutSetLog>]
    private(set) var routineOffsets: [Int] = []
    private(set) var requestedRoutineIDs: [Int] = []
    private(set) var exerciseRequests: [[Int]] = []
    private(set) var requestedLogDates: [String] = []
    private(set) var createdInputs: [WorkoutSetInput] = []
    private(set) var updatedLogIDs: [String] = []
    private(set) var deletedLogIDs: [String] = []

    init(
        routinePages: [Int: WgerPage<WorkoutRoutineRecord>],
        days: [Int: [WorkoutDayRecord]] = [:],
        exercises: [WorkoutExerciseRecord] = [],
        weightUnits: [WorkoutWeightUnitRecord] = [],
        repetitionUnits: [WorkoutRepetitionUnitRecord] = [],
        logPages: [Int: WgerPage<WorkoutSetLog>] = [:]
    ) {
        self.routinePages = routinePages
        self.days = days
        exercisesValue = exercises
        weightUnitValues = weightUnits
        repetitionUnitValues = repetitionUnits
        self.logPages = logPages
    }

    func routines(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) -> WgerPage<WorkoutRoutineRecord> {
        routineOffsets.append(offset)
        return routinePages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func dayPlans(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int
    ) -> [WorkoutDayRecord] {
        requestedRoutineIDs.append(routineID)
        return days[routineID] ?? []
    }

    func exercises(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) -> [WorkoutExerciseRecord] {
        exerciseRequests.append(ids)
        return exercisesValue.filter { ids.contains($0.id) }
    }

    func weightUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) -> WgerPage<WorkoutWeightUnitRecord> {
        WgerPage(values: offset == 0 ? weightUnitValues : [], hasNextPage: false)
    }

    func repetitionUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) -> WgerPage<WorkoutRepetitionUnitRecord> {
        WgerPage(values: offset == 0 ? repetitionUnitValues : [], hasNextPage: false)
    }

    func logs(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int,
        date: String,
        limit: Int,
        offset: Int
    ) -> WgerPage<WorkoutSetLog> {
        requestedLogDates.append(date)
        return logPages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func createLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) {
        createdInputs.append(input)
    }

    func updateLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String,
        input: WorkoutSetInput
    ) {
        updatedLogIDs.append(id)
    }

    func deleteLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) {
        deletedLogIDs.append(id)
    }
}
