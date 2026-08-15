import Foundation
import WgerAPI

nonisolated protocol WeightHistoryFetching: Sendable {
    func weightHistory() async throws -> [WgerWeightEntry]
    func weightHistoryStream() async throws -> AsyncThrowingStream<[WgerWeightEntry], Error>
}

extension WeightHistoryFetching {
    nonisolated func weightHistoryStream() async throws
        -> AsyncThrowingStream<[WgerWeightEntry], Error>
    {
        let entries = try await weightHistory()
        return AsyncThrowingStream { continuation in
            continuation.yield(entries)
            continuation.finish()
        }
    }
}

nonisolated protocol WeightEntryCreating: Sendable {
    func createWeightEntry(date: Date, weight: String) async throws
}

nonisolated protocol WeightEntryUpdating: Sendable {
    func updateWeightEntry(id: String, date: Date, weight: String) async throws
}

nonisolated protocol WeightEntryDeleting: Sendable {
    func deleteWeightEntry(id: String) async throws
}

nonisolated protocol WeightDataStore:
    WeightHistoryFetching,
    WeightEntryCreating,
    WeightEntryUpdating,
    WeightEntryDeleting
{}

nonisolated protocol WeightTransport: Sendable {
    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerWeightEntry>

    func create(
        instance: InstanceURL,
        session: AuthenticationSession,
        date: Date,
        weight: String
    ) async throws

    func update(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: Int,
        date: Date,
        weight: String
    ) async throws

    func delete(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: Int
    ) async throws
}

nonisolated struct WgerWeightTransport: WeightTransport {
    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerWeightEntry> {
        let page = try await WgerAPIModule.weightEntries(
            serverURL: instance.url,
            accessToken: session.accessToken,
            limit: limit,
            offset: offset
        )
        return try WgerPage(
            values: page.results.map { try $0.vegaValue },
            hasNextPage: page.next != nil
        )
    }

    func create(
        instance: InstanceURL,
        session: AuthenticationSession,
        date: Date,
        weight: String
    ) async throws {
        _ = try await WgerAPIModule.createWeightEntry(
            serverURL: instance.url,
            accessToken: session.accessToken,
            date: date,
            weight: weight
        )
    }

    func update(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: Int,
        date: Date,
        weight: String
    ) async throws {
        _ = try await WgerAPIModule.updateWeightEntry(
            serverURL: instance.url,
            accessToken: session.accessToken,
            id: id,
            date: date,
            weight: weight
        )
    }

    func delete(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: Int
    ) async throws {
        try await WgerAPIModule.deleteWeightEntry(
            serverURL: instance.url,
            accessToken: session.accessToken,
            id: id
        )
    }
}

nonisolated struct WeightAPI: WeightDataStore {
    private let client: any AuthenticatedRequestExecuting
    private let transport: any WeightTransport
    private let pageSize: Int

    init(
        client: any AuthenticatedRequestExecuting,
        transport: any WeightTransport = WgerWeightTransport(),
        pageSize: Int = 100
    ) {
        self.client = client
        self.transport = transport
        self.pageSize = pageSize
    }

    func weightHistory() async throws -> [WgerWeightEntry] {
        try await client.perform { instance, session in
            var values: [WgerWeightEntry] = []
            var offset = 0
            while true {
                let page = try await transport.entries(
                    instance: instance,
                    session: session,
                    limit: pageSize,
                    offset: offset
                )
                values.append(contentsOf: page.values)
                guard page.hasNextPage else { break }
                offset += pageSize
            }
            return values.sorted { $0.date > $1.date }
        }
    }

    func createWeightEntry(date: Date, weight: String) async throws {
        try await client.perform { instance, session in
            try await transport.create(
                instance: instance,
                session: session,
                date: date,
                weight: weight
            )
        }
    }

    func updateWeightEntry(id: String, date: Date, weight: String) async throws {
        guard let id = Int(id) else { throw WgerModelError.invalidIdentifier(id) }
        try await client.perform { instance, session in
            try await transport.update(
                instance: instance,
                session: session,
                id: id,
                date: date,
                weight: weight
            )
        }
    }

    func deleteWeightEntry(id: String) async throws {
        guard let id = Int(id) else { throw WgerModelError.invalidIdentifier(id) }
        try await client.perform { instance, session in
            try await transport.delete(instance: instance, session: session, id: id)
        }
    }
}
