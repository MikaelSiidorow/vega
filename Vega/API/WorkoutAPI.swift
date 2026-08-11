import Foundation
import WgerAPI

nonisolated protocol WorkoutDashboardFetching: Sendable {
    func dashboard(for date: Date, calendar: Calendar) async throws -> WorkoutDashboard
}

nonisolated protocol WorkoutSetCreating: Sendable {
    func createSet(for plan: WorkoutExercisePlan, day: PlannedWorkoutDay, input: WorkoutSetInput)
        async throws
}

nonisolated protocol WorkoutSetUpdating: Sendable {
    func updateSet(id: String, input: WorkoutSetInput) async throws
}

nonisolated protocol WorkoutSetDeleting: Sendable {
    func deleteSet(id: String) async throws
}

nonisolated protocol WorkoutTransport: Sendable {
    func routines(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutRoutineRecord>

    func dayPlans(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int
    ) async throws -> [WorkoutDayRecord]

    func exercises(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) async throws -> [WorkoutExerciseRecord]

    func weightUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutWeightUnitRecord>

    func repetitionUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutRepetitionUnitRecord>

    func logs(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int,
        date: String,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutSetLog>

    func createLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) async throws

    func updateLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String,
        input: WorkoutSetInput
    ) async throws

    func deleteLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) async throws
}

nonisolated struct WorkoutRoutineRecord: Equatable, Sendable {
    let id: Int
    let name: String?
    let description: String?
    let start: String
    let end: String
}

nonisolated struct WorkoutDayRecord: Equatable, Sendable {
    let dayID: Int
    let name: String?
    let date: String
    let iteration: Int
    let isRest: Bool
    let sets: [WorkoutSetRecord]
}

nonisolated struct WorkoutSetRecord: Equatable, Sendable {
    let slotEntryID: Int
    let exerciseID: Int
    let setCount: Int
    let targetRepetitions: String?
    let targetWeight: String?
    let repetitionsUnitID: Int?
    let weightUnitID: Int?
    let repetitionsIncrement: String?
    let weightIncrement: String?
    let rest: String?
    let prescription: String
    let comment: String
}

nonisolated struct WorkoutExerciseRecord: Equatable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct WorkoutWeightUnitRecord: Equatable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct WorkoutRepetitionUnitRecord: Equatable, Sendable {
    let id: Int
    let name: String
}

