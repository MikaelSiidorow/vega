import Foundation
import PowerSync

nonisolated struct PowerSyncNutritionRepository: NutritionDataStore {
    private static let recentHistoryDays = 42
    private static let diaryObservationSQL = """
        SELECT id FROM nutrition_nutritionplan
        UNION ALL SELECT id FROM nutrition_logitem
        UNION ALL SELECT id FROM nutrition_meal
        UNION ALL SELECT id FROM nutrition_mealitem
        UNION ALL SELECT id FROM nutrition_ingredient
        UNION ALL SELECT id FROM nutrition_ingredientweightunit
        """

    private let powerSync: any PowerSyncDatabaseProviding
    private let fallback: any NutritionDataStore
    private let makeID: @Sendable () -> String

    init(
        powerSync: any PowerSyncDatabaseProviding,
        fallback: any NutritionDataStore,
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.powerSync = powerSync
        self.fallback = fallback
        self.makeID = makeID
    }

    func diary(for date: Date, calendar: Calendar) async throws -> DailyDiaryPayload {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.diary(for: date, calendar: calendar)
        }

        let plans = try await Self.plans(in: database)
        if plans.isEmpty, !(await powerSync.status()).hasSynced {
            return try await fallback.diary(for: date, calendar: calendar)
        }
        return try await Self.diary(
            for: date,
            calendar: calendar,
            plans: plans,
            database: database
        )
    }

    func diaryStream(for date: Date, calendar: Calendar) async throws
        -> AsyncThrowingStream<DailyDiaryPayload, Error>
    {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.diaryStream(for: date, calendar: calendar)
        }
        let updates = try database.watch(
            sql: Self.diaryObservationSQL,
            parameters: [],
            mapper: { try $0.getString(index: 0) }
        )
        return AsyncThrowingStream { continuation in
            let observation = Task {
                do {
                    for try await _ in updates {
                        let plans = try await Self.plans(in: database)
                        if plans.isEmpty, !(await powerSync.status()).hasSynced {
                            continuation.yield(
                                try await fallback.diary(for: date, calendar: calendar)
                            )
                        } else {
                            continuation.yield(
                                try await Self.diary(
                                    for: date,
                                    calendar: calendar,
                                    plans: plans,
                                    database: database
                                )
                            )
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in observation.cancel() }
        }
    }

    private static func diary(
        for date: Date,
        calendar: Calendar,
        plans: [WgerNutritionPlan],
        database: any PowerSyncDatabaseProtocol
    ) async throws -> DailyDiaryPayload {
        guard let plan = NutritionPlanSelection.active(in: plans, for: date, calendar: calendar)
        else { return .empty }

        let allEntries = try await Self.entries(planID: plan.id, in: database)
        let entries = allEntries.filter { entry in
            guard let entryDate = entry.date else { return false }
            return calendar.isDate(entryDate, inSameDayAs: date)
        }
        let meals = try await Self.meals(planID: plan.id, in: database)
        let mealItems = try await Self.mealItems(mealIDs: meals.map(\.id), in: database)
        let ingredientIDs = Set(entries.map(\.ingredientID) + mealItems.map(\.ingredientID))
        let ingredients = try await Self.ingredients(ids: ingredientIDs, in: database)

        return DailyDiaryPayload(
            plan: plan,
            entries: entries,
            ingredients: ingredients,
            meals: meals,
            plannedNutrition: Self.plannedNutrition(
                mealItems: mealItems,
                ingredients: ingredients
            )
        )
    }

    func recentDiary(
        planID: String,
        before date: Date,
        calendar: Calendar
    ) async throws -> RecentDiaryPayload {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await fallback.recentDiary(
                planID: planID,
                before: date,
                calendar: calendar
            )
        }
        guard
            let start = calendar.date(
                byAdding: .day,
                value: -Self.recentHistoryDays,
                to: date
            )
        else { return .empty }

        let entries = try await Self.entries(planID: planID, in: database).filter { entry in
            guard let entryDate = entry.date else { return false }
            return entryDate >= start && entryDate < date
        }
        return RecentDiaryPayload(
            entries: entries,
            ingredients: try await Self.ingredients(
                ids: Set(entries.map(\.ingredientID)),
                in: database
            )
        )
    }

    func createDiaryEntry(
        planID: String,
        ingredientID: Int,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.createDiaryEntry(
                planID: planID,
                ingredientID: ingredientID,
                amount: amount,
                weightUnitID: weightUnitID,
                date: date,
                mealID: mealID
            )
            return
        }
        let parameters: [Sendable?] = [
            makeID(),
            planID,
            mealID,
            ingredientID,
            weightUnitID,
            PowerSyncValueCodec.encodeDateTime(date),
            try PowerSyncValueCodec.double(amount, field: "amount"),
            nil,
        ]
        try await database.execute(
            sql: """
                INSERT INTO nutrition_logitem (
                    id, plan_id, meal_id, ingredient_id, weight_unit_id,
                    datetime, amount, comment
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            parameters: parameters
        )
    }

    func updateDiaryEntry(
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.updateDiaryEntry(
                id: id,
                amount: amount,
                weightUnitID: weightUnitID,
                date: date,
                mealID: mealID
            )
            return
        }
        let parameters: [Sendable?] = [
            try PowerSyncValueCodec.double(amount, field: "amount"),
            weightUnitID,
            PowerSyncValueCodec.encodeDateTime(date),
            mealID,
            id,
        ]
        try await database.execute(
            sql: """
                UPDATE nutrition_logitem
                SET amount = ?, weight_unit_id = ?, datetime = ?, meal_id = ?
                WHERE id = ?
                """,
            parameters: parameters
        )
    }

    func deleteDiaryEntry(id: String) async throws {
        let database: any PowerSyncDatabaseProtocol
        do {
            database = try await powerSync.database()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await fallback.deleteDiaryEntry(id: id)
            return
        }
        try await database.execute(
            sql: "DELETE FROM nutrition_logitem WHERE id = ?",
            parameters: [id]
        )
    }

    private static func plans(in database: any PowerSyncDatabaseProtocol) async throws
        -> [WgerNutritionPlan]
    {
        try await database.getAll(
            sql: """
                SELECT id, creation_date, start, end, description,
                       goal_energy, goal_protein, goal_carbohydrates, goal_fat
                FROM nutrition_nutritionplan
                """,
            parameters: []
        ) { cursor in
            WgerNutritionPlan(
                id: try cursor.getString(name: "id"),
                creationDate: try cursor.getString(name: "creation_date"),
                start: try cursor.getStringOptional(name: "start"),
                end: try cursor.getStringOptional(name: "end"),
                description: try cursor.getStringOptional(name: "description"),
                goalEnergy: try cursor.getIntOptional(name: "goal_energy"),
                goalProtein: try cursor.getIntOptional(name: "goal_protein"),
                goalCarbohydrates: try cursor.getIntOptional(name: "goal_carbohydrates"),
                goalFat: try cursor.getIntOptional(name: "goal_fat")
            )
        }
    }

    private static func entries(
        planID: String,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [WgerNutritionDiaryEntry] {
        try await database.getAll(
            sql: """
                SELECT id, plan_id, meal_id, ingredient_id, weight_unit_id, datetime, amount
                FROM nutrition_logitem
                WHERE plan_id = ?
                ORDER BY datetime
                """,
            parameters: [planID]
        ) { cursor in
            let encodedDate = try cursor.getString(name: "datetime")
            let id = try cursor.getString(name: "id")
            guard let date = PowerSyncValueCodec.decodeDateTime(encodedDate) else {
                throw PowerSyncRepositoryError.invalidDate(
                    table: WgerPowerSyncTable.logItem,
                    recordID: id,
                    value: encodedDate
                )
            }
            return WgerNutritionDiaryEntry(
                id: id,
                planID: try cursor.getString(name: "plan_id"),
                mealID: try cursor.getStringOptional(name: "meal_id"),
                ingredientID: try integerID(cursor, name: "ingredient_id"),
                weightUnitID: try optionalIntegerID(cursor, name: "weight_unit_id"),
                date: date,
                amount: PowerSyncValueCodec.decimalString(
                    try cursor.getDouble(name: "amount")
                )
            )
        }
    }

    private static func meals(
        planID: String,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [WgerMeal] {
        try await database.getAll(
            sql: """
                SELECT id, plan_id, "order", time, name
                FROM nutrition_meal
                WHERE plan_id = ?
                ORDER BY "order", time
                """,
            parameters: [planID]
        ) { cursor in
            WgerMeal(
                id: try cursor.getString(name: "id"),
                planID: try cursor.getString(name: "plan_id"),
                order: try cursor.getInt(name: "order"),
                time: try cursor.getStringOptional(name: "time"),
                name: try cursor.getStringOptional(name: "name")
            )
        }
    }

    private static func mealItems(
        mealIDs: [String],
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [LocalMealItem] {
        guard !mealIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: mealIDs.count).joined(separator: ",")
        return try await database.getAll(
            sql: """
                SELECT id, meal_id, ingredient_id, weight_unit_id, amount
                FROM nutrition_mealitem
                WHERE meal_id IN (\(placeholders))
                """,
            parameters: mealIDs
        ) { cursor in
            LocalMealItem(
                id: try cursor.getString(name: "id"),
                ingredientID: try integerID(cursor, name: "ingredient_id"),
                weightUnitID: try optionalIntegerID(cursor, name: "weight_unit_id"),
                amount: Decimal(try cursor.getDouble(name: "amount"))
            )
        }
    }

    private static func ingredients(
        ids: Set<Int>,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [Int: WgerIngredient] {
        guard !ids.isEmpty else { return [:] }
        let sortedIDs = ids.sorted()
        let placeholders = Array(repeating: "?", count: sortedIDs.count).joined(separator: ",")
        let rows = try await database.getAll(
            sql: """
                SELECT id, name, brand, energy, protein, carbohydrates, fat
                FROM nutrition_ingredient
                WHERE CAST(id AS INTEGER) IN (\(placeholders))
                """,
            parameters: sortedIDs
        ) { cursor in
            LocalIngredient(
                id: try integerID(cursor, name: "id"),
                name: try cursor.getString(name: "name"),
                brand: try cursor.getStringOptional(name: "brand"),
                energy: try cursor.getInt(name: "energy"),
                protein: PowerSyncValueCodec.decimalString(
                    try cursor.getDouble(name: "protein")
                ),
                carbohydrates: PowerSyncValueCodec.decimalString(
                    try cursor.getDouble(name: "carbohydrates")
                ),
                fat: PowerSyncValueCodec.decimalString(try cursor.getDouble(name: "fat"))
            )
        }
        let units = try await ingredientUnits(ids: ids, in: database)
        return Dictionary(
            uniqueKeysWithValues: rows.map { row in
                (
                    row.id,
                    WgerIngredient(
                        id: row.id,
                        name: row.name,
                        brand: row.brand,
                        energy: row.energy,
                        protein: row.protein,
                        carbohydrates: row.carbohydrates,
                        fat: row.fat,
                        weightUnits: units[row.id, default: []]
                    )
                )
            }
        )
    }

    private static func ingredientUnits(
        ids: Set<Int>,
        in database: any PowerSyncDatabaseProtocol
    ) async throws -> [Int: [WgerIngredientWeightUnit]] {
        let sortedIDs = ids.sorted()
        let placeholders = Array(repeating: "?", count: sortedIDs.count).joined(separator: ",")
        let rows = try await database.getAll(
            sql: """
                SELECT id, ingredient_id, gram, name
                FROM nutrition_ingredientweightunit
                WHERE ingredient_id IN (\(placeholders))
                ORDER BY gram, name
                """,
            parameters: sortedIDs
        ) { cursor in
            LocalIngredientUnit(
                ingredientID: try cursor.getInt(name: "ingredient_id"),
                value: WgerIngredientWeightUnit(
                    id: try integerID(cursor, name: "id"),
                    grams: try cursor.getInt(name: "gram"),
                    name: try cursor.getString(name: "name")
                )
            )
        }
        return Dictionary(grouping: rows, by: \.ingredientID).mapValues { $0.map(\.value) }
    }

    private static func plannedNutrition(
        mealItems: [LocalMealItem],
        ingredients: [Int: WgerIngredient]
    ) -> PlannedNutritionState {
        guard !mealItems.isEmpty else { return .unavailable }
        var totals = NutritionTotals.zero
        for item in mealItems {
            guard let ingredient = ingredients[item.ingredientID] else { return .unavailable }
            let unit: WgerIngredientWeightUnit?
            if let weightUnitID = item.weightUnitID {
                guard
                    let resolved = ingredient.weightUnits.first(where: { $0.id == weightUnitID })
                else { return .unavailable }
                unit = resolved
            } else {
                unit = nil
            }
            guard
                let protein = Decimal(
                    string: ingredient.protein,
                    locale: Locale(identifier: "en_US_POSIX")
                ),
                let carbohydrates = Decimal(
                    string: ingredient.carbohydrates,
                    locale: Locale(identifier: "en_US_POSIX")
                ),
                let fat = Decimal(
                    string: ingredient.fat,
                    locale: Locale(identifier: "en_US_POSIX")
                )
            else { return .unavailable }
            let grams = item.amount * Decimal(unit?.grams ?? 1)
            totals =
                totals
                + NutritionTotals(
                    energy: Decimal(ingredient.energy),
                    protein: protein,
                    carbohydrates: carbohydrates,
                    fat: fat
                ).scaled(toGrams: grams)
        }
        return .available(
            WgerNutritionalValues(
                energy: NSDecimalNumber(decimal: totals.energy).doubleValue,
                protein: NSDecimalNumber(decimal: totals.protein).doubleValue,
                carbohydrates: NSDecimalNumber(decimal: totals.carbohydrates).doubleValue,
                fat: NSDecimalNumber(decimal: totals.fat).doubleValue
            )
        )
    }

    private static func integerID(_ cursor: SqlCursor, name: String) throws -> Int {
        try PowerSyncValueCodec.integerID(cursor.getString(name: name))
    }

    private static func optionalIntegerID(_ cursor: SqlCursor, name: String) throws -> Int? {
        guard let value = try cursor.getStringOptional(name: name) else { return nil }
        return try PowerSyncValueCodec.integerID(value)
    }
}

private nonisolated struct LocalMealItem: Sendable {
    let id: String
    let ingredientID: Int
    let weightUnitID: Int?
    let amount: Decimal
}

private nonisolated struct LocalIngredient: Sendable {
    let id: Int
    let name: String
    let brand: String?
    let energy: Int
    let protein: String
    let carbohydrates: String
    let fat: String
}

private nonisolated struct LocalIngredientUnit: Sendable {
    let ingredientID: Int
    let value: WgerIngredientWeightUnit
}
