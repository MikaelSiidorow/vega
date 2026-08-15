import Foundation
import PowerSync

nonisolated struct WgerPowerSyncCredential: Equatable, Sendable {
    let endpoint: String
    let token: String
    let subject: String?
}

nonisolated struct WgerPowerSyncUploadResponse: Equatable, Sendable {
    let statusCode: Int
    let body: Data

    var containsRejection: Bool {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return object["error"] != nil
    }
}

nonisolated enum WgerPowerSyncRemoteError: Error, Equatable, Sendable, HTTPStatusProviding {
    case invalidCredentialsResponse
    case invalidEndpoint
    case status(Int)

    var statusCode: Int {
        switch self {
        case .invalidCredentialsResponse, .invalidEndpoint: 0
        case .status(let status): status
        }
    }
}

nonisolated protocol WgerPowerSyncRemote: Sendable {
    func credentials() async throws -> WgerPowerSyncCredential
    func upload(method: String, table: String, data: JsonParam) async throws
        -> WgerPowerSyncUploadResponse
}

actor WgerPowerSyncRemoteAPI: WgerPowerSyncRemote {
    private struct CredentialEnvelope: Decodable {
        let token: String
        let powersyncURL: String?

        enum CodingKeys: String, CodingKey {
            case token
            case powersyncURL = "powersync_url"
        }
    }

    private struct UploadEnvelope: Encodable {
        let table: String
        let data: JsonParam
    }

    private let client: any AuthenticatedRequestExecuting
    private let transport: any HTTPTransport

    init(
        client: any AuthenticatedRequestExecuting,
        transport: any HTTPTransport = URLSessionHTTPTransport()
    ) {
        self.client = client
        self.transport = transport
    }

    func credentials() async throws -> WgerPowerSyncCredential {
        try await client.perform { [transport] instance, session in
            var request = URLRequest(url: instance.appending(path: "api/v2/powersync-token"))
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await transport.data(for: request)
            guard (200...299).contains(response.statusCode) else {
                throw WgerPowerSyncRemoteError.status(response.statusCode)
            }
            let envelope = try JSONDecoder().decode(CredentialEnvelope.self, from: data)
            guard !envelope.token.isEmpty else {
                throw WgerPowerSyncRemoteError.invalidCredentialsResponse
            }
            guard
                let endpoint = envelope.powersyncURL?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                !endpoint.isEmpty,
                let components = URLComponents(string: endpoint),
                components.scheme == "https" || components.scheme == "http",
                components.host?.isEmpty == false
            else {
                throw WgerPowerSyncRemoteError.invalidEndpoint
            }
            return WgerPowerSyncCredential(
                endpoint: endpoint,
                token: envelope.token,
                subject: JWTSubject.value(in: envelope.token)
            )
        }
    }

    func upload(method: String, table: String, data: JsonParam) async throws
        -> WgerPowerSyncUploadResponse
    {
        try await client.perform { [transport] instance, session in
            var request = URLRequest(
                url: instance.appending(path: "api/v2/upload-powersync-data")
            )
            request.httpMethod = method
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(UploadEnvelope(table: table, data: data))
            let (body, response) = try await transport.data(for: request)
            if response.statusCode == 401 {
                throw WgerPowerSyncRemoteError.status(401)
            }
            return WgerPowerSyncUploadResponse(statusCode: response.statusCode, body: body)
        }
    }
}

nonisolated enum JWTSubject {
    static func value(in token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var encoded = String(segments[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let subject = object["sub"] as? String, !subject.isEmpty {
            return subject
        }
        if let subject = object["sub"] as? NSNumber {
            return subject.stringValue
        }
        return nil
    }
}

nonisolated struct PowerSyncUploadRejection: Equatable, Sendable {
    let table: String
    let operation: String
    let recordID: String
    let statusCode: Int
}

actor PowerSyncIssueStore {
    private(set) var latestRejection: PowerSyncUploadRejection?

    func record(_ rejection: PowerSyncUploadRejection) {
        latestRejection = rejection
    }

    func clear() {
        latestRejection = nil
    }
}

actor WgerPowerSyncConnector: PowerSyncBackendConnectorProtocol {
    private static let dateOnlyFields: [String: Set<String>] = [
        WgerPowerSyncTable.routine: ["start", "end"],
        WgerPowerSyncTable.workoutSession: ["date"],
        WgerPowerSyncTable.nutritionPlan: ["start", "end"],
    ]

    private let remote: any WgerPowerSyncRemote
    private let issueStore: PowerSyncIssueStore

    init(remote: any WgerPowerSyncRemote, issueStore: PowerSyncIssueStore) {
        self.remote = remote
        self.issueStore = issueStore
    }

    func fetchCredentials() async throws -> PowerSyncCredentials? {
        let value = try await remote.credentials()
        return PowerSyncCredentials(endpoint: value.endpoint, token: value.token)
    }

    func uploadData(database: any PowerSyncDatabaseProtocol) async throws {
        guard let transaction = try await database.getNextCrudTransaction() else { return }

        for operation in transaction.crud {
            let response = try await remote.upload(
                method: operation.op.rawValue,
                table: operation.table,
                data: Self.transformedData(
                    table: operation.table,
                    id: operation.id,
                    values: operation.opDataTyped
                )
            )
            if Self.isRetryable(response.statusCode) {
                throw WgerPowerSyncRemoteError.status(response.statusCode)
            }
            guard (200...299).contains(response.statusCode), !response.containsRejection else {
                await issueStore.record(
                    PowerSyncUploadRejection(
                        table: operation.table,
                        operation: operation.op.rawValue,
                        recordID: operation.id,
                        statusCode: response.statusCode
                    )
                )
                continue
            }
        }
        try await transaction.complete()
    }

    static func transformedData(table: String, id: String, values: JsonParam?) -> JsonParam {
        var result: JsonParam = ["id": .string(id)]
        let dateFields = dateOnlyFields[table] ?? []
        for (key, value) in values ?? [:] where key != "id" {
            let transformedKey = key.hasSuffix("_id") ? String(key.dropLast(3)) : key
            if dateFields.contains(transformedKey), case .string(let date) = value, date.count >= 10
            {
                result[transformedKey] = .string(String(date.prefix(10)))
            } else {
                result[transformedKey] = value
            }
        }
        return result
    }

    private static func isRetryable(_ status: Int) -> Bool {
        status == 401 || status == 408 || status == 429 || status >= 500
    }
}
