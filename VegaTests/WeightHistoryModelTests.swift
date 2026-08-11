import Foundation
import Testing

@testable import Vega

@MainActor
struct WeightHistoryModelTests {
    @Test(arguments: [
        ("79", "79"),
        ("79.25", "79.25"),
        (" 79,5 ", "79.5"),
        ("600.00", "600"),
    ])
    func normalizesValidServerWeights(_ input: String, _ expected: String) {
        #expect(WeightInput.normalized(input) == expected)
    }

    @Test(arguments: ["", "29.99", "600.01", "80.123", "weight", "80."])
    func rejectsInvalidServerWeights(_ input: String) {
        #expect(WeightInput.normalized(input) == nil)
    }

    @Test
    func loadsNewestFirstFiltersRangesAndMutates() async throws {
        let now = try Self.date("2026-08-11T12:00:00Z")
        let store = FixtureWeightStore()
        let model = WeightHistoryModel(
            historyFetcher: store,
            entryCreator: store,
            entryUpdater: store,
            entryDeleter: store,
            calendar: Self.utcCalendar,
            now: { now }
        )

        await model.load()
        #expect(model.latestEntry?.weight == 79.6)
        #expect(model.rangedEntries.count == 11)
        #expect(model.changeInRange == -2.6)

        model.selectedRange = .all
        #expect(model.rangedEntries.count == 14)
        #expect(await model.create(date: now, weight: "79,4"))
        let created = try #require(model.latestEntry)
        #expect(created.weight == 79.4)
        #expect(await model.update(id: created.id, date: now, weight: "79.3"))
        #expect(model.latestEntry?.weight == 79.3)
        await model.delete(id: created.id)
        #expect(model.latestEntry?.weight == 79.6)
    }

    @Test
    func computesTrailingSevenCalendarDayAverageFromDailyMeans() async throws {
        let entries = try [
            WgerWeightEntry(id: 1, date: Self.date("2026-08-01T07:00:00Z"), weight: 70),
            WgerWeightEntry(id: 2, date: Self.date("2026-08-01T19:00:00Z"), weight: 72),
            WgerWeightEntry(id: 3, date: Self.date("2026-08-02T07:00:00Z"), weight: 71),
            WgerWeightEntry(id: 4, date: Self.date("2026-08-03T07:00:00Z"), weight: 72),
            WgerWeightEntry(id: 5, date: Self.date("2026-08-04T07:00:00Z"), weight: 73),
            WgerWeightEntry(id: 6, date: Self.date("2026-08-05T07:00:00Z"), weight: 74),
            WgerWeightEntry(id: 7, date: Self.date("2026-08-06T07:00:00Z"), weight: 75),
            WgerWeightEntry(id: 8, date: Self.date("2026-08-07T07:00:00Z"), weight: 76),
            WgerWeightEntry(id: 9, date: Self.date("2026-08-08T07:00:00Z"), weight: 84),
        ]
        let store = FixtureWeightStore(entries: entries)
        let now = try Self.date("2026-08-08T12:00:00Z")
        let model = WeightHistoryModel(
            historyFetcher: store,
            entryCreator: store,
            entryUpdater: store,
            entryDeleter: store,
            calendar: Self.utcCalendar,
            now: { now }
        )
        model.selectedRange = .all

        await model.load()

        #expect(model.sevenDayTrend.count == 8)
        #expect(model.sevenDayTrend.first?.average == 71)
        #expect(model.sevenDayTrend.last?.average == 75)
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
