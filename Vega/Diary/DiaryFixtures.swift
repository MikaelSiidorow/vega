import Foundation

nonisolated enum DiaryFixtureMode: Equatable, Sendable {
    case basicLogging
    case plannedMeals
}

actor FixtureDailyDiaryStore: DailyDiaryFetching, DiaryEntryDeleting, DiaryEntryUpdating,
    IngredientSearching, DiaryEntryCreating, RecentDiaryFetching
{
    let mode: DiaryFixtureMode
    private var deletedEntryIDs: Set<String> = []
    private var amountOverrides: [String: (amount: String, weightUnitID: Int?)] = [:]
    private var scheduleOverrides: [String: (date: Date, mealID: String?)] = [:]
    private var createdEntries: [WgerNutritionDiaryEntry] = []

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
            entries: (entries(for: date, calendar: calendar) + createdEntries)
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
            ingredients: Dictionary(uniqueKeysWithValues: ingredientCatalog.map { ($0.id, $0) }),
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

    func searchIngredients(query: String) -> [WgerIngredient] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count >= 2 else { return [] }
        if normalized == "5901234123457" {
            return ingredientCatalog.filter { $0.id == 4 }
        }
        return ingredientCatalog.filter {
            $0.name.lowercased().contains(normalized)
                || $0.brand?.lowercased().contains(normalized) == true
        }
    }

    func recentDiary(
        planID: String,
        before date: Date,
        calendar: Calendar
    ) -> RecentDiaryPayload {
        let history = [
            historicalEntry(
                id: "recent-tofu-1",
                ingredientID: 3,
                amount: "2",
                weightUnitID: 31,
                daysAgo: 1,
                hour: 12,
                minute: 10,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-tofu-2",
                ingredientID: 3,
                amount: "2",
                weightUnitID: 31,
                daysAgo: 2,
                hour: 11,
                minute: 45,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-tofu-3",
                ingredientID: 3,
                amount: "2",
                weightUnitID: 31,
                daysAgo: 5,
                hour: 13,
                minute: 0,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-banana-1",
                ingredientID: 4,
                amount: "1",
                weightUnitID: 41,
                daysAgo: 1,
                hour: 12,
                minute: 30,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-banana-2",
                ingredientID: 4,
                amount: "1",
                weightUnitID: 41,
                daysAgo: 3,
                hour: 12,
                minute: 20,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-oats-1",
                ingredientID: 1,
                amount: "80",
                weightUnitID: nil,
                daysAgo: 1,
                hour: 8,
                minute: 0,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-oats-2",
                ingredientID: 1,
                amount: "80",
                weightUnitID: nil,
                daysAgo: 2,
                hour: 8,
                minute: 5,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-tofu-grams",
                ingredientID: 3,
                amount: "150",
                weightUnitID: nil,
                daysAgo: 2,
                hour: 18,
                minute: 0,
                before: date,
                calendar: calendar
            ),
            historicalEntry(
                id: "recent-yogurt",
                ingredientID: 5,
                amount: "200",
                weightUnitID: nil,
                daysAgo: 4,
                hour: 15,
                minute: 0,
                before: date,
                calendar: calendar
            ),
        ]
        return RecentDiaryPayload(
            entries: history,
            ingredients: Dictionary(uniqueKeysWithValues: ingredientCatalog.map { ($0.id, $0) })
        )
    }

    func createDiaryEntry(
        planID: String,
        ingredientID: Int,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) {
        createdEntries.append(
            WgerNutritionDiaryEntry(
                id: "created-\(createdEntries.count + 1)",
                planID: planID,
                mealID: mealID,
                ingredientID: ingredientID,
                weightUnitID: weightUnitID,
                date: date,
                amount: amount
            )
        )
    }

    private var ingredientCatalog: [WgerIngredient] {
        [
            ingredient(
                id: 1,
                name: "Rolled oats",
                brand: "Elovena",
                energy: 370,
                protein: "14",
                carbohydrates: "56",
                fat: "7"
            ),
            ingredient(
                id: 2,
                name: "Blueberries",
                brand: nil,
                energy: 44,
                protein: "0.7",
                carbohydrates: "8.4",
                fat: "0.6"
            ),
            ingredient(
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
            ingredient(
                id: 4,
                name: "Banana",
                brand: nil,
                energy: 89,
                protein: "1.1",
                carbohydrates: "22.8",
                fat: "0.3",
                weightUnits: [
                    WgerIngredientWeightUnit(id: 41, grams: 118, name: "medium banana")
                ]
            ),
            ingredient(
                id: 5,
                name: "Greek yogurt",
                brand: "Arla",
                energy: 73,
                protein: "9.2",
                carbohydrates: "3.8",
                fat: "2.2"
            ),
        ]
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

    private func historicalEntry(
        id: String,
        ingredientID: Int,
        amount: String,
        weightUnitID: Int?,
        daysAgo: Int,
        hour: Int,
        minute: Int,
        before date: Date,
        calendar: Calendar
    ) -> WgerNutritionDiaryEntry {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: date) ?? date
        return entry(
            id: id,
            mealID: nil,
            ingredientID: ingredientID,
            amount: amount,
            weightUnitID: weightUnitID,
            date: timestamp(atHour: hour, minute: minute, on: day, calendar: calendar)
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
