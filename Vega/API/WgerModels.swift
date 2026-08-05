import Foundation
import WgerAPI

nonisolated struct WgerNutritionPlan: Equatable, Sendable {
    let id: String
    let creationDate: String
    let start: String?
    let end: String?
    let description: String?
}

nonisolated struct WgerNutritionDiaryEntry: Equatable, Sendable {
    let id: String?
    let planID: String
    let mealID: String?
    let ingredientID: Int
    let weightUnitID: Int?
    let date: Date?
    let amount: String
}

nonisolated struct WgerIngredient: Equatable, Sendable {
    let id: Int
    let name: String
    let brand: String?
    let energy: Int
    let protein: String
    let carbohydrates: String
    let fat: String
}

nonisolated struct WgerPage<Value: Sendable>: Sendable {
    let values: [Value]
    let hasNextPage: Bool
}

extension Components.Schemas.NutritionPlan {
    nonisolated var vegaValue: WgerNutritionPlan? {
        guard let id else { return nil }
        return WgerNutritionPlan(
            id: id,
            creationDate: creationDate,
            start: start,
            end: end,
            description: description
        )
    }
}

extension Components.Schemas.LogItem {
    nonisolated var vegaValue: WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: id,
            planID: plan,
            mealID: meal,
            ingredientID: ingredient,
            weightUnitID: weightUnit,
            date: datetime,
            amount: amount
        )
    }
}

extension Components.Schemas.IngredientInfo {
    nonisolated var vegaValue: WgerIngredient {
        WgerIngredient(
            id: id,
            name: name,
            brand: brand,
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat
        )
    }
}
