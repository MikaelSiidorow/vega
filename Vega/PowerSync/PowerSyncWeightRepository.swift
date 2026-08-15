import Foundation
import PowerSync

nonisolated enum PowerSyncRepositoryError: Error, Equatable, Sendable {
    case invalidDate(table: String, recordID: String, value: String)
}

/// Local-first weight storage. PowerSync records every local write in `ps_crud`
/// and uploads it when a connection is available; callers never need separate
/// online and offline mutation paths.
nonisolated struct PowerSyncWeightRepository: WeightDataStore {
    private static let historySQL = """
        SELECT id, date, weight
        FROM weight_weightentry
        ORDER BY date DESC
        """

    private let powerSync: any PowerSyncDatabaseProviding
    private let fallback: any WeightDataStore
    private let makeID: @Sendable () -> String

    init(
        powerSync: any PowerSyncDatabaseProviding,
        fallback: any WeightDataStore,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.powerSync = powerSync
        self.fallback = fallback
        self.makeID = makeID
    }

    func weightHistory() async throws -> [WgerWeightEntry] {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.weightHistory()
        }
        let values = try await Self.readHistory(from: database)
        let status = await powerSync.status()
        if values.isEmpty, !status.hasSynced {
            return try await fallback.weightHistory()
        }
        return values
    }

    func weightHistoryStream() async throws
        -> AsyncThrowingStream<[WgerWeightEntry], Error>
    {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.weightHistoryStream()
        }
        let updates = try database.watch(
            sql: Self.historySQL,
            parameters: [],
            mapper: Self.decode
        )
        return AsyncThrowingStream { continuation in
            let observation = Task {
                do {
                    for try await values in updates {
                        if values.isEmpty, !(await powerSync.status()).hasSynced {
                            continuation.yield(try await fallback.weightHistory())
                        } else {
                            continuation.yield(values)
                        }
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

    func createWeightEntry(date: Date, weight: String) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.createWeightEntry(date: date, weight: weight)
            return
        }
        try await database.execute(
            sql: """
                INSERT INTO weight_weightentry (id, date, weight)
                VALUES (?, ?, ?)
                """,
            parameters: [
                makeID(),
                PowerSyncValueCodec.encodeDateTime(date),
                try Self.double(weight),
            ]
        )
    }

    func updateWeightEntry(id: String, date: Date, weight: String) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.updateWeightEntry(id: id, date: date, weight: weight)
            return
        }
        try await database.execute(
            sql: """
                UPDATE weight_weightentry
                SET date = ?, weight = ?
                WHERE id = ?
                """,
            parameters: [PowerSyncValueCodec.encodeDateTime(date), try Self.double(weight), id]
        )
    }

    func deleteWeightEntry(id: String) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.deleteWeightEntry(id: id)
            return
        }
        try await database.execute(
            sql: "DELETE FROM weight_weightentry WHERE id = ?",
            parameters: [id]
        )
    }

    private static func readHistory(from database: any PowerSyncDatabaseProtocol) async throws
        -> [WgerWeightEntry]
    {
        try await database.getAll(sql: historySQL, parameters: [], mapper: decode)
    }

    private static func decode(_ cursor: SqlCursor) throws -> WgerWeightEntry {
        let id = try cursor.getString(name: "id")
        let encodedDate = try cursor.getString(name: "date")
        guard let date = PowerSyncValueCodec.decodeDateTime(encodedDate) else {
            throw PowerSyncRepositoryError.invalidDate(
                table: WgerPowerSyncTable.weightEntry,
                recordID: id,
                value: encodedDate
            )
        }
        return WgerWeightEntry(
            id: id,
            date: date,
            weight: Decimal(try cursor.getDouble(name: "weight"))
        )
    }

    private static func double(_ value: String) throws -> Double {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else { throw WgerModelError.invalidWeight(value) }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

}
