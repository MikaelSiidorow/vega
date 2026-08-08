import Foundation
import WgerAPI

nonisolated struct DailyDiaryPayload: Equatable, Sendable {
    let plan: WgerNutritionPlan?
    let entries: [WgerNutritionDiaryEntry]
    let ingredients: [Int: WgerIngredient]

    static let empty = DailyDiaryPayload(plan: nil, entries: [], ingredients: [:])
}

nonisolated protocol DailyDiaryFetching: Sendable {
    func diary(for date: Date, calendar: Calendar) async throws -> DailyDiaryPayload
}

nonisolated protocol DiaryEntryDeleting: Sendable {
    func deleteDiaryEntry(id: String) async throws
}

nonisolated protocol DailyDiaryTransport: Sendable {
    func plans(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerNutritionPlan>

    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        planID: String,
        from start: Date,
        to end: Date,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerNutritionDiaryEntry>

    func ingredients(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) async throws -> [WgerIngredient]

    func deleteEntry(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) async throws
}

nonisolated struct WgerDailyDiaryTransport: DailyDiaryTransport {
    func plans(
        instance: InstanceURL,
        session: AuthenticationSession,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerNutritionPlan> {
        let page = try await WgerAPIModule.nutritionPlans(
            serverURL: instance.url,
            accessToken: session.accessToken,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.compactMap(\.vegaValue),
            hasNextPage: page.next != nil
        )
    }

    func entries(
        instance: InstanceURL,
        session: AuthenticationSession,
        planID: String,
        from start: Date,
        to end: Date,
        limit: Int,
        offset: Int
    ) async throws -> WgerPage<WgerNutritionDiaryEntry> {
        let page = try await WgerAPIModule.nutritionDiary(
            serverURL: instance.url,
            accessToken: session.accessToken,
            planID: planID,
            from: start,
            to: end,
            limit: limit,
            offset: offset
        )
        return WgerPage(
            values: page.results.map(\.vegaValue),
            hasNextPage: page.next != nil
        )
    }

    func ingredients(
        instance: InstanceURL,
        session: AuthenticationSession,
        ids: [Int]
    ) async throws -> [WgerIngredient] {
        let page = try await WgerAPIModule.ingredientInfo(
            serverURL: instance.url,
            accessToken: session.accessToken,
            ids: ids
        )
        return page.results.map(\.vegaValue)
    }

    func deleteEntry(
        instance: InstanceURL,
        session: AuthenticationSession,
        id: String
    ) async throws {
        try await WgerAPIModule.deleteNutritionDiaryEntry(
            serverURL: instance.url,
            accessToken: session.accessToken,
            id: id
        )
    }
}

actor DailyDiaryAPI: DailyDiaryFetching, DiaryEntryDeleting {
    private static let pageSize = 100
    private let client: any AuthenticatedRequestExecuting
    private let transport: any DailyDiaryTransport
    private var ingredientCache: [Int: WgerIngredient] = [:]

    init(
        client: any AuthenticatedRequestExecuting,
        transport: any DailyDiaryTransport = WgerDailyDiaryTransport()
    ) {
        self.client = client
        self.transport = transport
    }

    func diary(for date: Date, calendar: Calendar) async throws -> DailyDiaryPayload {
        guard let interval = calendar.dateInterval(of: .day, for: date) else {
            return .empty
        }
        let cachedIngredients = ingredientCache
        let transport = transport

        let result = try await client.perform { instance, session in
            let plans = try await Self.allPlans(
                transport: transport,
                instance: instance,
                session: session
            )
            guard let plan = Self.activePlan(in: plans, for: date, calendar: calendar) else {
                return DailyDiaryPayload.empty
            }
            let entries = try await Self.allEntries(
                transport: transport,
                instance: instance,
                session: session,
                planID: plan.id,
                interval: interval
            )
            let missingIDs = Set(entries.map(\.ingredientID)).subtracting(cachedIngredients.keys)
            var ingredients = cachedIngredients
            for batch in missingIDs.sorted().chunks(ofCount: Self.pageSize) {
                let hydrated = try await transport.ingredients(
                    instance: instance,
                    session: session,
                    ids: batch
                )
                for ingredient in hydrated {
                    ingredients[ingredient.id] = ingredient
                }
            }
            return DailyDiaryPayload(plan: plan, entries: entries, ingredients: ingredients)
        }
        ingredientCache.merge(result.ingredients) { _, latest in latest }
        return result
    }

    func deleteDiaryEntry(id: String) async throws {
        let transport = transport
        try await client.perform { instance, session in
            try await transport.deleteEntry(instance: instance, session: session, id: id)
        }
    }

    private static func allPlans(
        transport: any DailyDiaryTransport,
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> [WgerNutritionPlan] {
        var result: [WgerNutritionPlan] = []
        var offset = 0
        while true {
            let page = try await transport.plans(
                instance: instance,
                session: session,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func allEntries(
        transport: any DailyDiaryTransport,
        instance: InstanceURL,
        session: AuthenticationSession,
        planID: String,
        interval: DateInterval
    ) async throws -> [WgerNutritionDiaryEntry] {
        var result: [WgerNutritionDiaryEntry] = []
        var offset = 0
        while true {
            let page = try await transport.entries(
                instance: instance,
                session: session,
                planID: planID,
                from: interval.start,
                to: interval.end,
                limit: pageSize,
                offset: offset
            )
            result.append(contentsOf: page.values)
            guard page.hasNextPage, !page.values.isEmpty else { return result }
            offset += page.values.count
        }
    }

    private static func activePlan(
        in plans: [WgerNutritionPlan],
        for date: Date,
        calendar: Calendar
    ) -> WgerNutritionPlan? {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month,
            let dayOfMonth = components.day
        else { return nil }
        let day = String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
        return
            plans
            .filter { ($0.start == nil || $0.start! <= day) && ($0.end == nil || $0.end! >= day) }
            .sorted { ($0.start ?? $0.creationDate) > ($1.start ?? $1.creationDate) }
            .first
    }
}

nonisolated extension Array {
    fileprivate func chunks(ofCount size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
