import Foundation
import Testing

@testable import Vega

nonisolated struct RecentFoodsTests {
    @Test
    func deduplicatesEquivalentAmountsButPreservesUnits() throws {
        let ingredient = Self.ingredient(
            id: 1,
            units: [WgerIngredientWeightUnit(id: 11, grams: 40, name: "slice")]
        )
        let payload = RecentDiaryPayload(
            entries: [
                Self.entry(ingredientID: 1, amount: "2.0", unitID: 11, at: "2026-08-01T08:00:00Z"),
                Self.entry(ingredientID: 1, amount: "2", unitID: 11, at: "2026-08-02T08:00:00Z"),
                Self.entry(ingredientID: 1, amount: "2", unitID: nil, at: "2026-08-03T08:00:00Z"),
            ],
            ingredients: [1: ingredient]
        )

        let result = RecentFoodRanker.suggestions(
            from: payload,
            referenceDate: try Self.date("2026-08-04T16:00:00Z"),
            includesTimeContext: false,
            calendar: Self.utcCalendar
        )

        #expect(result.aroundThisTime.isEmpty)
        #expect(result.recent.map(\.weightUnitID) == [nil, 11])
        #expect(result.recent.map(\.amount) == ["2", "2"])
        #expect(result.recent.map(\.occurrenceCount) == [1, 2])
    }

    @Test
    func ranksFrequentlyLoggedPortionsNearTheReferenceTimeFirst() throws {
        let oats = Self.ingredient(id: 1)
        let tofu = Self.ingredient(id: 2)
        let payload = RecentDiaryPayload(
            entries: [
                Self.entry(ingredientID: 1, amount: "80", at: "2026-08-01T07:30:00Z"),
                Self.entry(ingredientID: 1, amount: "80", at: "2026-08-02T08:15:00Z"),
                Self.entry(ingredientID: 1, amount: "80", at: "2026-08-03T12:00:00Z"),
                Self.entry(ingredientID: 2, amount: "200", at: "2026-08-03T08:30:00Z"),
                Self.entry(ingredientID: 2, amount: "200", at: "2026-08-04T08:45:00Z"),
                Self.entry(ingredientID: 2, amount: "200", at: "2026-08-05T07:45:00Z"),
                Self.entry(ingredientID: 2, amount: "100", at: "2026-08-05T18:00:00Z"),
            ],
            ingredients: [1: oats, 2: tofu]
        )

        let result = RecentFoodRanker.suggestions(
            from: payload,
            referenceDate: try Self.date("2026-08-06T08:00:00Z"),
            includesTimeContext: true,
            calendar: Self.utcCalendar
        )

        #expect(result.aroundThisTime.map(\.ingredient.id) == [2, 1])
        #expect(result.aroundThisTime.map(\.matchingTimeCount) == [3, 2])
        #expect(result.recent.map(\.amount) == ["100"])
    }

    @Test
    func omitsTimeRankingForPastDatesAndOrdersByLastUse() throws {
        let payload = RecentDiaryPayload(
            entries: [
                Self.entry(ingredientID: 1, amount: "80", at: "2026-08-01T08:00:00Z"),
                Self.entry(ingredientID: 1, amount: "80", at: "2026-08-02T08:00:00Z"),
                Self.entry(ingredientID: 2, amount: "100", at: "2026-08-03T18:00:00Z"),
            ],
            ingredients: [1: Self.ingredient(id: 1), 2: Self.ingredient(id: 2)]
        )

        let result = RecentFoodRanker.suggestions(
            from: payload,
            referenceDate: try Self.date("2026-08-04T08:00:00Z"),
            includesTimeContext: false,
            calendar: Self.utcCalendar
        )

        #expect(result.aroundThisTime.isEmpty)
        #expect(result.recent.map(\.ingredient.id) == [2, 1])
    }

    @Test
    func capsContextualSuggestionsAtSix() throws {
        let ingredients = Dictionary(
            uniqueKeysWithValues: (1...7).map { ($0, Self.ingredient(id: $0)) }
        )
        let entries = (1...7).flatMap { ingredientID in
            [
                Self.entry(
                    ingredientID: ingredientID,
                    amount: "1",
                    at: "2026-08-01T08:00:00Z"
                ),
                Self.entry(
                    ingredientID: ingredientID,
                    amount: "1",
                    at: "2026-08-02T08:00:00Z"
                ),
            ]
        }
        let result = RecentFoodRanker.suggestions(
            from: RecentDiaryPayload(entries: entries, ingredients: ingredients),
            referenceDate: try Self.date("2026-08-03T08:00:00Z"),
            includesTimeContext: true,
            calendar: Self.utcCalendar
        )

        #expect(result.aroundThisTime.count == 6)
        #expect(result.recent.count == 1)
    }

    @Test
    func ignoresIncompleteHistoryAndReturnsAnEmptyState() throws {
        let result = RecentFoodRanker.suggestions(
            from: RecentDiaryPayload(
                entries: [
                    WgerNutritionDiaryEntry(
                        id: "missing-date",
                        planID: "active",
                        mealID: nil,
                        ingredientID: 1,
                        weightUnitID: nil,
                        date: nil,
                        amount: "100"
                    ),
                    Self.entry(ingredientID: 2, amount: "invalid", at: "2026-08-01T08:00:00Z"),
                ],
                ingredients: [1: Self.ingredient(id: 1)]
            ),
            referenceDate: try Self.date("2026-08-03T08:00:00Z"),
            includesTimeContext: true,
            calendar: Self.utcCalendar
        )

        #expect(result == .empty)
    }

    private static func entry(
        ingredientID: Int,
        amount: String,
        unitID: Int? = nil,
        at date: String
    ) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: "\(ingredientID)-\(amount)-\(date)",
            planID: "active",
            mealID: nil,
            ingredientID: ingredientID,
            weightUnitID: unitID,
            date: ISO8601DateFormatter().date(from: date),
            amount: amount
        )
    }

    private static func ingredient(
        id: Int,
        units: [WgerIngredientWeightUnit] = []
    ) -> WgerIngredient {
        WgerIngredient(
            id: id,
            name: "Ingredient \(id)",
            brand: nil,
            energy: 100,
            protein: "10",
            carbohydrates: "20",
            fat: "5",
            weightUnits: units
        )
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
