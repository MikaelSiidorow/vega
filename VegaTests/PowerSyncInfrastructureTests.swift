import Foundation
import PowerSync
import Testing

@testable import Vega

nonisolated struct PowerSyncInfrastructureTests {
    @Test
    func schemaContainsEveryVegaDataTableAndIsValid() throws {
        try wgerPowerSyncSchema.validate()

        let names = Set(wgerPowerSyncSchema.tables.map(\.name))
        #expect(names.contains(WgerPowerSyncTable.weightEntry))
        #expect(names.contains(WgerPowerSyncTable.logItem))
        #expect(names.contains(WgerPowerSyncTable.nutritionPlan))
        #expect(names.contains(WgerPowerSyncTable.workoutLog))
        #expect(names.contains(WgerPowerSyncTable.workoutSession))
        #expect(names.contains(WgerPowerSyncTable.routine))
    }

    @Test
    func connectorTransformsForeignKeysAndDateOnlyFieldsForWger() {
        let transformed = WgerPowerSyncConnector.transformedData(
            table: WgerPowerSyncTable.workoutSession,
            id: "session-uuid",
            values: [
                "routine_id": .int(42),
                "date": .string("2026-08-16T00:00:00.000Z"),
                "notes": .null,
                "id": .string("must-not-replace-client-id"),
            ]
        )

        #expect(transformed["id"] == .string("session-uuid"))
        #expect(transformed["routine"] == .int(42))
        #expect(transformed["routine_id"] == nil)
        #expect(transformed["date"] == .string("2026-08-16"))
        #expect(transformed["notes"] == .null)
    }

    @Test
    func accountDatabaseKeysAreStableAndIsolated() throws {
        let firstHost = try InstanceURL("one.example")
        let secondHost = try InstanceURL("two.example")

        let first = WgerPowerSyncController.accountKey(instance: firstHost, subject: "user-1")
        #expect(first == WgerPowerSyncController.accountKey(instance: firstHost, subject: "user-1"))
        #expect(first != WgerPowerSyncController.accountKey(instance: firstHost, subject: "user-2"))
        #expect(
            first != WgerPowerSyncController.accountKey(instance: secondHost, subject: "user-1"))
        #expect(first.count == 32)
    }

    @Test
    func controllerUsesIsolatedDatabasesAndReconnectsTheActiveAccount() async throws {
        let firstHost = try InstanceURL("one.example")
        let secondHost = try InstanceURL("two.example")
        let sessions = MutablePowerSyncSession(
            Self.session(instance: firstHost, subject: "user-1")
        )
        let factory = DatabaseFactoryRecorder()
        let connections = ConnectionRecorder()
        let controller = WgerPowerSyncController(
            sessionCoordinator: sessions,
            remote: UploadRemote(responses: []),
            databaseFactory: { factory.make(filename: $0) },
            connectDatabase: { _, _ in await connections.record() }
        )

        let firstDatabase = try await controller.database()
        try await firstDatabase.execute(
            sql: "INSERT INTO weight_weightentry (id, date, weight) VALUES (?, ?, ?)",
            parameters: ["private-weight", "2026-08-16T07:30:00.000Z", 79.5]
        )
        let reusedDatabase = try await controller.database()
        #expect(reusedDatabase as AnyObject === firstDatabase as AnyObject)

        await sessions.set(Self.session(instance: secondHost, subject: "user-1"))
        let secondDatabase = try await controller.database()
        #expect(try await Self.weightCount(in: secondDatabase) == 0)

        await sessions.set(Self.session(instance: secondHost, subject: "user-2"))
        let thirdDatabase = try await controller.database()
        #expect(try await Self.weightCount(in: thirdDatabase) == 0)

        let filenames = factory.filenames
        #expect(filenames.count == 3)
        #expect(Set(filenames).count == 3)
        #expect(filenames.allSatisfy { $0.hasPrefix("vega-powersync-") })

        try await controller.reconnect()
        let connectionCount = await connections.count
        #expect(connectionCount == 4)
        try await controller.clearCurrentAccount()
    }

    @Test
    func extractsStringAndNumericJWTSubjects() throws {
        #expect(JWTSubject.value(in: token(payload: #"{"sub":"person-7"}"#)) == "person-7")
        #expect(JWTSubject.value(in: token(payload: #"{"sub":42}"#)) == "42")
        #expect(JWTSubject.value(in: "opaque") == nil)
    }

    @Test
    func connectorCompletesSuccessfulUploads() async throws {
        let database = try await makeDatabase()
        let remote = UploadRemote(responses: [Self.response(204)])
        let issueStore = PowerSyncIssueStore()
        let connector = WgerPowerSyncConnector(remote: remote, issueStore: issueStore)
        try await database.execute(
            sql: "INSERT INTO weight_weightentry (id, date, weight) VALUES (?, ?, ?)",
            parameters: ["local-weight", "2026-08-16T07:30:00.000Z", 79.5]
        )

        try await connector.uploadData(database: database)

        let requests = await remote.requests
        #expect(requests.count == 1)
        #expect(requests.first?.method == "PUT")
        #expect(requests.first?.table == WgerPowerSyncTable.weightEntry)
        #expect(requests.first?.data["id"] == .string("local-weight"))
        #expect(try await database.getNextCrudTransaction() == nil)
        #expect(await issueStore.latestRejection == nil)
        try await database.close()
    }

    @Test
    func connectorLeavesTransientFailuresQueuedForRetry() async throws {
        let database = try await makeDatabase()
        let remote = UploadRemote(responses: [Self.response(503)])
        let connector = WgerPowerSyncConnector(
            remote: remote,
            issueStore: PowerSyncIssueStore()
        )
        try await database.execute(
            sql: "INSERT INTO weight_weightentry (id, date, weight) VALUES (?, ?, ?)",
            parameters: ["retry-weight", "2026-08-16T07:30:00.000Z", 79.5]
        )

        await #expect(throws: WgerPowerSyncRemoteError.status(503)) {
            try await connector.uploadData(database: database)
        }

        let queued = try #require(try await database.getNextCrudTransaction())
        #expect(queued.crud.map(\.id) == ["retry-weight"])
        try await queued.complete()
        try await database.close()
    }

    @Test
    func connectorRecordsPermanentServerRejectionsWithoutBlockingTheQueue() async throws {
        let database = try await makeDatabase()
        let remote = UploadRemote(
            responses: [
                WgerPowerSyncUploadResponse(
                    statusCode: 200,
                    error: "invalid data",
                    details: nil
                )
            ]
        )
        let issueStore = PowerSyncIssueStore()
        let connector = WgerPowerSyncConnector(remote: remote, issueStore: issueStore)
        try await database.execute(
            sql: "INSERT INTO weight_weightentry (id, date, weight) VALUES (?, ?, ?)",
            parameters: ["rejected-weight", "2026-08-16T07:30:00.000Z", 79.5]
        )

        try await connector.uploadData(database: database)

        #expect(try await database.getNextCrudTransaction() == nil)
        #expect(
            await issueStore.latestRejection
                == PowerSyncUploadRejection(
                    table: WgerPowerSyncTable.weightEntry,
                    operation: "PUT",
                    recordID: "rejected-weight",
                    statusCode: 200
                )
        )
        try await database.close()
    }

    private func token(payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private func makeDatabase() async throws -> any PowerSyncDatabaseProtocol {
        let database = PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
        try await database.disconnectAndClear()
        return database
    }

    private static func response(_ statusCode: Int) -> WgerPowerSyncUploadResponse {
        WgerPowerSyncUploadResponse(statusCode: statusCode, error: nil, details: nil)
    }

    private static func session(instance: InstanceURL, subject: String) -> ActiveSession {
        ActiveSession(
            instance: instance,
            credentials: AuthenticationSession(
                accessToken: token(payload: #"{"sub":"\#(subject)"}"#),
                refreshToken: "refresh"
            )
        )
    }

    private static func token(payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }

    private static func weightCount(in database: any PowerSyncDatabaseProtocol) async throws
        -> Int
    {
        try await database.getOptional(
            sql: "SELECT count(*) AS count FROM weight_weightentry",
            parameters: [],
            mapper: { try $0.getInt(name: "count") }
        ) ?? 0
    }
}

private actor MutablePowerSyncSession: SessionCoordinating {
    private var session: ActiveSession?

    init(_ session: ActiveSession?) {
        self.session = session
    }

    func set(_ session: ActiveSession?) {
        self.session = session
    }

    func establish(instance: InstanceURL, credentials: AuthenticationSession) {
        session = ActiveSession(instance: instance, credentials: credentials)
    }

    func restore() -> ActiveSession? { session }
    func current() -> ActiveSession? { session }

    func refresh() throws -> ActiveSession {
        guard let session else { throw SessionCoordinatorError.noSession }
        return session
    }

    func clear() {
        session = nil
    }
}

private final class DatabaseFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedFilenames: [String] = []

    var filenames: [String] {
        lock.withLock { storedFilenames }
    }

    func make(filename: String) -> any PowerSyncDatabaseProtocol {
        lock.withLock { storedFilenames.append(filename) }
        return PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: ":memory:")
    }
}

private actor ConnectionRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private nonisolated struct UploadRequest: Sendable {
    let method: String
    let table: String
    let data: JsonParam
}

private actor UploadRemote: WgerPowerSyncRemote {
    private(set) var requests: [UploadRequest] = []
    private var responses: [WgerPowerSyncUploadResponse]

    init(responses: [WgerPowerSyncUploadResponse]) {
        self.responses = responses
    }

    func credentials() -> WgerPowerSyncCredential {
        WgerPowerSyncCredential(
            endpoint: "https://powersync.example",
            token: "token",
            subject: "test-user"
        )
    }

    func upload(method: String, table: String, data: JsonParam) throws
        -> WgerPowerSyncUploadResponse
    {
        requests.append(UploadRequest(method: method, table: table, data: data))
        return responses.removeFirst()
    }
}
