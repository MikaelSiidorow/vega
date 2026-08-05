import Foundation

nonisolated struct FixtureDailyDiaryFetcher: DailyDiaryFetching {
    func diary(for date: Date, calendar: Calendar) -> DailyDiaryPayload {
        DailyDiaryPayload(
            plan: WgerNutritionPlan(
                id: "fixture-plan",
                creationDate: "2026-08-01",
                start: "2026-08-01",
                end: nil,
                description: "Balanced nutrition"
            ),
            entries: [
                entry(
                    id: "oats",
                    mealID: "breakfast",
                    ingredientID: 1,
                    amount: "80"
                ),
                entry(
                    id: "blueberries",
                    mealID: "breakfast",
                    ingredientID: 2,
                    amount: "120"
                ),
                entry(
                    id: "tofu",
                    mealID: "dinner",
                    ingredientID: 3,
                    amount: "2",
                    weightUnitID: 31
                ),
            ],
            ingredients: [
                1: ingredient(
                    id: 1,
                    name: "Rolled oats",
                    brand: "Elovena",
                    energy: 370,
                    protein: "14",
                    carbohydrates: "56",
                    fat: "7"
                ),
                2: ingredient(
                    id: 2,
                    name: "Blueberries",
                    brand: nil,
                    energy: 44,
                    protein: "0.7",
                    carbohydrates: "8.4",
                    fat: "0.6"
                ),
                3: ingredient(
                    id: 3,
                    name: "Smoked tofu",
                    brand: "Jalotofu",
                    energy: 160,
                    protein: "17",
                    carbohydrates: "1.5",
                    fat: "9",
                    weightUnits: [
                        WgerIngredientWeightUnit(id: 31, grams: 100, name: "portion")
                    ]
                ),
            ]
        )
    }

    private func entry(
        id: String,
        mealID: String,
        ingredientID: Int,
        amount: String,
        weightUnitID: Int? = nil
    ) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: "fixture-plan",
            mealID: mealID,
            ingredientID: ingredientID,
            weightUnitID: weightUnitID,
            date: nil,
            amount: amount
        )
    }

    private func ingredient(
        id: Int,
        name: String,
        brand: String?,
        energy: Int,
        protein: String,
        carbohydrates: String,
        fat: String,
        weightUnits: [WgerIngredientWeightUnit] = []
    ) -> WgerIngredient {
        WgerIngredient(
            id: id,
            name: name,
            brand: brand,
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            weightUnits: weightUnits
        )
    }
}
