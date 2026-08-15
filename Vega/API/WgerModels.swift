import Foundation
import WgerAPI

nonisolated struct WgerNutritionPlan: Equatable, Sendable {
    let id: String
    let creationDate: String
    let start: String?
    let end: String?
    let description: String?
    let goalEnergy: Int?
    let goalProtein: Int?
    let goalCarbohydrates: Int?
    let goalFat: Int?

    init(
        id: String,
        creationDate: String,
        start: String?,
        end: String?,
        description: String?,
        goalEnergy: Int? = nil,
        goalProtein: Int? = nil,
        goalCarbohydrates: Int? = nil,
        goalFat: Int? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.start = start
        self.end = end
        self.description = description
        self.goalEnergy = goalEnergy
        self.goalProtein = goalProtein
        self.goalCarbohydrates = goalCarbohydrates
        self.goalFat = goalFat
    }
}

nonisolated struct WgerNutritionalValues: Equatable, Sendable {
    let energy: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
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

nonisolated struct WgerMeal: Equatable, Sendable {
    let id: String
    let planID: String
    let order: Int
    let time: String?
    let name: String?
}

nonisolated struct WgerIngredient: Equatable, Sendable {
    let id: Int
    let name: String
    let brand: String?
    let energy: Int
    let protein: String
    let carbohydrates: String
    let fat: String
    let weightUnits: [WgerIngredientWeightUnit]
}

nonisolated struct WgerIngredientWeightUnit: Equatable, Sendable {
    let id: Int
    let grams: Int
    let name: String
}

nonisolated struct WgerWeightEntry: Equatable, Identifiable, Sendable {
    let id: String
    let date: Date
    let weight: Decimal
}

nonisolated enum WgerModelError: Error, Equatable, Sendable {
    case invalidWeight(String)
    case invalidIdentifier(String)
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
            description: description,
            goalEnergy: goalEnergy,
            goalProtein: goalProtein,
            goalCarbohydrates: goalCarbohydrates,
            goalFat: goalFat
        )
    }
}

extension Components.Schemas.NutritionalValues {
    nonisolated var vegaValue: WgerNutritionalValues {
        WgerNutritionalValues(
            energy: energy,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat
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

extension Components.Schemas.Meal {
    nonisolated var vegaValue: WgerMeal? {
        guard let id else { return nil }
        return WgerMeal(id: id, planID: plan, order: order, time: time, name: name)
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
            fat: fat,
            weightUnits: weightUnits.map {
                WgerIngredientWeightUnit(id: $0.id, grams: $0.gram, name: $0.name)
            }
        )
    }
}

extension Components.Schemas.WeightEntry {
    nonisolated var vegaValue: WgerWeightEntry {
        get throws {
            guard let weight = Decimal(string: weight, locale: Locale(identifier: "en_US_POSIX"))
            else {
                throw WgerModelError.invalidWeight(self.weight)
            }
            return WgerWeightEntry(id: String(id), date: date, weight: weight)
        }
    }
}
