import Foundation
import PowerSync
import Testing

@testable import Vega

nonisolated struct PowerSyncWorkoutRepositoryTests {
    @Test
    func dashboardUsesLocalPersonalDataAndCachesUnsupportedSchedule() async throws {
        let database = try await seededDatabase()
        let date = Self.calendar.startOfDay(for: Date())
        let onlineStructure = WorkoutStructureStub(days: [42: [Self.day(date: date)]])
        let repository = PowerSyncWorkoutRepository(
            powerSync: WorkoutPowerSyncProvider(database: database),
            fallback: FailingWorkoutStore(),
            structure: onlineStructure
        )

        let dashboard = try await repository.dashboard(for: date, calendar: Self.calendar)

        #expect(dashboard.routines.first?.name == "Local strength")
        #expect(dashboard.today?.name == "Upper body")
        #expect(dashboard.today?.exercises.first?.name == "Local bench press")
        #expect(dashboard.logs.map(\.id) == ["existing-log"])
        #expect(dashboard.weightUnits == [WorkoutWeightUnit(id: 1, name: "kg")])
        #expect(
            dashboard.repetitionUnits
                == [WorkoutRepetitionUnit(id: 1, name: "Repetitions")]
        )

        let offlineRepository = PowerSyncWorkoutRepository(
            powerSync: WorkoutPowerSyncProvider(database: database),
            fallback: FailingWorkoutStore(),
            structure: WorkoutStructureStub(error: WorkoutStructureStubError.offline)
        )
        let cached = try await offlineRepository.dashboard(for: date, calendar: Self.calendar)
        #expect(cached.today?.exercises.first?.slotEntryID == 7)
        #expect(cached.today?.exercises.first?.prescription == "3 sets · 8 reps · 60 kg")
        try await database.close()
    }

    @Test
    func offlineSetCreatesSessionAndQueuesAtomicUploads() async throws {
        let database = try await seededDatabase()
        try await database.execute("DELETE FROM ps_crud")
        let date = Self.calendar.startOfDay(for: Date())
        let day = Self.day(date: date)
        let ids = WorkoutIDSequence([
            "offline-log-1", "offline-session", "offline-log-2", "unused-session",
        ])
        let repository = PowerSyncWorkoutRepository(
            powerSync: WorkoutPowerSyncProvider(database: database),
            fallback: FailingWorkoutStore(),
            structure: WorkoutStructureStub(days: [42: [day]]),
            makeID: { ids.next() },
            now: { date.addingTimeInterval(12 * 60 * 60) }
        )
        let initial = try await repository.dashboard(for: date, calendar: Self.calendar)
        let workoutDay = try #require(initial.today)
        let plan = try #require(workoutDay.exercises.first)

        try await repository.createSet(
            for: plan,
            day: try #require(
                try await repository.dashboard(for: date, calendar: Self.calendar).today
            ),
            input: WorkoutSetInput(
                repetitions: "9",
                weight: "62.5",
                repetitionsUnitID: 1,
                weightUnitID: 1
            )
        )

        var transaction = try #require(try await database.getNextCrudTransaction())
        #expect(
            transaction.crud.map(\.table) == [
                WgerPowerSyncTable.workoutSession,
                WgerPowerSyncTable.workoutLog,
            ])
        #expect(transaction.crud.allSatisfy { $0.op == .put })
        try await transaction.complete()
        let created = try #require(
            try await repository.dashboard(for: date, calendar: Self.calendar).logs.first {
                $0.id == "offline-log-1"
            }
        )
        #expect(created.repetitions == "9")
        #expect(created.weight == "62.5")

        try await repository.createSet(
            for: plan,
            day: try #require(
                try await repository.dashboard(for: date, calendar: Self.calendar).today
            ),
            input: WorkoutSetInput(repetitions: "8", weight: "60")
        )
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.map(\.table) == [WgerPowerSyncTable.workoutLog])
        try await transaction.complete()
        let sessionCount = try await database.getOptional(
            sql: "SELECT count(*) AS count FROM manager_workoutsession",
            parameters: [],
            mapper: { try $0.getInt(name: "count") }
        )
        #expect(sessionCount == 1)

        try await repository.updateSet(
            id: created.id,
            input: WorkoutSetInput(repetitions: "10", weight: "65")
        )
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.first?.op == .patch)
        try await transaction.complete()

        try await repository.deleteSet(id: created.id)
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.first?.op == .delete)
        try await database.close()
    }

    @Test
    func dashboardStreamPublishesLocalSetLogs() async throws {
        let database = try await seededDatabase()
        let date = Self.calendar.startOfDay(for: Date())
        let day = Self.day(date: date)
        let repository = PowerSyncWorkoutRepository(
            powerSync: WorkoutPowerSyncProvider(database: database),
            fallback: FailingWorkoutStore(),
            structure: WorkoutStructureStub(days: [42: [day]]),
            makeID: { "streamed-workout" },
            now: { date.addingTimeInterval(12 * 60 * 60) }
        )
        let initial = try await repository.dashboard(for: date, calendar: Self.calendar)
        let workoutDay = try #require(initial.today)
        let plan = try #require(workoutDay.exercises.first)
        let stream = try await repository.dashboardStream(for: date, calendar: Self.calendar)
        let observation = Task { () throws -> WorkoutDashboard in
            for try await dashboard in stream
            where dashboard.logs.contains(where: {
                $0.id == "streamed-workout"
            }) {
                return dashboard
            }
            throw CancellationError()
        }

        try await repository.createSet(
            for: plan,
            day: workoutDay,
            input: WorkoutSetInput(repetitions: "8", weight: "60")
        )

        #expect(try await observation.value.logs.map(\.id).contains("streamed-workout"))
    }

    @Test
    func emptyDatabaseStreamsRESTUntilFirstSyncCompletes() async throws {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        let repository = PowerSyncWorkoutRepository(
            powerSync: WorkoutPowerSyncProvider(database: database, hasSynced: false),
            fallback: FixtureWorkoutStore(),
            structure: WorkoutStructureStub(error: WorkoutStructureStubError.offline)
        )
        let stream = try await repository.dashboardStream(
            for: Date(),
            calendar: Self.calendar
        )
        var iterator = stream.makeAsyncIterator()

        let initial = try #require(try await iterator.next())

        #expect(initial.routines.first?.id == 42)
    }

    @Test
    func fallsBackToRESTWhenPowerSyncIsUnavailable() async throws {
        let fallback = FixtureWorkoutStore()
        let repository = PowerSyncWorkoutRepository(
            powerSync: WorkoutUnavailablePowerSyncProvider(),
            fallback: fallback,
            structure: WorkoutStructureStub(error: WorkoutStructureStubError.offline)
        )
        let date = FixtureWorkoutStore.now
        let initial = try await repository.dashboard(for: date, calendar: Self.calendar)
        let day = try #require(initial.today)
        let plan = try #require(day.exercises.last)

        try await repository.createSet(
            for: plan,
            day: day,
            input: WorkoutSetInput(repetitions: "12", weight: "47.5")
        )
        var logs = try await repository.dashboard(for: date, calendar: Self.calendar).logs
        let created = try #require(logs.first { $0.slotEntryID == plan.slotEntryID })
        #expect(created.repetitions == "12")

        try await repository.updateSet(
            id: created.id,
            input: WorkoutSetInput(repetitions: "10", weight: "50")
        )
        logs = try await repository.dashboard(for: date, calendar: Self.calendar).logs
        #expect(logs.first { $0.id == created.id }?.weight == "50")

        try await repository.deleteSet(id: created.id)
        logs = try await repository.dashboard(for: date, calendar: Self.calendar).logs
        #expect(!logs.contains { $0.id == created.id })
    }

    private func seededDatabase() async throws -> any PowerSyncDatabaseProtocol {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        let date = Self.calendar.startOfDay(for: Date()).addingTimeInterval(12 * 60 * 60)
        try await database.execute(
            sql: """
                INSERT INTO manager_routine (
                    id, name, description, created, start, end,
                    is_template, is_public, fit_in_week
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                "42", "Local strength", "Synced routine", "2026-08-01T00:00:00Z",
                "2026-08-01", "2030-12-31", 0, 0, 1,
            ]
        )
        try await database.execute(
            sql: "INSERT INTO core_language (id, short_name, full_name) VALUES (?, ?, ?)",
            parameters: ["1", "en", "English"]
        )
        try await database.execute(
            sql: """
                INSERT INTO exercises_translation (
                    id, exercise_id, language_id, name, description
                ) VALUES (?, ?, ?, ?, ?)
                """,
            parameters: ["translation-1", 123, 1, "Local bench press", ""]
        )
        try await database.execute(
            sql: "INSERT INTO core_weightunit (id, name) VALUES (?, ?)",
            parameters: ["1", "kg"]
        )
        try await database.execute(
            sql: "INSERT INTO core_repetitionunit (id, name) VALUES (?, ?)",
            parameters: ["1", "Repetitions"]
        )
        try await database.execute(
            sql: """
                INSERT INTO manager_workoutlog (
                    id, exercise_id, routine_id, iteration, slot_entry_id,
                    repetitions, repetitions_unit_id, weight, weight_unit_id, date
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                "existing-log", 123, 42, 2, 7, 8.0, 1, 60.0, 1,
                PowerSyncValueCodec.encodeDateTime(date),
            ]
        )
        return database
    }

    private static func day(date: Date) -> WorkoutDayRecord {
        WorkoutDayRecord(
            dayID: 3,
            name: "Upper body",
            date: WorkoutAPI.dateKey(date, calendar: calendar),
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
                    repetitionsIncrement: "1",
                    weightIncrement: "2.5",
                    rest: "120",
                    prescription: "3 sets · 8 reps · 60 kg",
                    comment: "Controlled reps"
                )
            ]
        )
    }

    private static var calendar: Calendar {
        Calendar.current
    }
}

