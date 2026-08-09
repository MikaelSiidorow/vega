import Foundation
import Testing
import WgerAPI

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
            mealPages: [
                0: WgerPage(
                    values: [Self.meal("breakfast", order: 1)],
                    hasNextPage: true
                ),
                1: WgerPage(
                    values: [Self.meal("dinner", order: 2)],
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
        #expect(result.meals.map(\.id) == ["breakfast", "dinner"])
        #expect(await transport.planOffsets == [0, 2])
        #expect(await transport.entryOffsets == [0, 1])
        #expect(await transport.requestedPlanIDs == ["active", "active"])
        #expect(await transport.ingredientRequests == [[12, 34]])
        #expect(await transport.mealOffsets == [0, 1])
        #expect(await transport.requestedMealPlanIDs == ["active", "active"])

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
        #expect(await transport.mealOffsets.isEmpty)
    }

    @Test
    func loadsAndPaginatesSixWeeksOfRecentDiaryHistory() async throws {
        let firstDate = try Self.date("2026-07-20T08:00:00Z")
        let secondDate = try Self.date("2026-08-05T08:00:00Z")
        let transport = DiaryTransportStub(
            planPages: [:],
            entryPages: [
                0: WgerPage(
                    values: [Self.entry("one", ingredientID: 12, date: firstDate)],
                    hasNextPage: true
                ),
                1: WgerPage(
                    values: [Self.entry("two", ingredientID: 34, date: secondDate)],
                    hasNextPage: false
                ),
            ],
            ingredientValues: [Self.ingredient(12), Self.ingredient(34)]
        )
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )
        let end = try Self.date("2026-08-06T12:00:00Z")

        let result = try await api.recentDiary(
            planID: "active",
            before: end,
            calendar: Self.utcCalendar
        )

        #expect(result.entries.compactMap(\.id) == ["one", "two"])
        #expect(result.ingredients.keys.sorted() == [12, 34])
        #expect(await transport.entryOffsets == [0, 1])
        #expect(await transport.requestedPlanIDs == ["active", "active"])
        #expect(await transport.ingredientRequests == [[12, 34]])
        let requestedIntervals = await transport.requestedIntervals
        let interval = try #require(requestedIntervals.first)
        #expect(interval.end == end)
        #expect(
            Self.utcCalendar.dateComponents([.day], from: interval.start, to: interval.end).day
                == 42
        )
    }

    @Test
    func deletesEntryThroughAuthenticatedTransport() async throws {
        let transport = DiaryTransportStub(planPages: [:])
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )

        try await api.deleteDiaryEntry(id: "entry-id")

        #expect(await transport.deletedEntryIDs == ["entry-id"])
    }

    @Test
    func updatesEditableFieldsThroughAuthenticatedTransport() async throws {
        let transport = DiaryTransportStub(planPages: [:])
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )

        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-05T12:30:00Z"))
        try await api.updateDiaryEntry(
            id: "entry-id",
            amount: "1.5",
            weightUnitID: 31,
            date: date,
            mealID: "dinner"
        )

        #expect(
            await transport.entryUpdates
                == [
                    DiaryEntryUpdate(
                        id: "entry-id",
                        amount: "1.5",
                        weightUnitID: 31,
                        date: date,
                        mealID: "dinner"
                    )
                ]
        )
    }

    @Test
    func searchesAndCreatesEntriesThroughAuthenticatedTransport() async throws {
        let ingredient = Self.ingredient(42)
        let transport = DiaryTransportStub(
            planPages: [:],
            ingredientValues: [ingredient]
        )
        let api = DailyDiaryAPI(
            client: DiaryAuthenticatedExecutor(),
            transport: transport
        )

        #expect(try await api.searchIngredients(query: "  oats ") == [ingredient])
        #expect(await transport.searchQueries == ["oats"])
        #expect(try await api.searchIngredients(query: "x").isEmpty)

        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-05T12:30:00Z"))
        try await api.createDiaryEntry(
            planID: "active",
            ingredientID: 42,
            amount: "1.5",
            weightUnitID: 31,
            date: date,
            mealID: "lunch"
        )

        #expect(
            await transport.createdEntries
                == [
                    NutritionDiaryEntryCreate(
                        plan: "active",
                        ingredient: 42,
                        amount: "1.5",
                        weightUnit: 31,
                        datetime: date,
                        meal: "lunch"
                    )
                ]
        )
    }

    @Test
    func patchExplicitlyClearsWeightUnitAndMeal() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-05T12:30:00Z"))
        let patch = NutritionDiaryEntryPatch(
            amount: "150",
            weightUnit: nil,
            datetime: date,
            meal: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(patch)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["amount"] as? String == "150")
        #expect(json["weight_unit"] is NSNull)
        #expect(json["meal"] is NSNull)
        #expect(json["datetime"] as? String == "2026-08-05T12:30:00Z")
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

    private static func entry(
        _ id: String,
        ingredientID: Int,
        date: Date? = nil
    ) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: "active",
            mealID: nil,
            ingredientID: ingredientID,
            weightUnitID: nil,
            date: date,
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
            fat: "5",
            weightUnits: []
        )
    }

    private static func meal(_ id: String, order: Int) -> WgerMeal {
        WgerMeal(id: id, planID: "active", order: order, time: nil, name: id.capitalized)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
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
    private let mealPages: [Int: WgerPage<WgerMeal>]
    private let ingredientValues: [WgerIngredient]
    private(set) var planOffsets: [Int] = []
    private(set) var entryOffsets: [Int] = []
    private(set) var requestedPlanIDs: [String] = []
    private(set) var requestedIntervals: [DateInterval] = []
    private(set) var ingredientRequests: [[Int]] = []
    private(set) var mealOffsets: [Int] = []
    private(set) var requestedMealPlanIDs: [String] = []
    private(set) var deletedEntryIDs: [String] = []
    private(set) var entryUpdates: [DiaryEntryUpdate] = []
    private(set) var searchQueries: [String] = []
    private(set) var createdEntries: [NutritionDiaryEntryCreate] = []

    init(
        planPages: [Int: WgerPage<WgerNutritionPlan>],
        entryPages: [Int: WgerPage<WgerNutritionDiaryEntry>] = [:],
        mealPages: [Int: WgerPage<WgerMeal>] = [:],
        ingredientValues: [WgerIngredient] = []
    ) {
        self.planPages = planPages
        self.entryPages = entryPages
        self.mealPages = mealPages
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

    func meals(
        instance: InstanceURL,
        session: AuthenticationSession,
        planID: String,
        limit: Int,
        offset: Int
    ) -> WgerPage<WgerMeal> {
        mealOffsets.append(offset)
        requestedMealPlanIDs.append(planID)
        return mealPages[offset] ?? WgerPage(values: [], hasNextPage: false)
    }

    func searchIngredients(
        instance: InstanceURL,
        session: AuthenticationSession,
        query: String,
        limit: Int
    ) -> [WgerIngredient] {
        searchQueries.append(query)
        return ingredientValues
    }

    func createEntry(
        instance: InstanceURL,
        session: AuthenticationSession,
        entry: NutritionDiaryEntryCreate
    ) {
        createdEntries.append(entry)
    }

    func deleteEntry(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) {
        deletedEntryIDs.append(id)
    }

    func updateEntry(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) {
        entryUpdates.append(
            DiaryEntryUpdate(
                id: id,
                amount: amount,
                weightUnitID: weightUnitID,
                date: date,
                mealID: mealID
            )
        )
    }
}

private nonisolated struct DiaryEntryUpdate: Equatable, Sendable {
    let id: String
    let amount: String
    let weightUnitID: Int?
    let date: Date
    let mealID: String?
}
