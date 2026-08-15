import Foundation
import Testing
import WgerAPI

@testable import Vega

nonisolated struct WeightAPITests {
    @Test
    func paginatesSortsAndForwardsMutations() async throws {
        let oldest = try Self.date("2026-06-01T08:00:00Z")
        let middle = try Self.date("2026-07-01T08:00:00Z")
        let newest = try Self.date("2026-08-01T08:00:00Z")
        let transport = WeightTransportStub(pages: [
            0: WgerPage(
                values: [Self.entry(2, date: middle, weight: 81.4)],
                hasNextPage: true
            ),
            2: WgerPage(
                values: [
                    Self.entry(1, date: oldest, weight: 82.1),
                    Self.entry(3, date: newest, weight: 80.8),
                ],
                hasNextPage: false
            ),
        ])
        let api = WeightAPI(
            client: WeightAuthenticatedExecutor(),
            transport: transport,
            pageSize: 2
        )

        let history = try await api.weightHistory()
        try await api.createWeightEntry(date: newest, weight: "80.8")
        try await api.updateWeightEntry(id: "2", date: middle, weight: "81.2")
        try await api.deleteWeightEntry(id: "1")

        #expect(history.map(\.id) == ["3", "2", "1"])
        #expect(await transport.offsets == [0, 2])
        #expect(
            await transport.created == WeightMutation(id: nil, date: newest, weight: "80.8")
        )
        #expect(
            await transport.updated == WeightMutation(id: 2, date: middle, weight: "81.2")
        )
        #expect(await transport.deletedID == 1)
    }

    @Test
    func strictlyConvertsGeneratedDecimalWeight() throws {
        let date = try Self.date("2026-08-01T08:00:00Z")
        let generated = Components.Schemas.WeightEntry(
            id: 7,
            date: date,
            weight: "80.25",
            user: 3
        )

        #expect(try generated.vegaValue == WgerWeightEntry(id: "7", date: date, weight: 80.25))
    }

    @Test
    func rejectsInvalidGeneratedDecimalWeight() throws {
        let generated = Components.Schemas.WeightEntry(
            id: 7,
            date: Date(),
            weight: "not-a-number",
            user: 3
        )

        #expect(throws: WgerModelError.invalidWeight("not-a-number")) {
            try generated.vegaValue
        }
    }

    private static func entry(_ id: Int, date: Date, weight: Decimal) -> WgerWeightEntry {
        WgerWeightEntry(id: String(id), date: date, weight: weight)
    }

    private static func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}

private nonisolated struct WeightAuthenticatedExecutor: AuthenticatedRequestExecuting {
    func perform<Value: Sendable>(
        _ operation: @Sendable (InstanceURL, AuthenticationSession) async throws -> Value
    ) async throws -> Value {
        try await operation(
            InstanceURL("wger.example"),
            AuthenticationSession(accessToken: "access", refreshToken: "refresh")
        )
    }
}

private actor WeightTransportStub: WeightTransport {
    private let pages: [Int: WgerPage<WgerWeightEntry>]
    private(set) var offsets: [Int] = []
    private(set) var created: WeightMutation?
    private(set) var updated: WeightMutation?
    private(set) var deletedID: Int?

    init(pages: [Int: WgerPage<WgerWeightEntry>]) {
        self.pages = pages
    }

    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) -> WgerPage<WgerWeightEntry> {
        offsets.append(offset)
        return pages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func create(
        instance: InstanceURL,
        session: AuthenticationSession,
        date: Date,
        weight: String
    ) {
        created = WeightMutation(id: nil, date: date, weight: weight)
    }

    func update(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: Int,
        date: Date,
        weight: String
    ) {
        updated = WeightMutation(id: id, date: date, weight: weight)
    }

    func delete(instance: InstanceURL, session: AuthenticationSession, id: Int) {
        deletedID = id
    }
}

private nonisolated struct WeightMutation: Equatable, Sendable {
    let id: Int?
    let date: Date
    let weight: String
}
