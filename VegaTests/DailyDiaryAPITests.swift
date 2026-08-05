import Foundation
import Testing

@testable import Vega

nonisolated struct DailyDiaryAPITests {
    @Test
    func selectsNewestActivePlanPaginatesAndHydratesDistinctIngredients() async throws {
        let transport = DiaryTransportStub(
            planPages: [
                0: WgerPage(
                    values: [
                        Self.plan("future", start: "2026-08-06"),
                        Self.plan("older", start: "2026-01-01"),
                    ],
                    hasNextPage: true
                ),
                2: WgerPage(
                    values: [Self.plan("active", start: "2026-08-01")],
                    hasNextPage: false
                ),
            ],
            entryPages: [
                0: WgerPage(
                    values: [Self.entry("one", ingredientID: 12)],
                    hasNextPage: true
                ),
                1: WgerPage(
                    values: [
                        Self.entry("two", ingredientID: 12),
                        Self.entry("three", ingredientID: 34),
                    ],
                    hasNextPage: false
                ),
            ],
            ingredientValues: [Self.ingredient(12), Self.ingredient(34)]
        )
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 60 * 60))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-05T12:00:00Z"))

        let result = try await api.diary(for: date, calendar: calendar)

        #expect(result.plan?.id == "active")
        #expect(result.entries.compactMap(\.id) == ["one", "two", "three"])
        #expect(result.ingredients.keys.sorted() == [12, 34])
        #expect(await transport.planOffsets == [0, 2])
        #expect(await transport.entryOffsets == [0, 1])
        #expect(await transport.requestedPlanIDs == ["active", "active"])
        #expect(await transport.ingredientRequests == [[12, 34]])

        let requestedIntervals = await transport.requestedIntervals
        let bounds = try #require(requestedIntervals.first)
        #expect(calendar.component(.hour, from: bounds.start) == 0)
        #expect(calendar.dateComponents([.day], from: bounds.start, to: bounds.end).day == 1)

        _ = try await api.diary(for: date, calendar: calendar)
        #expect(await transport.ingredientRequests == [[12, 34]])
    }

    @Test
    func returnsEmptyDiaryWhenNoPlanIsActive() async throws {
        let transport = DiaryTransportStub(
            planPages: [
                0: WgerPage(
                    values: [Self.plan("past", start: "2026-01-01", end: "2026-01-31")],
                    hasNextPage: false
                )
            ]
        )
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )

        let result = try await api.diary(for: Date(), calendar: Calendar.current)

        #expect(result == .empty)
        #expect(await transport.entryOffsets.isEmpty)
        #expect(await transport.ingredientRequests.isEmpty)
    }

    private static func plan(
        _ id: String,
        start: String,
        end: String? = nil
    ) -> WgerNutritionPlan {
        WgerNutritionPlan(
            id: id,
            creationDate: start,
            start: start,
            end: end,
            description: nil
        )
    }

    private static func entry(_ id: String, ingredientID: Int) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: "active",
            mealID: nil,
            ingredientID: ingredientID,
            weightUnitID: nil,
            date: nil,
            amount: "100"
        )
    }

    private static func ingredient(_ id: Int) -> WgerIngredient {
        WgerIngredient(
            id: id,
            name: "Ingredient \(id)",
            brand: nil,
            energy: 100,
            protein: "10",
            carbohydrates: "20",
            fat: "5"
        )
    }
}

private nonisolated struct DiaryAuthenticatedExecutor: AuthenticatedRequestExecuting {
    func perform<Value: Sendable>(
        _ operation: @Sendable (InstanceURL, AuthenticationSession) async throws -> Value
    ) async throws -> Value {
        try await operation(
            InstanceURL("wger.example"),
            AuthenticationSession(accessToken: "access", refreshToken: "refresh")
        )
    }
}

private actor DiaryTransportStub: DailyDiaryTransport {
    private let planPages: [Int: WgerPage<WgerNutritionPlan>]
    private let entryPages: [Int: WgerPage<WgerNutritionDiaryEntry>]
    private let ingredientValues: [WgerIngredient]
    private(set) var planOffsets: [Int] = []
    private(set) var entryOffsets: [Int] = []
    private(set) var requestedPlanIDs: [String] = []
    private(set) var requestedIntervals: [DateInterval] = []
    private(set) var ingredientRequests: [[Int]] = []

    init(
        planPages: [Int: WgerPage<WgerNutritionPlan>],
        entryPages: [Int: WgerPage<WgerNutritionDiaryEntry>] = [:],
        ingredientValues: [WgerIngredient] = []
    ) {
        self.planPages = planPages
        self.entryPages = entryPages
        self.ingredientValues = ingredientValues
    }

    func plans(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) -> WgerPage<WgerNutritionPlan> {
        planOffsets.append(offset)
        return planPages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        planID: String,
        from start: Date,
        to end: Date,
        limit: Int,
        offset: Int
    ) -> WgerPage<WgerNutritionDiaryEntry> {
        entryOffsets.append(offset)
        requestedPlanIDs.append(planID)
        requestedIntervals.append(DateInterval(start: start, end: end))
        return entryPages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func ingredients(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) -> [WgerIngredient] {
        ingredientRequests.append(ids)
        return ingredientValues.filter { ids.contains($0.id) }
    }
}
