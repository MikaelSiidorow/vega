import CryptoKit
import Foundation
import PowerSync

nonisolated enum PowerSyncControllerError: Error, Equatable, Sendable {
    case noSession
    case noAccountIdentity
}

nonisolated struct VegaSyncStatus: Equatable, Sendable {
    let connected: Bool
    let connecting: Bool
    let downloading: Bool
    let uploading: Bool
    let hasSynced: Bool
    let lastSyncedAt: Date?
    let pendingUploads: Int
    let errorMessage: String?
    let rejection: PowerSyncUploadRejection?

    static let unavailable = VegaSyncStatus(
        connected: false,
        connecting: false,
        downloading: false,
        uploading: false,
        hasSynced: false,
        lastSyncedAt: nil,
        pendingUploads: 0,
        errorMessage: nil,
        rejection: nil
    )
}

nonisolated protocol PowerSyncDatabaseProviding: Sendable {
    func database() async throws -> any PowerSyncDatabaseProtocol
    func status() async -> VegaSyncStatus
    func reconnect() async throws
    func clearCurrentAccount() async throws
}

actor WgerPowerSyncController: PowerSyncDatabaseProviding {
    typealias DatabaseFactory = @Sendable (String) -> any PowerSyncDatabaseProtocol
    typealias DatabaseConnector =
        @Sendable (
            any PowerSyncDatabaseProtocol,
            WgerPowerSyncConnector
        ) async throws -> Void

    private let sessionCoordinator: any SessionCoordinating
    private let remote: any WgerPowerSyncRemote
    private let issueStore: PowerSyncIssueStore
    private let databaseFactory: DatabaseFactory
    private let connectDatabase: DatabaseConnector

    private var activeKey: String?
    private var activeDatabase: (any PowerSyncDatabaseProtocol)?
    private var activeConnector: WgerPowerSyncConnector?

    init(
        sessionCoordinator: any SessionCoordinating,
        remote: any WgerPowerSyncRemote,
        issueStore: PowerSyncIssueStore = PowerSyncIssueStore(),
        databaseFactory: @escaping DatabaseFactory = { filename in
            PowerSyncDatabase(schema: wgerPowerSyncSchema, dbFilename: filename)
        },
        connectDatabase: @escaping DatabaseConnector = { database, connector in
            try await database.connect(connector: connector)
        }
    ) {
        self.sessionCoordinator = sessionCoordinator
        self.remote = remote
        self.issueStore = issueStore
        self.databaseFactory = databaseFactory
        self.connectDatabase = connectDatabase
    }

    func database() async throws -> any PowerSyncDatabaseProtocol {
        guard let session = await sessionCoordinator.current() else {
            throw PowerSyncControllerError.noSession
        }
        var subject = JWTSubject.value(in: session.credentials.accessToken)
        if subject == nil {
            subject = try? await remote.credentials().subject
        }
        guard let subject, !subject.isEmpty else {
            throw PowerSyncControllerError.noAccountIdentity
        }
        let key = Self.accountKey(instance: session.instance, subject: subject)
        if activeKey == key, let activeDatabase {
            return activeDatabase
        }

        if let activeDatabase {
            try await activeDatabase.close()
        }
        let database = databaseFactory("vega-powersync-\(key).sqlite")
        _ = try await database.getOptional(
            sql: "SELECT 1",
            parameters: [],
            mapper: { try $0.getInt(index: 0) }
        )
        if database.currentStatus.hasSynced != true {
            _ = try await remote.credentials()
        }
        let connector = WgerPowerSyncConnector(remote: remote, issueStore: issueStore)
        activeKey = key
        activeDatabase = database
        activeConnector = connector
        try await connectDatabase(database, connector)
        return database
    }

    func status() async -> VegaSyncStatus {
        guard let database = activeDatabase else { return .unavailable }
        let current = database.currentStatus
        let pendingUploads =
            (try? await database.getOptional(
                sql: "SELECT count(*) AS count FROM ps_crud",
                parameters: [],
                mapper: { try $0.getInt(name: "count") }
            )) ?? 0
        let rejection = await issueStore.latestRejection
        return VegaSyncStatus(
            connected: current.connected,
            connecting: current.connecting,
            downloading: current.downloading,
            uploading: current.uploading,
            hasSynced: current.hasSynced == true,
            lastSyncedAt: current.lastSyncedAt,
            pendingUploads: pendingUploads,
            errorMessage: current.anyError.map { String(describing: $0) },
            rejection: rejection
        )
    }

    func reconnect() async throws {
        let database = try await database()
        guard let activeConnector else { return }
        try await database.disconnect()
        try await connectDatabase(database, activeConnector)
    }

    func clearCurrentAccount() async throws {
        guard let database = activeDatabase else { return }
        try await database.disconnectAndClear()
        try await database.close(deleteDatabase: true)
        self.activeDatabase = nil
        activeConnector = nil
        activeKey = nil
        await issueStore.clear()
    }

    nonisolated static func accountKey(instance: InstanceURL, subject: String) -> String {
        let value = Data("\(instance.url.absoluteString)|\(subject)".utf8)
        return SHA256.hash(data: value).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}
