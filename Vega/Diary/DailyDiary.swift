import Foundation

nonisolated struct DailyDiary: Equatable, Sendable {
    let date: Date
    let planID: String?
    let sections: [DiarySection]
    let totals: NutritionTotals

    static func build(from payload: DailyDiaryPayload, date: Date) throws -> DailyDiary {
        var sectionOrder: [DiarySection.ID] = []
        var itemsBySection: [DiarySection.ID: [DiaryItem]] = [:]
        var currentTimeGroup: DiarySection.ID?
        var lastUnassignedDate: Date?

        for (index, entry) in ordered(payload.entries) {
            let sectionID: DiarySection.ID
            if let mealID = entry.mealID {
                sectionID = .meal(mealID)
            } else if let entryDate = entry.date {
                if let lastUnassignedDate, let currentTimeGroup,
                    entryDate.timeIntervalSince(lastUnassignedDate) < 60 * 60
                {
                    sectionID = currentTimeGroup
                } else {
                    sectionID = .timeGroup(entry.id ?? "\(entry.planID)-\(index)")
                    currentTimeGroup = sectionID
                }
                lastUnassignedDate = entryDate
            } else {
                sectionID = .unscheduled
            }

            if itemsBySection[sectionID] == nil {
                sectionOrder.append(sectionID)
                itemsBySection[sectionID] = []
            }
            let item = try DiaryItem.build(
                from: entry,
                ingredient: payload.ingredients[entry.ingredientID],
                fallbackID: "\(entry.planID)-\(index)"
            )
            itemsBySection[sectionID, default: []].append(item)
        }

        let sections = sectionOrder.map { id in
            DiarySection(id: id, items: itemsBySection[id, default: []])
        }
        return DailyDiary(
            date: date,
            planID: payload.plan?.id,
            sections: sections,
            totals: sections.flatMap(\.items).reduce(.zero) { $0 + $1.nutrition }
        )
    }

    private static func ordered(
        _ entries: [WgerNutritionDiaryEntry]
    ) -> [(offset: Int, element: WgerNutritionDiaryEntry)] {
        entries.enumerated().sorted { lhs, rhs in
            switch (lhs.element.date, rhs.element.date) {
            case (let lhsDate?, let rhsDate?):
                lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate < rhsDate
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                lhs.offset < rhs.offset
            }
        }
    }
}

nonisolated struct DiarySection: Equatable, Identifiable, Sendable {
    enum ID: Equatable, Hashable, Sendable {
        case meal(String)
        case timeGroup(String)
        case unscheduled
    }

    let id: ID
    let items: [DiaryItem]
}

nonisolated struct DiaryItem: Equatable, Identifiable, Sendable {
    let id: String
    let remoteID: String?
    let ingredientID: Int
    let name: String
    let brand: String?
    let loggedAmount: Decimal
    let weightUnitID: Int?
    let unitName: String?
    let weightUnits: [WgerIngredientWeightUnit]
    let grams: Decimal
    let date: Date?
    let nutritionPer100Grams: NutritionTotals
    let nutrition: NutritionTotals

    fileprivate static func build(
        from entry: WgerNutritionDiaryEntry,
        ingredient: WgerIngredient?,
        fallbackID: String
    ) throws -> DiaryItem {
        let amount = try decimal(entry.amount, field: "amount")
        let unit = ingredient?.weightUnits.first { $0.id == entry.weightUnitID }
        let grams = amount * Decimal(unit?.grams ?? 1)

        let nutritionPer100Grams: NutritionTotals
        if let ingredient {
            nutritionPer100Grams = NutritionTotals(
                energy: Decimal(ingredient.energy),
                protein: try decimal(ingredient.protein, field: "protein"),
                carbohydrates: try decimal(ingredient.carbohydrates, field: "carbohydrates"),
                fat: try decimal(ingredient.fat, field: "fat")
            )
        } else {
            nutritionPer100Grams = .zero
        }
        let nutrition = nutritionPer100Grams.scaled(toGrams: grams)

        return DiaryItem(
            id: entry.id ?? fallbackID,
            remoteID: entry.id,
            ingredientID: entry.ingredientID,
            name: ingredient?.name ?? "Ingredient \(entry.ingredientID)",
            brand: ingredient?.brand,
            loggedAmount: amount,
            weightUnitID: entry.weightUnitID,
            unitName: unit?.name,
            weightUnits: ingredient?.weightUnits ?? [],
            grams: grams,
            date: entry.date,
            nutritionPer100Grams: nutritionPer100Grams,
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

    func scaled(toGrams grams: Decimal) -> NutritionTotals {
        NutritionTotals(
            energy: energy * grams / 100,
            protein: protein * grams / 100,
            carbohydrates: carbohydrates * grams / 100,
            fat: fat * grams / 100
        )
    }
}

nonisolated enum DiaryDomainError: Error, Equatable, Sendable {
    case invalidDecimal(field: String, value: String)
}
