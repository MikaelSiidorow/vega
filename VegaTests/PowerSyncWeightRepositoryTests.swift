import Foundation
import PowerSync
import Testing

@testable import Vega

nonisolated struct PowerSyncWeightRepositoryTests {
    @Test
    func offlineMutationsReadLocallyAndQueueUploads() async throws {
        let database = try await makeDatabase()
        let fallback = FixtureWeightStore(entries: [])
        let repository = PowerSyncWeightRepository(
            powerSync: StaticPowerSyncProvider(database: database, hasSynced: true),
            fallback: fallback,
            makeID: { "weight-offline-1" }
        )
        let originalDate = try #require(Self.date("2026-08-16T07:30:00Z"))
        let updatedDate = try #require(Self.date("2026-08-16T08:00:00Z"))

        try await repository.createWeightEntry(date: originalDate, weight: "79.5")

        #expect(
            try await repository.weightHistory()
                == [WgerWeightEntry(id: "weight-offline-1", date: originalDate, weight: 79.5)]
        )
        var transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.count == 1)
        #expect(transaction.crud[0].op == .put)
        #expect(transaction.crud[0].table == WgerPowerSyncTable.weightEntry)
        #expect(transaction.crud[0].id == "weight-offline-1")
        try await transaction.complete()

        try await repository.updateWeightEntry(
            id: "weight-offline-1",
            date: updatedDate,
            weight: "79.2"
        )

        #expect(
            try await repository.weightHistory()
                == [WgerWeightEntry(id: "weight-offline-1", date: updatedDate, weight: 79.2)]
        )
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.count == 1)
        #expect(transaction.crud[0].op == .patch)
        try await transaction.complete()

        try await repository.deleteWeightEntry(id: "weight-offline-1")

        #expect(try await repository.weightHistory().isEmpty)
        transaction = try #require(try await database.getNextCrudTransaction())
        #expect(transaction.crud.count == 1)
        #expect(transaction.crud[0].op == .delete)
        try await database.close()
    }

    @Test
    func watchPublishesLocalWritesWithoutReloadingFromREST() async throws {
        let database = try await makeDatabase()
        let repository = PowerSyncWeightRepository(
            powerSync: StaticPowerSyncProvider(database: database, hasSynced: true),
            fallback: FixtureWeightStore(entries: []),
            makeID: { "watched-weight" }
        )
        let date = try #require(Self.date("2026-08-16T07:30:00Z"))
        let stream = try await repository.weightHistoryStream()
        let observation = Task { () throws -> [WgerWeightEntry] in
            var iterator = stream.makeAsyncIterator()
            _ = try await iterator.next()
            return try #require(try await iterator.next())
        }

        try await repository.createWeightEntry(date: date, weight: "80")

        #expect(
            try await observation.value
                == [WgerWeightEntry(id: "watched-weight", date: date, weight: 80)]
        )
    }

    @Test
    func emptyDatabaseUsesRESTUntilFirstSyncCompletes() async throws {
        let database = try await makeDatabase()
        let fallbackDate = try #require(Self.date("2026-08-15T07:30:00Z"))
        let repository = PowerSyncWeightRepository(
            powerSync: StaticPowerSyncProvider(database: database, hasSynced: false),
            fallback: FixtureWeightStore(entries: [
                WgerWeightEntry(id: "rest-weight", date: fallbackDate, weight: 80)
            ])
        )
        let stream = try await repository.weightHistoryStream()
        var iterator = stream.makeAsyncIterator()

        let initial = try #require(try await iterator.next())

        #expect(initial.map(\.id) == ["rest-weight"])
    }

    @Test
    func fallsBackToRESTWhenPowerSyncCannotOpen() async throws {
        let date = try #require(Self.date("2026-08-16T07:30:00Z"))
        let fallback = FixtureWeightStore(entries: [
            WgerWeightEntry(id: "42", date: date, weight: 81)
        ])
        let repository = PowerSyncWeightRepository(
            powerSync: UnavailablePowerSyncProvider(),
            fallback: fallback
        )

        #expect(try await repository.weightHistory().map(\.id) == ["42"])
        try await repository.updateWeightEntry(id: "42", date: date, weight: "80.5")
        #expect(try await repository.weightHistory().first?.weight == 80.5)
        try await repository.deleteWeightEntry(id: "42")
        #expect(try await repository.weightHistory().isEmpty)
    }

    @Test
    func rejectsCorruptLocalDatesInsteadOfLooseningTheDomainType() async throws {
        let database = try await makeDatabase()
        try await database.execute(
            sql: "INSERT INTO weight_weightentry (id, date, weight) VALUES (?, ?, ?)",
            parameters: ["bad-date", "16/08/2026", 80.0]
        )
        let repository = PowerSyncWeightRepository(
            powerSync: StaticPowerSyncProvider(database: database, hasSynced: true),
            fallback: FixtureWeightStore(entries: [])
        )

        await #expect(
            throws: PowerSyncRepositoryError.invalidDate(
                table: WgerPowerSyncTable.weightEntry,
                recordID: "bad-date",
                value: "16/08/2026"
            )
        ) {
            try await repository.weightHistory()
        }
        try await database.close()
    }

    private func makeDatabase() async throws -> any PowerSyncDatabaseProtocol {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        return database
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }
}

private nonisolated struct StaticPowerSyncProvider: PowerSyncDatabaseProviding {
    let storedDatabase: any PowerSyncDatabaseProtocol
    let hasSynced: Bool

    init(database: any PowerSyncDatabaseProtocol, hasSynced: Bool) {
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

private nonisolated struct UnavailablePowerSyncProvider: PowerSyncDatabaseProviding {
    func database() throws -> any PowerSyncDatabaseProtocol {
        throw PowerSyncControllerError.noSession
    }

    func status() -> VegaSyncStatus { .unavailable }
    func reconnect() throws { throw PowerSyncControllerError.noSession }
    func clearCurrentAccount() {}
}
