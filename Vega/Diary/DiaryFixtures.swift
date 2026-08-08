import Foundation

nonisolated enum DiaryFixtureMode: Equatable, Sendable {
    case basicLogging
    case plannedMeals
}

actor FixtureDailyDiaryStore: DailyDiaryFetching, DiaryEntryDeleting, DiaryEntryUpdating {
    let mode: DiaryFixtureMode
    private var deletedEntryIDs: Set<String> = []
    private var amountOverrides: [String: (amount: String, weightUnitID: Int?)] = [:]
    private var scheduleOverrides: [String: (date: Date, mealID: String?)] = [:]

    init(mode: DiaryFixtureMode) {
        self.mode = mode
    }

    func diary(for date: Date, calendar: Calendar) -> DailyDiaryPayload {
        DailyDiaryPayload(
            plan: WgerNutritionPlan(
                id: "fixture-plan",
                creationDate: "2026-08-01",
                start: "2026-08-01",
                end: nil,
                description: "Balanced nutrition"
            ),
            entries: entries(for: date, calendar: calendar)
                .filter {
                    guard let id = $0.id else { return true }
                    return !deletedEntryIDs.contains(id)
                }
                .map { entry in
                    guard let id = entry.id, let override = amountOverrides[id] else {
                        return entry
                    }
                    let schedule = scheduleOverrides[id]
                    let mealID = if let schedule { schedule.mealID } else { entry.mealID }
                    return WgerNutritionDiaryEntry(
                        id: entry.id,
                        planID: entry.planID,
                        mealID: mealID,
                        ingredientID: entry.ingredientID,
                        weightUnitID: override.weightUnitID,
                        date: schedule?.date ?? entry.date,
                        amount: override.amount
                    )
                },
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
            ],
            meals: mode == .plannedMeals
                ? [
                    WgerMeal(
                        id: "breakfast",
                        planID: "fixture-plan",
                        order: 1,
                        time: "08:00:00",
                        name: "Breakfast"
                    ),
                    WgerMeal(
                        id: "dinner",
                        planID: "fixture-plan",
                        order: 2,
                        time: "18:00:00",
                        name: "Dinner"
                    ),
                ] : []
        )
    }

    func deleteDiaryEntry(id: String) {
        deletedEntryIDs.insert(id)
    }

    func updateDiaryEntry(
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) {
        amountOverrides[id] = (amount, weightUnitID)
        scheduleOverrides[id] = (date, mealID)
    }

    private func entries(for date: Date, calendar: Calendar) -> [WgerNutritionDiaryEntry] {
        let usesMeals = mode == .plannedMeals
        return [
            entry(
                id: "oats",
                mealID: usesMeals ? "breakfast" : nil,
                ingredientID: 1,
                amount: "80",
                date: timestamp(atHour: 8, minute: 5, on: date, calendar: calendar)
            ),
            entry(
                id: "blueberries",
                mealID: usesMeals ? "breakfast" : nil,
                ingredientID: 2,
                amount: "120",
                date: timestamp(atHour: 8, minute: 20, on: date, calendar: calendar)
            ),
            entry(
                id: "tofu",
                mealID: usesMeals ? "dinner" : nil,
                ingredientID: 3,
                amount: "2",
                weightUnitID: 31,
                date: timestamp(atHour: 12, minute: 30, on: date, calendar: calendar)
            ),
        ]
    }

    private func entry(
        id: String,
        mealID: String?,
        ingredientID: Int,
        amount: String,
        weightUnitID: Int? = nil,
        date: Date
    ) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: "fixture-plan",
            mealID: mealID,
            ingredientID: ingredientID,
            weightUnitID: weightUnitID,
            date: date,
            amount: amount
        )
    }

    private func timestamp(
        atHour hour: Int,
        minute: Int,
        on date: Date,
        calendar: Calendar
    ) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
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
