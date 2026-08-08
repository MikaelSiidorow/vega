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
            diaryEntryDeleter: ScreenDiaryDeleter()
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
            diaryEntryDeleter: ScreenDiaryDeleter()
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
            diaryEntryDeleter: ScreenDiaryDeleter()
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
            diaryEntryDeleter: ScreenDiaryDeleter()
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
            diaryEntryDeleter: store
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
            diaryEntryDeleter: FailingDiaryDeleter()
        )
        await model.load()
        let originalDiary = try #require(model.diary)

        await model.deleteEntry(id: "blueberries")

        #expect(model.diary == originalDiary)
        #expect(model.mutationErrorMessage == "The diary service is unavailable.")
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

private nonisolated struct ScreenDiaryDeleter: DiaryEntryDeleting {
    func deleteDiaryEntry(id: String) {}
}

private nonisolated struct FailingDiaryDeleter: DiaryEntryDeleting {
    func deleteDiaryEntry(id: String) throws {
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
