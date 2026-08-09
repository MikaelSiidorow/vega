import Foundation
import Testing

@testable import Vega

@MainActor
struct DiaryScreenModelTests {
    @Test
    func loadsSelectedDayAndExposesDiary() async throws {
        let date = try Self.date("2026-08-05T12:00:00Z")
        let fetcher = ScreenDiaryFetcher { _, _ in .empty }
        let model = DiaryScreenModel(
            selectedDate: date,
            calendar: Self.utcCalendar,
            diaryFetcher: fetcher,
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater()
        )

        await model.load()

        let expectedDate = try Self.date("2026-08-05T00:00:00Z")
        let diary = try #require(model.diary)
        #expect(model.selectedDate == expectedDate)
        #expect(model.diary?.date == model.selectedDate)
        #expect(model.phase == .loaded(diary))
    }

    @Test
    func navigatesByLocalCalendarDaysAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-03-08T17:00:00Z"),
            calendar: calendar,
            diaryFetcher: ScreenDiaryFetcher { _, _ in .empty },
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater()
        )

        model.selectPreviousDay()
        let previous = model.selectedDate
        model.selectNextDay()

        #expect(calendar.component(.day, from: previous) == 7)
        #expect(calendar.component(.hour, from: previous) == 0)
        #expect(calendar.component(.day, from: model.selectedDate) == 8)
        #expect(calendar.component(.hour, from: model.selectedDate) == 0)
        #expect(model.phase == .idle)
    }

    @Test
    func exposesLocalizedFailureAndCanRetry() async {
        let fetcher = RetryingDiaryFetcher()
        let model = DiaryScreenModel(
            calendar: Self.utcCalendar,
            diaryFetcher: fetcher,
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater()
        )

        await model.load()
        #expect(model.phase == .failed("The diary service is unavailable."))

        await fetcher.succeed()
        await model.load()
        #expect(model.diary != nil)
    }

    @Test
    func slowOldRequestCannotReplaceNewerDate() async throws {
        let firstDate = try Self.date("2026-08-05T00:00:00Z")
        let secondDate = try Self.date("2026-08-06T00:00:00Z")
        let fetcher = ScreenDiaryFetcher { date, _ in
            if date == firstDate {
                try await Task.sleep(for: .milliseconds(80))
            }
            return .empty
        }
        let model = DiaryScreenModel(
            selectedDate: firstDate,
            calendar: Self.utcCalendar,
            diaryFetcher: fetcher,
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater()
        )

        let oldLoad = Task { await model.load() }
        await Task.yield()
        model.selectNextDay()
        await model.load()
        await oldLoad.value

        #expect(model.selectedDate == secondDate)
        #expect(model.diary?.date == secondDate)
    }

    @Test
    func deletesEntryAndReloadsTheVisibleDiary() async throws {
        let store = FixtureDailyDiaryStore(mode: .basicLogging)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: store,
            diaryEntryUpdater: store
        )
        await model.load()

        await model.deleteEntry(id: "blueberries")

        let itemIDs = try #require(model.diary).sections.flatMap(\.items).map(\.id)
        #expect(itemIDs == ["oats", "tofu"])
        #expect(model.deletingEntryID == nil)
        #expect(model.mutationErrorMessage == nil)
    }

    @Test
    func failedDeletionKeepsTheVisibleDiaryAndExposesError() async throws {
        let store = FixtureDailyDiaryStore(mode: .basicLogging)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: FailingDiaryDeleter(),
            diaryEntryUpdater: store
        )
        await model.load()
        let originalDiary = try #require(model.diary)

        await model.deleteEntry(id: "blueberries")

        #expect(model.diary == originalDiary)
        #expect(model.mutationErrorMessage == "The diary service is unavailable.")
    }

    @Test
    func updatesAmountAndUnitThenReloadsCalculatedValues() async throws {
        let store = FixtureDailyDiaryStore(mode: .basicLogging)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: store,
            diaryEntryUpdater: store
        )
        await model.load()
        let originalTofu = try #require(
            model.diary?.sections.flatMap(\.items).first { $0.id == "tofu" }
        )

        let didSave = await model.updateEntry(
            id: "tofu",
            amount: "150",
            weightUnitID: nil,
            date: try #require(originalTofu.date),
            mealID: originalTofu.mealID
        )

        let tofu = try #require(
            model.diary?.sections.flatMap(\.items).first { $0.id == "tofu" }
        )
        #expect(didSave)
        #expect(tofu.loggedAmount == 150)
        #expect(tofu.weightUnitID == nil)
        #expect(tofu.grams == 150)
        #expect(tofu.nutrition.energy == 240)
    }

    @Test
    func failedAmountUpdateKeepsVisibleDiary() async throws {
        let store = FixtureDailyDiaryStore(mode: .basicLogging)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: store,
            diaryEntryUpdater: FailingDiaryUpdater()
        )
        await model.load()
        let originalDiary = try #require(model.diary)

        let didSave = await model.updateEntry(
            id: "tofu",
            amount: "150",
            weightUnitID: nil,
            date: try Self.date("2026-08-05T12:30:00Z"),
            mealID: nil
        )

        #expect(!didSave)
        #expect(model.diary == originalDiary)
        #expect(model.mutationErrorTitle == "Couldn’t save changes")
        #expect(model.mutationErrorMessage == "The diary service is unavailable.")
    }

    @Test
    func updatesTimeAndMealThenRegroupsEntry() async throws {
        let store = FixtureDailyDiaryStore(mode: .plannedMeals)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: store,
            diaryEntryUpdater: store
        )
        await model.load()
        let tofu = try #require(
            model.diary?.sections.flatMap(\.items).first { $0.id == "tofu" }
        )
        let newDate = try Self.date("2026-08-05T08:30:00Z")

        let didSave = await model.updateEntry(
            id: "tofu",
            amount: NSDecimalNumber(decimal: tofu.loggedAmount).stringValue,
            weightUnitID: tofu.weightUnitID,
            date: newDate,
            mealID: "breakfast"
        )

        let breakfast = try #require(
            model.diary?.sections.first { $0.id == .meal("breakfast") }
        )
        #expect(didSave)
        #expect(breakfast.items.map(\.id) == ["oats", "blueberries", "tofu"])
        #expect(breakfast.items.last?.date == newDate)
        #expect(model.diary?.sections.contains { $0.id == .meal("dinner") } == false)
    }

    @Test
    func searchesCreatesAndReloadsANewDiaryEntry() async throws {
        let store = FixtureDailyDiaryStore(mode: .basicLogging)
        let model = DiaryScreenModel(
            selectedDate: try Self.date("2026-08-05T12:00:00Z"),
            calendar: Self.utcCalendar,
            diaryFetcher: store,
            diaryEntryDeleter: store,
            diaryEntryUpdater: store,
            ingredientSearcher: store,
            diaryEntryCreator: store
        )
        await model.load()

        let banana = try #require(try await model.searchIngredients(query: "banana").first)
        let didSave = await model.createEntry(
            ingredientID: banana.id,
            amount: "2",
            weightUnitID: 41,
            date: try Self.date("2026-08-05T15:00:00Z"),
            mealID: nil
        )

        let created = try #require(
            model.diary?.sections.flatMap(\.items).first { $0.id == "created-1" }
        )
        #expect(didSave)
        #expect(created.name == "Banana")
        #expect(created.loggedAmount == 2)
        #expect(created.unitName == "medium banana")
        #expect(created.grams == 236)
        #expect(created.nutrition.energy == Decimal(string: "210.04"))
        #expect(model.isCreatingEntry == false)
    }

    @Test
    func ranksRecentFoodsByTimeForToday() async throws {
        let now = try Self.date("2026-08-06T08:00:00Z")
        let ingredient = WgerIngredient(
            id: 1,
            name: "Rolled oats",
            brand: nil,
            energy: 370,
            protein: "14",
            carbohydrates: "56",
            fat: "7",
            weightUnits: []
        )
        let history = RecentDiaryPayload(
            entries: [
                Self.recentEntry(at: "2026-08-04T08:15:00Z"),
                Self.recentEntry(at: "2026-08-05T07:45:00Z"),
            ],
            ingredients: [1: ingredient]
        )
        let model = DiaryScreenModel(
            selectedDate: now,
            calendar: Self.utcCalendar,
            diaryFetcher: ScreenDiaryFetcher { _, _ in Self.loadedPayload },
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater(),
            recentDiaryFetcher: ScreenRecentDiaryFetcher { _, _, _ in history },
            now: { now }
        )
        await model.load()

        let suggestions = try await model.recentFoodSuggestions()

        #expect(model.suggestedEntryDate == now)
        #expect(suggestions.aroundThisTime.map(\.ingredient.name) == ["Rolled oats"])
        #expect(suggestions.recent.isEmpty)
    }

    @Test
    func pastDateUsesNoTimeContext() async throws {
        let selectedDate = try Self.date("2026-08-05T12:00:00Z")
        let now = try Self.date("2026-08-06T08:00:00Z")
        let ingredient = WgerIngredient(
            id: 1,
            name: "Rolled oats",
            brand: nil,
            energy: 370,
            protein: "14",
            carbohydrates: "56",
            fat: "7",
            weightUnits: []
        )
        let history = RecentDiaryPayload(
            entries: [
                Self.recentEntry(at: "2026-08-03T12:00:00Z"),
                Self.recentEntry(at: "2026-08-04T12:00:00Z"),
            ],
            ingredients: [1: ingredient]
        )
        let model = DiaryScreenModel(
            selectedDate: selectedDate,
            calendar: Self.utcCalendar,
            diaryFetcher: ScreenDiaryFetcher { _, _ in Self.loadedPayload },
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater(),
            recentDiaryFetcher: ScreenRecentDiaryFetcher { _, _, _ in history },
            now: { now }
        )
        await model.load()

        let suggestions = try await model.recentFoodSuggestions()

        #expect(model.suggestedEntryDate == selectedDate)
        #expect(suggestions.aroundThisTime.isEmpty)
        #expect(suggestions.recent.map(\.ingredient.name) == ["Rolled oats"])
    }

    @Test
    func recentFoodFailureIsPropagatedForTheUIErrorState() async throws {
        let date = try Self.date("2026-08-06T08:00:00Z")
        let model = DiaryScreenModel(
            selectedDate: date,
            calendar: Self.utcCalendar,
            diaryFetcher: ScreenDiaryFetcher { _, _ in Self.loadedPayload },
            diaryEntryDeleter: ScreenDiaryDeleter(),
            diaryEntryUpdater: ScreenDiaryUpdater(),
            recentDiaryFetcher: ScreenRecentDiaryFetcher { _, _, _ in
                throw ScreenDiaryError.unavailable
            },
            now: { date }
        )
        await model.load()

        do {
            _ = try await model.recentFoodSuggestions()
            Issue.record("Expected recent food loading to fail")
        } catch {
            #expect(error.localizedDescription == "The diary service is unavailable.")
        }
    }

    private static var loadedPayload: DailyDiaryPayload {
        DailyDiaryPayload(
            plan: WgerNutritionPlan(
                id: "active",
                creationDate: "2026-08-01",
                start: "2026-08-01",
                end: nil,
                description: nil
            ),
            entries: [],
            ingredients: [:]
        )
    }

    private static func recentEntry(at date: String) -> WgerNutritionDiaryEntry {
        WgerNutritionDiaryEntry(
            id: date,
            planID: "active",
            mealID: nil,
            ingredientID: 1,
            weightUnitID: nil,
            date: ISO8601DateFormatter().date(from: date),
            amount: "80"
        )
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

private nonisolated struct ScreenDiaryFetcher: DailyDiaryFetching {
    let response: @Sendable (Date, Calendar) async throws -> DailyDiaryPayload

    func diary(for date: Date, calendar: Calendar) async throws -> DailyDiaryPayload {
        try await response(date, calendar)
    }
}

private nonisolated struct ScreenRecentDiaryFetcher: RecentDiaryFetching {
    let response: @Sendable (String, Date, Calendar) async throws -> RecentDiaryPayload

    func recentDiary(
        planID: String,
        before date: Date,
        calendar: Calendar
    ) async throws -> RecentDiaryPayload {
        try await response(planID, date, calendar)
    }
}

private nonisolated struct ScreenDiaryDeleter: DiaryEntryDeleting {
    func deleteDiaryEntry(id: String) {}
}

private nonisolated struct FailingDiaryDeleter: DiaryEntryDeleting {
    func deleteDiaryEntry(id: String) throws {
        throw ScreenDiaryError.unavailable
    }
}

private nonisolated struct ScreenDiaryUpdater: DiaryEntryUpdating {
    func updateDiaryEntry(
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) {}
}

private nonisolated struct FailingDiaryUpdater: DiaryEntryUpdating {
    func updateDiaryEntry(
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) throws {
        throw ScreenDiaryError.unavailable
    }
}

private actor RetryingDiaryFetcher: DailyDiaryFetching {
    private var shouldSucceed = false

    func succeed() {
        shouldSucceed = true
    }

    func diary(for date: Date, calendar: Calendar) throws -> DailyDiaryPayload {
        guard shouldSucceed else { throw ScreenDiaryError.unavailable }
        return .empty
    }
}

private nonisolated enum ScreenDiaryError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "The diary service is unavailable."
    }
}
