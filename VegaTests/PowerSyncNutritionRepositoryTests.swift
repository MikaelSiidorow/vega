import Foundation
import PowerSync
import Testing

@testable import Vega

nonisolated struct PowerSyncNutritionRepositoryTests {
    @Test
    func hydratesDiaryAndComputesPlannedGoalsLocally() async throws {
        let database = try await seededDatabase()
        let repository = PowerSyncNutritionRepository(
            powerSync: NutritionPowerSyncProvider(database: database),
            fallback: FixtureDailyDiaryStore(mode: .basicLogging)
        )
        let date = try #require(Self.date("2026-08-16T12:00:00Z"))

        let payload = try await repository.diary(for: date, calendar: Self.utcCalendar)

        #expect(payload.plan?.id == "plan-1")
        #expect(payload.plan?.goalEnergy == 2_000)
        #expect(payload.plan?.goalProtein == 120)
        #expect(payload.plan?.goalCarbohydrates == 250)
        #expect(payload.plan?.goalFat == 70)
        #expect(payload.entries.map(\.id) == ["log-1"])
        #expect(payload.entries.first?.amount == "1")
        #expect(payload.ingredients[10]?.name == "Local tofu")
        #expect(payload.ingredients[10]?.weightUnits.first?.name == "portion")
        #expect(payload.meals.map(\.id) == ["meal-1"])
        #expect(
            payload.plannedNutrition
                == .available(
                    WgerNutritionalValues(
                        energy: 400,
                        protein: 40,
                        carbohydrates: 20,
                        fat: 10
                    )
                )
        )
        try await database.close()
    }

    @Test
    func offlineCreateEditDeleteAndRecentReadsUseSQLite() async throws {
        let database = try await seededDatabase()
        try await database.execute("DELETE FROM ps_crud")
        let repository = PowerSyncNutritionRepository(
            powerSync: NutritionPowerSyncProvider(database: database),
            fallback: FixtureDailyDiaryStore(mode: .basicLogging),
            makeID: { "new-log" }
        )
        let date = try #require(Self.date("2026-08-16T18:00:00Z"))

        try await repository.createDiaryEntry(
            planID: "plan-1",
            ingredientID: 10,
            amount: "2",
            weightUnitID: 100,
            date: date,
            mealID: nil
        )

        var transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.first?.op == .put)
        #expect(transaction.crud.first?.id == "new-log")
        #expect(transaction.crud.first?.table == WgerPowerSyncTable.logItem)
        try await transaction.complete()
        #expect(
            try await repository.diary(for: date, calendar: Self.utcCalendar).entries.map(\.id)
                == ["log-1", "new-log"]
        )

        try await repository.updateDiaryEntry(
            id: "new-log",
            amount: "1.5",
            weightUnitID: nil,
            date: date,
            mealID: "meal-1"
        )

        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.first?.op == .patch)
        try await transaction.complete()
        let updated = try #require(
            try await repository.diary(for: date, calendar: Self.utcCalendar).entries.first {
                $0.id == "new-log"
            }
        )
        #expect(updated.amount == "1.5")
        #expect(updated.weightUnitID == nil)
        #expect(updated.mealID == "meal-1")

        let recent = try await repository.recentDiary(
            planID: "plan-1",
            before: date.addingTimeInterval(60),
            calendar: Self.utcCalendar
        )
        #expect(Set(recent.entries.compactMap(\.id)) == ["log-1", "new-log"])
        #expect(recent.ingredients[10]?.name == "Local tofu")

        try await repository.deleteDiaryEntry(id: "new-log")
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.first?.op == .delete)
        #expect(
            try await repository.diary(for: date, calendar: Self.utcCalendar).entries.map(\.id)
                == ["log-1"]
        )
        try await database.close()
    }

    @Test
    func diaryStreamPublishesLocalWrites() async throws {
        let database = try await seededDatabase()
        let repository = PowerSyncNutritionRepository(
            powerSync: NutritionPowerSyncProvider(database: database),
            fallback: FixtureDailyDiaryStore(mode: .basicLogging),
            makeID: { "streamed-log" }
        )
        let date = try #require(Self.date("2026-08-16T18:00:00Z"))
        let stream = try await repository.diaryStream(for: date, calendar: Self.utcCalendar)
        let observation = Task { () throws -> DailyDiaryPayload in
            for try await payload in stream
            where payload.entries.contains(where: {
                $0.id == "streamed-log"
            }) {
                return payload
            }
            throw CancellationError()
        }

        try await repository.createDiaryEntry(
            planID: "plan-1",
            ingredientID: 10,
            amount: "2",
            weightUnitID: 100,
            date: date,
            mealID: nil
        )

        #expect(try await observation.value.entries.map(\.id).contains("streamed-log"))
    }

    @Test
    func fallsBackWhenPowerSyncIsUnavailable() async throws {
        let fallback = FixtureDailyDiaryStore(mode: .basicLogging)
        let repository = PowerSyncNutritionRepository(
            powerSync: NutritionUnavailablePowerSyncProvider(),
            fallback: fallback
        )
        let date = try #require(Self.date("2026-08-16T12:00:00Z"))

        let payload = try await repository.diary(for: date, calendar: Self.utcCalendar)

        #expect(payload.plan?.id == "fixture-plan")
        #expect(!payload.entries.isEmpty)
    }

    @Test
    func emptyDatabaseStreamsRESTUntilFirstSyncCompletes() async throws {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        let repository = PowerSyncNutritionRepository(
            powerSync: NutritionPowerSyncProvider(database: database, hasSynced: false),
            fallback: FixtureDailyDiaryStore(mode: .basicLogging)
        )
        let date = try #require(Self.date("2026-08-16T12:00:00Z"))
        let stream = try await repository.diaryStream(for: date, calendar: Self.utcCalendar)
        var iterator = stream.makeAsyncIterator()

        let initial = try #require(try await iterator.next())

        #expect(initial.plan?.id == "fixture-plan")
    }

    private func seededDatabase() async throws -> any PowerSyncDatabaseProtocol {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        try await database.execute(
            sql: """
                INSERT INTO nutrition_nutritionplan (
                    id, description, creation_date, start, end, only_logging,
                    goal_energy, goal_protein, goal_carbohydrates, goal_fat,
                    goal_fiber, has_goal_calories
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                "plan-1", "Offline plan", "2026-08-01", "2026-08-01", nil, 0,
                2_000, 120, 250, 70, nil, 1,
            ]
        )
        try await database.execute(
            sql: """
                INSERT INTO nutrition_ingredient (
                    id, name, brand, energy, protein, carbohydrates, fat
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: ["10", "Local tofu", "Vega foods", 200, 20.0, 10.0, 5.0]
        )
        try await database.execute(
            sql: """
                INSERT INTO nutrition_ingredientweightunit (
                    id, ingredient_id, name, gram
                ) VALUES (?, ?, ?, ?)
                """,
            parameters: ["100", 10, "portion", 100]
        )
        try await database.execute(
            sql: """
                INSERT INTO nutrition_meal (id, plan_id, "order", time, name)
                VALUES (?, ?, ?, ?, ?)
                """,
            parameters: ["meal-1", "plan-1", 1, "12:00:00", "Lunch"]
        )
        try await database.execute(
            sql: """
                INSERT INTO nutrition_mealitem (
                    id, meal_id, ingredient_id, weight_unit_id, "order", amount
                ) VALUES (?, ?, ?, ?, ?, ?)
                """,
            parameters: ["meal-item-1", "meal-1", 10, 100, 1, 2.0]
        )
        try await database.execute(
            sql: """
                INSERT INTO nutrition_logitem (
                    id, plan_id, meal_id, ingredient_id, weight_unit_id,
                    datetime, amount, comment
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: [
                "log-1", "plan-1", "meal-1", 10, 100,
                "2026-08-16T12:00:00.000Z", 1.0, nil,
            ]
        )
        return database
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private nonisolated struct NutritionPowerSyncProvider: PowerSyncDatabaseProviding {
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

private nonisolated struct NutritionUnavailablePowerSyncProvider: PowerSyncDatabaseProviding {
    func database() throws -> any PowerSyncDatabaseProtocol {
        throw PowerSyncControllerError.noSession
    }

    func status() -> VegaSyncStatus { .unavailable }
    func reconnect() throws { throw PowerSyncControllerError.noSession }
    func clearCurrentAccount() {}
}