private nonisolated enum WorkoutStructureStubError: Error {
    case offline
}

private final class WorkoutIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        lock.withLock { values.removeFirst() }
    }
}

private actor WorkoutStructureStub: WorkoutStructureFetching {
    private let days: [Int: [WorkoutDayRecord]]
    private let error: Error?

    init(days: [Int: [WorkoutDayRecord]]) {
        self.days = days
        error = nil
    }

    init(error: Error) {
        days = [:]
        self.error = error
    }

    func dayPlans(routineIDs: [Int]) throws -> [Int: [WorkoutDayRecord]] {
        if let error { throw error }
        return days.filter { routineIDs.contains($0.key) }
    }
}

private nonisolated struct WorkoutPowerSyncProvider: PowerSyncDatabaseProviding {
    let storedDatabase: any PowerSyncDatabaseProtocol
    let hasSynced: Bool

    init(database: any PowerSyncDatabaseProtocol, hasSynced: Bool = true) {
        storedDatabase = database
        self.hasSynced = hasSynced
    }

    func database() -> any PowerSyncDatabaseProtocol { storedDatabase }

    func status() -> VegaSyncStatus {
        VegaSyncStatus(
            connected: false,
            connecting: false,
            downloading: false,
            uploading: false,
            hasSynced: hasSynced,
            lastSyncedAt: nil,
            pendingUploads: 0,
            errorMessage: nil,
            rejection: nil
        )
    }

    func reconnect() {}
    func clearCurrentAccount() {}
}

private nonisolated struct WorkoutUnavailablePowerSyncProvider: PowerSyncDatabaseProviding {
    func database() throws -> any PowerSyncDatabaseProtocol {
        throw PowerSyncControllerError.noSession
    }

    func status() -> VegaSyncStatus { .unavailable }
    func reconnect() throws { throw PowerSyncControllerError.noSession }
    func clearCurrentAccount() {}
}

private actor FailingWorkoutStore: WorkoutDataStore {
    func dashboard(for date: Date, calendar: Calendar) throws -> WorkoutDashboard {
        throw WorkoutStructureStubError.offline
    }

    func createSet(
        for plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) throws {
        throw WorkoutStructureStubError.offline
    }

    func updateSet(id: String, input: WorkoutSetInput) throws {
        throw WorkoutStructureStubError.offline
    }

    func deleteSet(id: String) throws {
        throw WorkoutStructureStubError.offline
    }
}
