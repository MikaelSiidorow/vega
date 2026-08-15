import Foundation
import PowerSync

nonisolated struct PowerSyncWorkoutRepository: WorkoutDataStore {
    private static let structureCacheKey = "workout-structure"
    private static let dashboardObservationSQL = """
        SELECT id FROM manager_routine
        UNION ALL SELECT id FROM manager_workoutsession
        UNION ALL SELECT id FROM manager_workoutlog
        UNION ALL SELECT id FROM exercises_translation
        UNION ALL SELECT id FROM core_language
        UNION ALL SELECT id FROM core_weightunit
        UNION ALL SELECT id FROM core_repetitionunit
        UNION ALL SELECT id FROM vega_workout_day_cache
        UNION ALL SELECT id FROM vega_workout_set_plan_cache
        """

    private let powerSync: any PowerSyncDatabaseProviding
    private let fallback: any WorkoutDataStore
    private let structure: any WorkoutStructureFetching
    private let makeID: @Sendable () -> String
    private let now: @Sendable () -> Date

    init(
        powerSync: any PowerSyncDatabaseProviding,
        fallback: any WorkoutDataStore,
        structure: any WorkoutStructureFetching,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.powerSync = powerSync
        self.fallback = fallback
        self.structure = structure
        self.makeID = makeID
        self.now = now
    }

    func dashboard(for date: Date, calendar: Calendar) async throws -> WorkoutDashboard {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.dashboard(for: date, calendar: calendar)
        }

        let records = try await Self.routines(in: database)
        if records.isEmpty, !(await powerSync.status()).hasSynced {
            return try await fallback.dashboard(for: date, calendar: calendar)
        }
        let daysByRoutine = try await dayPlans(
            routineIDs: records.map(\.id),
            database: database
        )
        return try await Self.dashboard(
            for: date,
            calendar: calendar,
            records: records,
            daysByRoutine: daysByRoutine,
            database: database
        )
    }

    func dashboardStream(for date: Date, calendar: Calendar) async throws
        -> AsyncThrowingStream<WorkoutDashboard, Error>
    {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.dashboardStream(for: date, calendar: calendar)
        }
        let updates = try database.watch(
            sql: Self.dashboardObservationSQL,
            parameters: [],
            mapper: { try $0.getString(index: 0) }
        )
        return AsyncThrowingStream { continuation in
            let observation = Task {
                var observedRoutineIDs: [Int]?
                do {
                    for try await _ in updates {
                        let records = try await Self.routines(in: database)
                        if records.isEmpty, !(await powerSync.status()).hasSynced {
                            continuation.yield(
                                try await fallback.dashboard(for: date, calendar: calendar)
                            )
                            continue
                        }
                        let routineIDs = records.map(\.id)
                        let daysByRoutine: [Int: [WorkoutDayRecord]]
                        if routineIDs.isEmpty {
                            daysByRoutine = [:]
                        } else {
                            let hasCachedDayPlans = try await Self.hasCachedDayPlans(in: database)
                            if observedRoutineIDs != routineIDs || !hasCachedDayPlans {
                                daysByRoutine = try await dayPlans(
                                    routineIDs: routineIDs,
                                    database: database
                                )
                            } else {
                                daysByRoutine = try await Self.cachedDayPlans(in: database)
                            }
                        }
                        observedRoutineIDs = routineIDs
                        continuation.yield(
                            try await Self.dashboard(
                                for: date,
                                calendar: calendar,
                                records: records,
                                daysByRoutine: daysByRoutine,
                                database: database
                            )
                        )
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in observation.cancel() }
        }
    }

    private static func dashboard(
        for date: Date,
        calendar: Calendar,
        records: [WorkoutRoutineRecord],
        daysByRoutine: [Int: [WorkoutDayRecord]],
        database: any PowerSyncDatabaseProtocol
    ) async throws -> WorkoutDashboard {
        let exerciseIDs = Set(
            daysByRoutine.values.flatMap { $0 }.flatMap(\.sets).map(\.exerciseID)
        )
        let exercises = try await Self.exerciseNames(ids: exerciseIDs, in: database)
        let routines = try records.map { routine in
            WorkoutRoutine(
                id: routine.id,
                name: routine.name?.powerSyncNilIfBlank ?? "Routine \(routine.id)",
                description: routine.description?.powerSyncNilIfBlank,
                start: routine.start,
                end: routine.end,
                days: try (daysByRoutine[routine.id] ?? []).map {
                    try WorkoutAPI.day(
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
        async let weightUnitsValue = Self.weightUnits(in: database)
        async let repetitionUnitsValue = Self.repetitionUnits(in: database)
        let logs: [WorkoutSetLog] =
            if let today {
                try await Self.logs(
                    routineID: today.routineID,
                    date: date,
                    calendar: calendar,
                    in: database
                )
            } else {
                []
            }
        let (weightUnits, repetitionUnits) = try await (
            weightUnitsValue,
            repetitionUnitsValue
        )
        return WorkoutDashboard(
            routines: routines,
            today: today,
            logs: logs,
            weightUnits: weightUnits,
            repetitionUnits: repetitionUnits
        )
    }

    func createSet(
        for plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.createSet(for: plan, day: day, input: input)
            return
        }
        let logID = makeID()
        let newSessionID = makeID()
        let logDate = now()
        let sessionDate = WorkoutAPI.dateKey(day.date, calendar: Calendar.current)
        let repetitions = try Self.optionalDouble(input.repetitions, field: "repetitions")
        let weight = try Self.optionalDouble(input.weight, field: "weight")
        let repetitionsTarget = try Self.optionalDouble(
            plan.targetRepetitions,
            field: "repetitions_target"
        )
        let weightTarget = try Self.optionalDouble(plan.targetWeight, field: "weight_target")
        let repetitionsUnitID = input.repetitionsUnitID ?? plan.repetitionsUnitID
        let weightUnitID = input.weightUnitID ?? plan.weightUnitID

        try await database.writeTransaction { transaction in
            let existingSessionID = try transaction.getOptional(
                sql: """
                    SELECT id FROM manager_workoutsession
                    WHERE routine_id = ? AND date = ?
                    LIMIT 1
                    """,
                parameters: [day.routineID, sessionDate],
                mapper: { try $0.getString(name: "id") }
            )
            let sessionID = existingSessionID ?? newSessionID
            if existingSessionID == nil {
                let sessionParameters: [Sendable?] = [
                    sessionID,
                    day.routineID,
                    day.dayID,
                    sessionDate,
                    nil,
                    "2",
                    nil,
                    nil,
                ]
                try transaction.execute(
                    sql: """
                        INSERT INTO manager_workoutsession (
                            id, routine_id, day_id, date, notes, impression,
                            time_start, time_end
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    parameters: sessionParameters
                )
            }
            let logParameters: [Sendable?] = [
                logID,
                plan.exerciseID,
                day.routineID,
                sessionID,
                day.iteration,
                plan.slotEntryID,
                nil,
                nil,
                repetitions,
                repetitionsTarget,
                repetitionsUnitID,
                weight,
                weightTarget,
                weightUnitID,
                PowerSyncValueCodec.encodeDateTime(logDate),
            ]
            try transaction.execute(
                sql: """
                    INSERT INTO manager_workoutlog (
                        id, exercise_id, routine_id, session_id, iteration,
                        slot_entry_id, rir, rir_target, repetitions,
                        repetitions_target, repetitions_unit_id, weight,
                        weight_target, weight_unit_id, date
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                parameters: logParameters
            )
        }
    }

    func updateSet(id: String, input: WorkoutSetInput) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.updateSet(id: id, input: input)
            return
        }
        let parameters: [Sendable?] = [
            try Self.optionalDouble(input.repetitions, field: "repetitions"),
            try Self.optionalDouble(input.weight, field: "weight"),
            input.repetitionsUnitID,
            input.weightUnitID,
            id,
        ]
        try await database.execute(
            sql: """
                UPDATE manager_workoutlog
                SET repetitions = ?, weight = ?,
                    repetitions_unit_id = COALESCE(?, repetitions_unit_id),
                    weight_unit_id = COALESCE(?, weight_unit_id)
                WHERE id = ?
                """,
            parameters: parameters
        )
    }

    func deleteSet(id: String) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.deleteSet(id: id)
            return
        }
        try await database.execute(
            sql: "DELETE FROM manager_workoutlog WHERE id = ?",
            parameters: [id]
        )
    }

    private func dayPlans(
        routineIDs: [Int],
        database: any PowerSyncDatabaseProtocol
    ) async throws -> [Int: [WorkoutDayRecord]] {
        do {
            let values = try await structure.dayPlans(routineIDs: routineIDs)
            try await Self.replaceCachedDayPlans(values, in: database)
            return values
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard try await Self.hasCachedDayPlans(in: database) else { throw error }
            return try await Self.cachedDayPlans(in: database)
        }
    }

    private static func routines(in database: any PowerSyncDatabaseProtocol) async throws
        -> [WorkoutRoutineRecord]
    {
        try await database.getAll(
            sql: "SELECT id, name, description, start, end FROM manager_routine",
            parameters: []
        ) { cursor in
            WorkoutRoutineRecord(
                id: try PowerSyncValueCodec.integerID(cursor.getString(name: "id")),
                name: try cursor.getStringOptional(name: "name"),
                description: try cursor.getStringOptional(name: "description"),
                start: try cursor.getString(name: "start"),
                end: try cursor.getString(name: "end")
            )
        }
    }

    private static func logs(
        routineID: Int,
        date: Date,
        calendar: Calendar,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [WorkoutSetLog] {
        let values = try await database.getAll(
            sql: """
                SELECT id, date, routine_id, iteration, slot_entry_id, exercise_id,
                       repetitions, weight, repetitions_unit_id, weight_unit_id
                FROM manager_workoutlog
                WHERE routine_id = ?
                ORDER BY date
                """,
            parameters: [routineID]
        ) { cursor in
            let id = try cursor.getString(name: "id")
            let encodedDate = try cursor.getString(name: "date")
            guard let decodedDate = PowerSyncValueCodec.decodeDateTime(encodedDate) else {
                throw PowerSyncRepositoryError.invalidDate(
                    table: WgerPowerSyncTable.workoutLog,
                    recordID: id,
                    value: encodedDate
                )
            }
            return WorkoutSetLog(
                id: id,
                date: decodedDate,
                routineID: try cursor.getIntOptional(name: "routine_id"),
                iteration: try cursor.getIntOptional(name: "iteration"),
                slotEntryID: try cursor.getIntOptional(name: "slot_entry_id"),
                exerciseID: try cursor.getInt(name: "exercise_id"),
                repetitions: try cursor.getDoubleOptional(name: "repetitions").map(
                    PowerSyncValueCodec.decimalString
                ),
                weight: try cursor.getDoubleOptional(name: "weight").map(
                    PowerSyncValueCodec.decimalString
                ),
                repetitionsUnitID: try cursor.getIntOptional(name: "repetitions_unit_id"),
                weightUnitID: try cursor.getIntOptional(name: "weight_unit_id")
            )
        }
        return values.filter { value in
            guard let logDate = value.date else { return false }
            return calendar.isDate(logDate, inSameDayAs: date)
        }
    }

    private static func weightUnits(in database: any PowerSyncDatabaseProtocol) async throws
        -> [WorkoutWeightUnit]
    {
        try await database.getAll(
            sql: "SELECT id, name FROM core_weightunit ORDER BY id",
            parameters: []
        ) { cursor in
            WorkoutWeightUnit(
                id: try PowerSyncValueCodec.integerID(cursor.getString(name: "id")),
                name: try cursor.getString(name: "name")
            )
        }
    }

    private static func repetitionUnits(in database: any PowerSyncDatabaseProtocol) async throws
        -> [WorkoutRepetitionUnit]
    {
        try await database.getAll(
            sql: "SELECT id, name FROM core_repetitionunit ORDER BY id",
            parameters: []
        ) { cursor in
            WorkoutRepetitionUnit(
                id: try PowerSyncValueCodec.integerID(cursor.getString(name: "id")),
                name: try cursor.getString(name: "name")
            )
        }
    }

    private static func exerciseNames(
        ids: Set<Int>,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [Int: WorkoutExerciseRecord] {
        guard !ids.isEmpty else { return [:] }
        let sortedIDs = ids.sorted()
        let placeholders = Array(repeating: "?", count: sortedIDs.count).joined(separator: ",")
        let values = try await database.getAll(
            sql: """
                SELECT t.exercise_id, t.name
                FROM exercises_translation t
                LEFT JOIN core_language l ON l.id = CAST(t.language_id AS TEXT)
                WHERE t.exercise_id IN (\(placeholders))
                ORDER BY CASE WHEN l.short_name = 'en' THEN 0 ELSE 1 END, t.language_id
                """,
            parameters: sortedIDs
        ) { cursor in
            WorkoutExerciseRecord(
                id: try cursor.getInt(name: "exercise_id"),
                name: try cursor.getString(name: "name")
            )
        }
        var result: [Int: WorkoutExerciseRecord] = [:]
        for value in values where result[value.id] == nil {
            result[value.id] = value
        }
        return result
    }

    private static func replaceCachedDayPlans(
        _ values: [Int: [WorkoutDayRecord]],
        in database: any PowerSyncDatabaseProtocol
    ) async throws {
        try await database.writeTransaction { transaction in
            try transaction.execute(sql: "DELETE FROM vega_workout_set_plan_cache", parameters: [])
            try transaction.execute(sql: "DELETE FROM vega_workout_day_cache", parameters: [])
            for routineID in values.keys.sorted() {
                for day in values[routineID] ?? [] {
                    let dayCacheID = cacheID(routineID: routineID, day: day)
                    let dayParameters: [Sendable?] = [
                        dayCacheID,
                        routineID,
                        day.dayID,
                        day.name,
                        day.date,
                        day.iteration,
                        day.isRest,
                    ]
                    try transaction.execute(
                        sql: """
                            INSERT INTO vega_workout_day_cache (
                                id, routine_id, day_id, name, date, iteration, is_rest
                            ) VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                        parameters: dayParameters
                    )
                    for (index, set) in day.sets.enumerated() {
                        let setParameters: [Sendable?] = [
                            "\(dayCacheID)|\(set.slotEntryID)|\(index)",
                            dayCacheID,
                            set.slotEntryID,
                            set.exerciseID,
                            set.setCount,
                            set.targetRepetitions,
                            set.targetWeight,
                            set.repetitionsUnitID,
                            set.weightUnitID,
                            set.repetitionsIncrement,
                            set.weightIncrement,
                            set.rest,
                            set.prescription,
                            set.comment,
                        ]
                        try transaction.execute(
                            sql: """
                                INSERT INTO vega_workout_set_plan_cache (
                                    id, day_cache_id, slot_entry_id, exercise_id,
                                    set_count, target_repetitions, target_weight,
                                    repetitions_unit_id, weight_unit_id,
                                    repetitions_increment, weight_increment, rest,
                                    prescription, comment
                                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                """,
                            parameters: setParameters
                        )
                    }
                }
            }
            try transaction.execute(
                sql: """
                    INSERT OR REPLACE INTO vega_local_cache_metadata (id, updated_at)
                    VALUES (?, ?)
                    """,
                parameters: [
                    structureCacheKey,
                    PowerSyncValueCodec.encodeDateTime(Date()),
                ]
            )
        }
    }

    private static func hasCachedDayPlans(in database: any PowerSyncDatabaseProtocol) async throws
        -> Bool
    {
        try await database.getOptional(
            sql: "SELECT id FROM vega_local_cache_metadata WHERE id = ?",
            parameters: [structureCacheKey],
            mapper: { try $0.getString(name: "id") }
        ) != nil
    }

    private static func cachedDayPlans(in database: any PowerSyncDatabaseProtocol) async throws
        -> [Int: [WorkoutDayRecord]]
    {
        let days = try await database.getAll(
            sql: """
                SELECT id, routine_id, day_id, name, date, iteration, is_rest
                FROM vega_workout_day_cache
                ORDER BY date, routine_id, day_id
                """,
            parameters: []
        ) { cursor in
            CachedWorkoutDay(
                cacheID: try cursor.getString(name: "id"),
                routineID: try cursor.getInt(name: "routine_id"),
                dayID: try cursor.getInt(name: "day_id"),
                name: try cursor.getStringOptional(name: "name"),
                date: try cursor.getString(name: "date"),
                iteration: try cursor.getInt(name: "iteration"),
                isRest: try cursor.getBoolean(name: "is_rest")
            )
        }
        var result: [Int: [WorkoutDayRecord]] = [:]
        for day in days {
            result[day.routineID, default: []].append(
                WorkoutDayRecord(
                    dayID: day.dayID,
                    name: day.name,
                    date: day.date,
                    iteration: day.iteration,
                    isRest: day.isRest,
                    sets: try await cachedSets(dayCacheID: day.cacheID, in: database)
                )
            )
        }
        return result
    }

    private static func cachedSets(
        dayCacheID: String,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [WorkoutSetRecord] {
        try await database.getAll(
            sql: """
                SELECT slot_entry_id, exercise_id, set_count, target_repetitions,
                       target_weight, repetitions_unit_id, weight_unit_id,
                       repetitions_increment, weight_increment, rest,
                       prescription, comment
                FROM vega_workout_set_plan_cache
                WHERE day_cache_id = ?
                ORDER BY id
                """,
            parameters: [dayCacheID]
        ) { cursor in
            WorkoutSetRecord(
                slotEntryID: try cursor.getInt(name: "slot_entry_id"),
                exerciseID: try cursor.getInt(name: "exercise_id"),
                setCount: try cursor.getInt(name: "set_count"),
                targetRepetitions: try cursor.getStringOptional(name: "target_repetitions"),
                targetWeight: try cursor.getStringOptional(name: "target_weight"),
                repetitionsUnitID: try cursor.getIntOptional(name: "repetitions_unit_id"),
                weightUnitID: try cursor.getIntOptional(name: "weight_unit_id"),
                repetitionsIncrement: try cursor.getStringOptional(name: "repetitions_increment"),
                weightIncrement: try cursor.getStringOptional(name: "weight_increment"),
                rest: try cursor.getStringOptional(name: "rest"),
                prescription: try cursor.getString(name: "prescription"),
                comment: try cursor.getString(name: "comment")
            )
        }
    }

    private static func cacheID(routineID: Int, day: WorkoutDayRecord) -> String {
        "\(routineID)|\(day.dayID)|\(day.iteration)|\(day.date)"
    }

    private static func optionalDouble(_ value: String?, field: String) throws -> Double? {
        guard let value else { return nil }
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else { throw WorkoutDomainError.invalidDecimal(field: field, value: value) }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }
}

private nonisolated struct CachedWorkoutDay: Sendable {
    let cacheID: String
    let routineID: Int
    let dayID: Int
    let name: String?
    let date: String
    let iteration: Int
    let isRest: Bool
}

nonisolated extension String {
    fileprivate var powerSyncNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
