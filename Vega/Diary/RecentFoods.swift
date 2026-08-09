import Foundation

nonisolated struct RecentFoodPortion: Equatable, Identifiable, Sendable {
    nonisolated struct ID: Equatable, Hashable, Sendable {
        let ingredientID: Int
        let amount: String
        let weightUnitID: Int?
    }

    let id: ID
    let ingredient: WgerIngredient
    let amount: String
    let weightUnitID: Int?
    let lastLoggedAt: Date
    let occurrenceCount: Int
    let matchingTimeCount: Int
}

nonisolated struct RecentFoodSuggestions: Equatable, Sendable {
    let aroundThisTime: [RecentFoodPortion]
    let recent: [RecentFoodPortion]

    static let empty = RecentFoodSuggestions(aroundThisTime: [], recent: [])
}

nonisolated enum RecentFoodRanker {
    private static let timeWindow: TimeInterval = 2 * 60 * 60

    static func suggestions(
        from payload: RecentDiaryPayload,
        referenceDate: Date,
        includesTimeContext: Bool,
        calendar: Calendar,
        aroundThisTimeLimit: Int = 6,
        recentLimit: Int = 10
    ) -> RecentFoodSuggestions {
        var grouped: [RecentFoodPortion.ID: Group] = [:]

        for entry in payload.entries {
            guard let date = entry.date,
                let ingredient = payload.ingredients[entry.ingredientID],
                let amount = canonicalAmount(entry.amount)
            else { continue }

            let id = RecentFoodPortion.ID(
                ingredientID: entry.ingredientID,
                amount: amount,
                weightUnitID: entry.weightUnitID
            )
            var group = grouped[id] ?? Group(ingredient: ingredient)
            group.dates.append(date)
            grouped[id] = group
        }

        let portions = grouped.map { id, group in
            let matchingTimeCount =
                includesTimeContext
                ? group.dates.count {
                    timeDistance(from: $0, to: referenceDate, calendar: calendar) <= timeWindow
                }
                : 0
            return RecentFoodPortion(
                id: id,
                ingredient: group.ingredient,
                amount: id.amount,
                weightUnitID: id.weightUnitID,
                lastLoggedAt: group.dates.max()!,
                occurrenceCount: group.dates.count,
                matchingTimeCount: matchingTimeCount
            )
        }

        let aroundThisTime =
            portions
            .filter { $0.matchingTimeCount >= 2 }
            .sorted(by: contextualOrder)
            .prefix(max(0, aroundThisTimeLimit))
        let contextualIDs = Set(aroundThisTime.map(\.id))
        let recent =
            portions
            .filter { !contextualIDs.contains($0.id) }
            .sorted(by: recentOrder)
            .prefix(max(0, recentLimit))

        return RecentFoodSuggestions(
            aroundThisTime: Array(aroundThisTime),
            recent: Array(recent)
        )
    }

    private struct Group {
        let ingredient: WgerIngredient
        var dates: [Date] = []
    }

    private static func canonicalAmount(_ amount: String) -> String? {
        let locale = Locale(identifier: "en_US_POSIX")
        guard let value = Decimal(string: amount, locale: locale), value > 0 else { return nil }
        return NSDecimalNumber(decimal: value).stringValue
    }

    private static func timeDistance(
        from first: Date,
        to second: Date,
        calendar: Calendar
    ) -> TimeInterval {
        let firstStart = calendar.startOfDay(for: first)
        let secondStart = calendar.startOfDay(for: second)
        let firstTime = first.timeIntervalSince(firstStart)
        let secondTime = second.timeIntervalSince(secondStart)
        let direct = abs(firstTime - secondTime)
        return min(direct, 24 * 60 * 60 - direct)
    }

    private static func contextualOrder(
        _ left: RecentFoodPortion,
        _ right: RecentFoodPortion
    ) -> Bool {
        if left.matchingTimeCount != right.matchingTimeCount {
            return left.matchingTimeCount > right.matchingTimeCount
        }
        if left.occurrenceCount != right.occurrenceCount {
            return left.occurrenceCount > right.occurrenceCount
        }
        return recentOrder(left, right)
    }

    private static func recentOrder(
        _ left: RecentFoodPortion,
        _ right: RecentFoodPortion
    ) -> Bool {
        if left.lastLoggedAt != right.lastLoggedAt {
            return left.lastLoggedAt > right.lastLoggedAt
        }
        if left.ingredient.name != right.ingredient.name {
            return left.ingredient.name.localizedStandardCompare(right.ingredient.name)
                == .orderedAscending
        }
        if left.id.ingredientID != right.id.ingredientID {
            return left.id.ingredientID < right.id.ingredientID
        }
        if left.id.amount != right.id.amount {
            return left.id.amount < right.id.amount
        }
        return (left.id.weightUnitID ?? Int.min) < (right.id.weightUnitID ?? Int.min)
    }
}