nonisolated struct WgerWorkoutTransport: WorkoutTransport {
    func routines(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutRoutineRecord> {
        let page = try await WgerAPIModule.routines(
            serverURL: instance.url,
            accessToken: session.accessToken,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.map {
                WorkoutRoutineRecord(
                    id: $0.id,
                    name: $0.name,
                    description: $0.description,
                    start: $0.start,
                    end: $0.end
                )
            },
            hasNextPage: page.next != nil
        )
    }

    func dayPlans(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int
    ) async throws -> [WorkoutDayRecord] {
        try await WgerAPIModule.workoutDayPlans(
            serverURL: instance.url,
            accessToken: session.accessToken,
            routineID: routineID
        ).map { day in
            WorkoutDayRecord(
                dayID: day.day.id,
                name: day.day.name,
                date: day.date,
                iteration: day.iteration,
                isRest: day.day.isRest ?? false,
                sets: day.slots.flatMap(\.sets).map {
                    WorkoutSetRecord(
                        slotEntryID: $0.slotEntryId,
                        exerciseID: $0.exercise,
                        setCount: $0.sets,
                        targetRepetitions: $0.repetitions,
                        targetWeight: $0.weight,
                        repetitionsUnitID: $0.repetitionsUnit,
                        weightUnitID: $0.weightUnit,
                        repetitionsIncrement: $0.repetitionsRounding,
                        weightIncrement: $0.weightRounding,
                        rest: $0.rest,
                        prescription: $0.textRepr,
                        comment: $0.comment
                    )
                }
            )
        }
    }

    func exercises(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) async throws -> [WorkoutExerciseRecord] {
        let page = try await WgerAPIModule.exerciseInfo(
            serverURL: instance.url,
            accessToken: session.accessToken,
            ids: ids
        )
        return page.results.map {
            WorkoutExerciseRecord(
                id: $0.id,
                name: $0.translations.first?.name ?? "Exercise \($0.id)"
            )
        }
    }

    func weightUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutWeightUnitRecord> {
        let page = try await WgerAPIModule.workoutWeightUnits(
            serverURL: instance.url,
            accessToken: session.accessToken,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.map { WorkoutWeightUnitRecord(id: $0.id, name: $0.name) },
            hasNextPage: page.next != nil
        )
    }

    func repetitionUnits(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutRepetitionUnitRecord> {
        let page = try await WgerAPIModule.workoutRepetitionUnits(
            serverURL: instance.url,
            accessToken: session.accessToken,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.map { WorkoutRepetitionUnitRecord(id: $0.id, name: $0.name) },
            hasNextPage: page.next != nil
        )
    }

    func logs(
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int,
        date: String,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WorkoutSetLog> {
        let page = try await WgerAPIModule.workoutLogs(
            serverURL: instance.url,
            accessToken: session.accessToken,
            routineID: routineID,
            date: date,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.compactMap(WorkoutSetLog.init),
            hasNextPage: page.next != nil
        )
    }

    func createLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) async throws {
        _ = try await WgerAPIModule.createWorkoutLog(
            serverURL: instance.url,
            accessToken: session.accessToken,
            log: .init(
                date: Date(),
                routine: day.routineID,
                iteration: day.iteration,
                slotEntry: plan.slotEntryID,
                exercise: plan.exerciseID,
                repetitionsUnit: input.repetitionsUnitID ?? plan.repetitionsUnitID,
                repetitions: input.repetitions,
                repetitionsTarget: plan.targetRepetitions,
                weightUnit: input.weightUnitID ?? plan.weightUnitID,
                weight: input.weight,
                weightTarget: plan.targetWeight
            )
        )
    }

    func updateLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String,
        input: WorkoutSetInput
    ) async throws {
        _ = try await WgerAPIModule.updateWorkoutLog(
            serverURL: instance.url,
            accessToken: session.accessToken,
            id: id,
            repetitions: input.repetitions,
            weight: input.weight,
            repetitionsUnit: input.repetitionsUnitID,
            weightUnit: input.weightUnitID
        )
    }

    func deleteLog(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) async throws {
        try await WgerAPIModule.deleteWorkoutLog(
            serverURL: instance.url,
            accessToken: session.accessToken,
            id: id
        )
    }
}

actor WorkoutAPI: WorkoutDashboardFetching, WorkoutSetCreating, WorkoutSetUpdating,
    WorkoutSetDeleting
{
    private static let pageSize = 100
    private let client: any AuthenticatedRequestExecuting
    private let transport: any WorkoutTransport

    init(
        client: any AuthenticatedRequestExecuting,
        transport: any WorkoutTransport = WgerWorkoutTransport()
    ) {
        self.client = client
        self.transport = transport
    }

    func dashboard(for date: Date, calendar: Calendar) async throws -> WorkoutDashboard {
        let dateKey = Self.dateKey(date, calendar: calendar)
        let transport = transport
        return try await client.perform { instance, session in
            let records = try await Self.allRoutines(
                transport: transport,
                instance: instance,
                session: session
            )
            async let weightUnitRecords = Self.allWeightUnits(
                transport: transport,
                instance: instance,
                session: session
            )
            async let repetitionUnitRecords = Self.allRepetitionUnits(
                transport: transport,
                instance: instance,
                session: session
            )
            var daysByRoutine: [Int: [WorkoutDayRecord]] = [:]
            for routine in records {
                daysByRoutine[routine.id] = try await transport.dayPlans(
                    instance: instance,
                    session: session,
                    routineID: routine.id
                )
            }
            let exerciseIDs = Set(
                daysByRoutine.values.flatMap { $0 }.flatMap(\.sets).map(\.exerciseID)
            )
            var exercises: [Int: WorkoutExerciseRecord] = [:]
            for batch in exerciseIDs.sorted().chunks(ofCount: Self.pageSize) {
                for exercise in try await transport.exercises(
                    instance: instance,
                    session: session,
                    ids: batch
                ) {
                    exercises[exercise.id] = exercise
                }
            }
            let routines = try records.map { routine in
                WorkoutRoutine(
                    id: routine.id,
                    name: routine.name?.nilIfBlank ?? "Routine \(routine.id)",
                    description: routine.description?.nilIfBlank,
                    start: routine.start,
                    end: routine.end,
                    days: try (daysByRoutine[routine.id] ?? []).map {
                        try Self.day(
                            $0,
                            routine: routine,
                            exercises: exercises,
                            calendar: calendar
                        )
                    }
                )
            }
            let today = routines.lazy.flatMap(\.days).first {
                calendar.isDate($0.date, inSameDayAs: date)
            }
            let logs: [WorkoutSetLog] =
                if let today {
                    try await Self.allLogs(
                        transport: transport,
                        instance: instance,
                        session: session,
                        routineID: today.routineID,
                        date: dateKey
                    )
                } else {
                    []
                }
            let (weightUnits, repetitionUnits) = try await (
                weightUnitRecords,
                repetitionUnitRecords
            )
            return WorkoutDashboard(
                routines: routines,
                today: today,
                logs: logs,
                weightUnits: weightUnits.map {
                    WorkoutWeightUnit(id: $0.id, name: $0.name)
                },
                repetitionUnits: repetitionUnits.map {
                    WorkoutRepetitionUnit(id: $0.id, name: $0.name)
                }
            )
        }
    }

    func createSet(
        for plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) async throws {
        let transport = transport
        try await client.perform { instance, session in
            try await transport.createLog(
                instance: instance,
                session: session,
                plan: plan,
                day: day,
                input: input
            )
        }
    }

    func updateSet(id: String, input: WorkoutSetInput) async throws {
        let transport = transport
        try await client.perform { instance, session in
            try await transport.updateLog(
                instance: instance,
                session: session,
                id: id,
                input: input
            )
        }
    }

    func deleteSet(id: String) async throws {
        let transport = transport
        try await client.perform { instance, session in
            try await transport.deleteLog(instance: instance, session: session, id: id)
        }
    }

    private static func allRoutines(
        transport: any WorkoutTransport,
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> [WorkoutRoutineRecord] {
        var result: [WorkoutRoutineRecord] = []
        var offset = 0
        while true {
            let page = try await transport.routines(
                instance: instance,
                session: session,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func allLogs(
        transport: any WorkoutTransport,
        instance: InstanceURL,
        session: AuthenticationSession,
        routineID: Int,
        date: String
    ) async throws -> [WorkoutSetLog] {
        var result: [WorkoutSetLog] = []
        var offset = 0
        while true {
            let page = try await transport.logs(
                instance: instance,
                session: session,
                routineID: routineID,
                date: date,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func allWeightUnits(
        transport: any WorkoutTransport,
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> [WorkoutWeightUnitRecord] {
        var result: [WorkoutWeightUnitRecord] = []
        var offset = 0
        while true {
            let page = try await transport.weightUnits(
                instance: instance,
                session: session,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func allRepetitionUnits(
        transport: any WorkoutTransport,
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> [WorkoutRepetitionUnitRecord] {
        var result: [WorkoutRepetitionUnitRecord] = []
        var offset = 0
        while true {
            let page = try await transport.repetitionUnits(
                instance: instance,
                session: session,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func day(
        _ record: WorkoutDayRecord,
        routine: WorkoutRoutineRecord,
        exercises: [Int: WorkoutExerciseRecord],
        calendar: Calendar
    ) throws -> PlannedWorkoutDay {
        PlannedWorkoutDay(
            routineID: routine.id,
            routineName: routine.name?.nilIfBlank ?? "Routine \(routine.id)",
            dayID: record.dayID,
            name: record.name?.nilIfBlank ?? "Workout day",
            date: try workoutDate(record.date, calendar: calendar),
            iteration: record.iteration,
            isRest: record.isRest,
            exercises: try record.sets.map {
                WorkoutExercisePlan(
                    slotEntryID: $0.slotEntryID,
                    exerciseID: $0.exerciseID,
                    name: exercises[$0.exerciseID]?.name ?? "Exercise \($0.exerciseID)",
                    setCount: max(1, $0.setCount),
                    targetRepetitions: $0.targetRepetitions,
                    targetWeight: $0.targetWeight,
                    repetitionsUnitID: $0.repetitionsUnitID,
                    weightUnitID: $0.weightUnitID,
                    repetitionsIncrement: try decimal(
                        $0.repetitionsIncrement,
                        fallback: 1,
                        field: "repetitions_rounding"
                    ),
                    weightIncrement: try decimal(
                        $0.weightIncrement,
                        fallback: 1.25,
                        field: "weight_rounding"
                    ),
                    restSeconds: try seconds($0.rest),
                    prescription: $0.prescription,
                    comment: $0.comment.nilIfBlank
                )
            }
        )
    }

    private static func decimal(
        _ value: String?,
        fallback: Decimal,
        field: String
    ) throws -> Decimal {
        guard let value else { return fallback }
        guard let parsed = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw WorkoutDomainError.invalidDecimal(field: field, value: value)
        }
        return parsed
    }

    private static func seconds(_ value: String?) throws -> Int {
        let decimal = try decimal(value, fallback: 90, field: "rest")
        let number = NSDecimalNumber(decimal: decimal)
        guard number != .notANumber, number.intValue >= 0 else {
            throw WorkoutDomainError.invalidDecimal(field: "rest", value: value ?? "")
        }
        return number.intValue
    }

    private static func workoutDate(_ value: String, calendar: Calendar) throws -> Date {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2]),
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))
        else {
            throw WorkoutDomainError.invalidDate(value)
        }
        let parsed = calendar.dateComponents([.year, .month, .day], from: date)
        guard parsed.year == year, parsed.month == month, parsed.day == day else {
            throw WorkoutDomainError.invalidDate(value)
        }
        return date
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            values.year ?? 0,
            values.month ?? 0,
            values.day ?? 0
        )
    }
}

nonisolated enum WorkoutDomainError: Error, Equatable {
    case invalidDate(String)
    case invalidDecimal(field: String, value: String)
}

nonisolated extension WorkoutSetLog {
    fileprivate init?(_ value: Components.Schemas.WorkoutLog) {
        guard let id = value.id else { return nil }
        self.init(
            id: id,
            date: value.date,
            routineID: value.routine,
            iteration: value.iteration,
            slotEntryID: value.slotEntry,
            exerciseID: value.exercise,
            repetitions: value.repetitions,
            weight: value.weight,
            repetitionsUnitID: value.repetitionsUnit,
            weightUnitID: value.weightUnit
        )
    }
}

nonisolated extension String {
    fileprivate var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

nonisolated extension Array {
    fileprivate func chunks(ofCount size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
