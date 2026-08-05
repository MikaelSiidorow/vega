import Foundation
import Testing

@testable import Vega

nonisolated struct DailyDiaryTests {
    @Test
    func groupsMealsAndCalculatesExactDecimalTotals() throws {
        let date = Date(timeIntervalSince1970: 1_754_392_800)
        let payload = DailyDiaryPayload(
            plan: Self.plan,
            entries: [
                Self.entry("oats", mealID: "breakfast", ingredientID: 1, amount: "150.5"),
                Self.entry(
                    "toast",
                    mealID: "breakfast",
                    ingredientID: 2,
                    weightUnitID: 20,
                    amount: "2"
                ),
                Self.entry("snack", mealID: nil, ingredientID: 1, amount: "10"),
            ],
            ingredients: [
                1: Self.ingredient(
                    id: 1,
                    energy: 100,
                    protein: "10",
                    carbohydrates: "20",
                    fat: "5"
                ),
                2: Self.ingredient(
                    id: 2,
                    energy: 200,
                    protein: "12.5",
                    carbohydrates: "40",
                    fat: "2.5",
                    units: [WgerIngredientWeightUnit(id: 20, grams: 30, name: "slice")]
                ),
            ]
        )

        let diary = try DailyDiary.build(from: payload, date: date)

        #expect(diary.date == date)
        #expect(diary.planID == "plan")
        #expect(diary.meals.map { $0.id } == [DiaryMeal.ID.meal("breakfast"), .unassigned])
        #expect(diary.meals.map { $0.items.count } == [2, 1])
        #expect(diary.meals[0].items[1].loggedAmount == Decimal(2))
        #expect(diary.meals[0].items[1].unitName == "slice")
        #expect(diary.meals[0].items[1].grams == Decimal(60))
        #expect(diary.totals.energy == Decimal(string: "280.5"))
        #expect(diary.totals.protein == Decimal(string: "23.55"))
        #expect(diary.totals.carbohydrates == Decimal(string: "56.1"))
        #expect(diary.totals.fat == Decimal(string: "9.525"))
    }

    @Test
    func preservesAnEntryWhenIngredientHydrationIsMissing() throws {
        let payload = DailyDiaryPayload(
            plan: Self.plan,
            entries: [Self.entry(nil, mealID: nil, ingredientID: 404, amount: "25")],
            ingredients: [:]
        )

        let diary = try DailyDiary.build(from: payload, date: Date())
        guard let item = diary.meals.first?.items.first else {
            Issue.record("Expected one diary item")
            return
        }

        #expect(item.id == "plan-0")
        #expect(item.name == "Ingredient 404")
        #expect(item.grams == 25)
        #expect(item.nutrition == .zero)
    }

    @Test
    func rejectsMalformedServerDecimals() {
        let payload = DailyDiaryPayload(
            plan: Self.plan,
            entries: [
                Self.entry("bad", mealID: nil, ingredientID: 1, amount: "not-a-number")
            ],
            ingredients: [1: Self.ingredient(id: 1)]
        )

        #expect(throws: DiaryDomainError.invalidDecimal(field: "amount", value: "not-a-number")) {
            try DailyDiary.build(from: payload, date: Date())
        }
    }

    private static let plan = WgerNutritionPlan(
        id: "plan",
        creationDate: "2026-01-01",
        start: "2026-01-01",
        end: nil,
        description: nil
    )

    private static func entry(
        _ id: String?,
        mealID: String?,
        ingredientID: Int,
        weightUnitID: Int? = nil,
        amount: String
    ) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: "plan",
            mealID: mealID,
            ingredientID: ingredientID,
            weightUnitID: weightUnitID,
            date: nil,
            amount: amount
        )
    }

    private static func ingredient(
        id: Int,
        energy: Int = 100,
        protein: String = "10",
        carbohydrates: String = "20",
        fat: String = "5",
        units: [WgerIngredientWeightUnit] = []
    ) -> WgerIngredient {
        WgerIngredient(
            id: id,
            name: "Ingredient \(id)",
            brand: nil,
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            weightUnits: units
        )
    }
}
