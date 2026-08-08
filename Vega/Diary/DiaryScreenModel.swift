import Foundation
import Observation

@MainActor
@Observable
final class DiaryScreenModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(DailyDiary)
        case failed(String)
    }

    private(set) var selectedDate: Date
    private(set) var phase: Phase = .idle
    private(set) var deletingEntryID: String?
    private(set) var updatingEntryID: String?
    private(set) var mutationErrorTitle: String?
    var mutationErrorMessage: String?

    private let diaryFetcher: any DailyDiaryFetching
    private let diaryEntryDeleter: any DiaryEntryDeleting
    private let diaryEntryUpdater: any DiaryEntryUpdating
    private let calendar: Calendar
    private var selectionRevision = 0

    init(
        selectedDate: Date = Date(),
        calendar: Calendar = .current,
        diaryFetcher: any DailyDiaryFetching,
        diaryEntryDeleter: any DiaryEntryDeleting,
        diaryEntryUpdater: any DiaryEntryUpdating
    ) {
        self.calendar = calendar
        self.diaryFetcher = diaryFetcher
        self.diaryEntryDeleter = diaryEntryDeleter
        self.diaryEntryUpdater = diaryEntryUpdater
        self.selectedDate = calendar.startOfDay(for: selectedDate)
    }

    var diary: DailyDiary? {
        guard case .loaded(let diary) = phase else { return nil }
        return diary
    }

    var errorMessage: String? {
        guard case .failed(let message) = phase else { return nil }
        return message
    }

    func selectPreviousDay() {
        selectDay(offset: -1)
    }

    func selectNextDay() {
        selectDay(offset: 1)
    }

    func selectToday(now: Date = Date()) {
        select(calendar.startOfDay(for: now))
    }

    func load() async {
        let requestedDate = selectedDate
        let requestedRevision = selectionRevision
        phase = .loading

        do {
            let payload = try await diaryFetcher.diary(for: requestedDate, calendar: calendar)
            try Task.checkCancellation()
            let diary = try DailyDiary.build(from: payload, date: requestedDate)
            guard requestedRevision == selectionRevision, requestedDate == selectedDate else {
                return
            }
            phase = .loaded(diary)
        } catch is CancellationError {
            return
        } catch {
            guard requestedRevision == selectionRevision, requestedDate == selectedDate else {
                return
            }
            phase = .failed(Self.message(for: error))
        }
    }

    func deleteEntry(id: String) async {
        guard deletingEntryID == nil else { return }
        deletingEntryID = id
        mutationErrorTitle = nil
        mutationErrorMessage = nil
        defer { deletingEntryID = nil }

        do {
            try await diaryEntryDeleter.deleteDiaryEntry(id: id)
            try await reloadPreservingContent()
        } catch is CancellationError {
            return
        } catch {
            mutationErrorTitle = "Couldn’t delete entry"
            mutationErrorMessage = Self.mutationMessage(for: error)
        }
    }

    func updateEntry(
        id: String,
        amount: String,
        weightUnitID: Int?,
        date: Date,
        mealID: String?
    ) async -> Bool {
        guard updatingEntryID == nil else { return false }
        updatingEntryID = id
        mutationErrorTitle = nil
        mutationErrorMessage = nil
        defer { updatingEntryID = nil }

        do {
            try await diaryEntryUpdater.updateDiaryEntry(
                id: id,
                amount: amount,
                weightUnitID: weightUnitID,
                date: date,
                mealID: mealID
            )
            try await reloadPreservingContent()
            return true
        } catch is CancellationError {
            return false
        } catch {
            mutationErrorTitle = "Couldn’t save changes"
            mutationErrorMessage = Self.updateMessage(for: error)
            return false
        }
    }

    private func reloadPreservingContent() async throws {
        let requestedDate = selectedDate
        let requestedRevision = selectionRevision
        let payload = try await diaryFetcher.diary(for: requestedDate, calendar: calendar)
        try Task.checkCancellation()
        let diary = try DailyDiary.build(from: payload, date: requestedDate)
        guard requestedRevision == selectionRevision, requestedDate == selectedDate else { return }
        phase = .loaded(diary)
    }

    private func selectDay(offset: Int) {
        guard let date = calendar.date(byAdding: .day, value: offset, to: selectedDate) else {
            return
        }
        select(calendar.startOfDay(for: date))
    }

    private func select(_ date: Date) {
        guard date != selectedDate else { return }
        selectedDate = date
        selectionRevision += 1
        phase = .idle
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Vega could not load this diary. Please try again."
    }

    private static func mutationMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Vega could not delete this entry. Please try again."
    }

    private static func updateMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "Vega could not update this entry. Please try again."
    }
}
