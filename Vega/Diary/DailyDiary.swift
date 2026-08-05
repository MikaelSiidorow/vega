import Foundation

nonisolated struct DailyDiary: Equatable, Sendable {
    let date: Date
    let planID: String?
    let meals: [DiaryMeal]
    let totals: NutritionTotals

    static func build(from payload: DailyDiaryPayload, date: Date) throws -> DailyDiary {
        var mealOrder: [DiaryMeal.ID] = []
        var itemsByMeal: [DiaryMeal.ID: [DiaryItem]] = [:]

        for (index, entry) in payload.entries.enumerated() {
            let mealID = entry.mealID.map(DiaryMeal.ID.meal) ?? .unassigned
            if itemsByMeal[mealID] == nil {
                mealOrder.append(mealID)
                itemsByMeal[mealID] = []
            }
            let item = try DiaryItem.build(
                from: entry,
                ingredient: payload.ingredients[entry.ingredientID],
                fallbackID: "\(entry.planID)-\(index)"
            )
            itemsByMeal[mealID, default: []].append(item)
        }

        let meals = mealOrder.map { id in
            DiaryMeal(id: id, items: itemsByMeal[id, default: []])
        }
        return DailyDiary(
            date: date,
            planID: payload.plan?.id,
            meals: meals,
            totals: meals.flatMap(\.items).reduce(.zero) { $0 + $1.nutrition }
        )
    }
}

nonisolated struct DiaryMeal: Equatable, Identifiable, Sendable {
    enum ID: Equatable, Hashable, Sendable {
        case meal(String)
        case unassigned
    }

    let id: ID
    let items: [DiaryItem]
}

nonisolated struct DiaryItem: Equatable, Identifiable, Sendable {
    let id: String
    let ingredientID: Int
    let name: String
    let brand: String?
    let loggedAmount: Decimal
    let unitName: String?
    let grams: Decimal
    let date: Date?
    let nutrition: NutritionTotals

    fileprivate static func build(
        from entry: WgerNutritionDiaryEntry,
        ingredient: WgerIngredient?,
        fallbackID: String
    ) throws -> DiaryItem {
        let amount = try decimal(entry.amount, field: "amount")
        let unit = ingredient?.weightUnits.first { $0.id == entry.weightUnitID }
        let grams = amount * Decimal(unit?.grams ?? 1)

        let nutrition: NutritionTotals
        if let ingredient {
            nutrition = NutritionTotals(
                energy: Decimal(ingredient.energy) * grams / 100,
                protein: try decimal(ingredient.protein, field: "protein") * grams / 100,
                carbohydrates: try decimal(ingredient.carbohydrates, field: "carbohydrates")
                    * grams / 100,
                fat: try decimal(ingredient.fat, field: "fat") * grams / 100
            )
        } else {
            nutrition = .zero
        }

        return DiaryItem(
            id: entry.id ?? fallbackID,
            ingredientID: entry.ingredientID,
            name: ingredient?.name ?? "Ingredient \(entry.ingredientID)",
            brand: ingredient?.brand,
            loggedAmount: amount,
            unitName: unit?.name,
            grams: grams,
            date: entry.date,
            nutrition: nutrition
        )
    }

    private static func decimal(_ value: String, field: String) throws -> Decimal {
        guard let value = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw DiaryDomainError.invalidDecimal(field: field, value: value)
        }
        return value
    }
}

nonisolated struct NutritionTotals: Equatable, Sendable {
    let energy: Decimal
    let protein: Decimal
    let carbohydrates: Decimal
    let fat: Decimal

    static let zero = NutritionTotals(energy: 0, protein: 0, carbohydrates: 0, fat: 0)

    static func + (lhs: NutritionTotals, rhs: NutritionTotals) -> NutritionTotals {
        NutritionTotals(
            energy: lhs.energy + rhs.energy,
            protein: lhs.protein + rhs.protein,
            carbohydrates: lhs.carbohydrates + rhs.carbohydrates,
            fat: lhs.fat + rhs.fat
        )
    }
}

nonisolated enum DiaryDomainError: Error, Equatable, Sendable {
    case invalidDecimal(field: String, value: String)
}
