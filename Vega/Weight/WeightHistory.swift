import Foundation
import Observation

nonisolated enum WeightRange: String, CaseIterable, Identifiable, Sendable {
    case month
    case quarter
    case year
    case all

    var id: Self { self }

    var title: String {
        switch self {
        case .month: "30D"
        case .quarter: "90D"
        case .year: "1Y"
        case .all: "All"
        }
    }

    func includes(_ date: Date, relativeTo now: Date, calendar: Calendar) -> Bool {
        let component: DateComponents?
        switch self {
        case .month: component = DateComponents(day: -30)
        case .quarter: component = DateComponents(day: -90)
        case .year: component = DateComponents(year: -1)
        case .all: component = nil
        }
        guard let component, let cutoff = calendar.date(byAdding: component, to: now) else {
            return true
        }
        return date >= cutoff
    }
}

nonisolated enum WeightInput {
    static func normalized(_ input: String) -> String? {
        let candidate = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        let parts = candidate.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
            (1...3).contains(parts[0].count),
            parts[0].allSatisfy(\.isNumber),
            parts.count == 1 || (1...2).contains(parts[1].count) && parts[1].allSatisfy(\.isNumber),
            let value = Decimal(string: candidate, locale: Locale(identifier: "en_US_POSIX")),
            value >= 30,
            value <= 600
        else {
            return nil
        }
        return NSDecimalNumber(decimal: value).stringValue
    }
}

nonisolated struct WeightTrendPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let average: Decimal

    var id: Date { date }
}

@MainActor
@Observable
final class WeightHistoryModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var entries: [WgerWeightEntry] = []
    private(set) var mutatingEntryID: String?
    private(set) var isCreating = false
    var selectedRange = WeightRange.quarter
    var mutationErrorMessage: String?

    private let historyFetcher: any WeightHistoryFetching
    private let entryCreator: any WeightEntryCreating
    private let entryUpdater: any WeightEntryUpdating
    private let entryDeleter: any WeightEntryDeleting
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        historyFetcher: any WeightHistoryFetching,
        entryCreator: any WeightEntryCreating,
        entryUpdater: any WeightEntryUpdating,
        entryDeleter: any WeightEntryDeleting,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.historyFetcher = historyFetcher
        self.entryCreator = entryCreator
        self.entryUpdater = entryUpdater
        self.entryDeleter = entryDeleter
        self.calendar = calendar
        self.now = now
    }

    var latestEntry: WgerWeightEntry? {
        entries.first
    }

    var suggestedDate: Date {
        now()
    }

    var rangedEntries: [WgerWeightEntry] {
        entries.filter { selectedRange.includes($0.date, relativeTo: now(), calendar: calendar) }
            .sorted { $0.date < $1.date }
    }

    var sevenDayTrend: [WeightTrendPoint] {
        let dailyWeights = Dictionary(grouping: entries) {
            calendar.startOfDay(for: $0.date)
        }
        .map { _, entries in
            WeightTrendPoint(
                date: entries.map(\.date).max()!,
                average: entries.reduce(Decimal.zero) { $0 + $1.weight }
                    / Decimal(entries.count)
            )
        }
        .sorted { $0.date < $1.date }

        var firstIncludedIndex = 0
        var runningTotal = Decimal.zero
        var trend: [WeightTrendPoint] = []

        for (index, dailyWeight) in dailyWeights.enumerated() {
            runningTotal += dailyWeight.average
            let day = calendar.startOfDay(for: dailyWeight.date)
            let cutoff = calendar.date(byAdding: .day, value: -6, to: day)!
            while calendar.startOfDay(for: dailyWeights[firstIncludedIndex].date) < cutoff {
                runningTotal -= dailyWeights[firstIncludedIndex].average
                firstIncludedIndex += 1
            }
            trend.append(
                WeightTrendPoint(
                    date: dailyWeight.date,
                    average: runningTotal / Decimal(index - firstIncludedIndex + 1)
                )
            )
        }
        return trend.filter {
            selectedRange.includes($0.date, relativeTo: now(), calendar: calendar)
        }
    }

    var changeInRange: Decimal? {
        guard let first = rangedEntries.first, let last = rangedEntries.last, first.id != last.id
        else { return nil }
        return last.weight - first.weight
    }

    func load() async {
        if entries.isEmpty { phase = .loading }
        do {
            entries = try await historyFetcher.weightHistory().sorted { $0.date > $1.date }
            phase = .loaded
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func observe() async {
        if entries.isEmpty { phase = .loading }
        do {
            let stream = try await historyFetcher.weightHistoryStream()
            for try await values in stream {
                entries = values.sorted { $0.date > $1.date }
                phase = .loaded
            }
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func create(date: Date, weight: String) async -> Bool {
        guard let weight = WeightInput.normalized(weight), !isCreating else { return false }
        isCreating = true
        mutationErrorMessage = nil
        defer { isCreating = false }
        do {
            try await entryCreator.createWeightEntry(date: date, weight: weight)
            try await reload()
            return true
        } catch {
            mutationErrorMessage = "The weight entry couldn’t be added. \(Self.message(for: error))"
            return false
        }
    }

    func update(id: String, date: Date, weight: String) async -> Bool {
        guard let weight = WeightInput.normalized(weight), mutatingEntryID == nil else {
            return false
        }
        mutatingEntryID = id
        mutationErrorMessage = nil
        defer { mutatingEntryID = nil }
        do {
            try await entryUpdater.updateWeightEntry(id: id, date: date, weight: weight)
            try await reload()
            return true
        } catch {
            mutationErrorMessage = "The weight entry couldn’t be saved. \(Self.message(for: error))"
            return false
        }
    }

    func delete(id: String) async {
        guard mutatingEntryID == nil else { return }
        mutatingEntryID = id
        mutationErrorMessage = nil
        defer { mutatingEntryID = nil }
        do {
            try await entryDeleter.deleteWeightEntry(id: id)
            try await reload()
        } catch {
            mutationErrorMessage =
                "The weight entry couldn’t be deleted. \(Self.message(for: error))"
        }
    }

    private func reload() async throws {
        entries = try await historyFetcher.weightHistory().sorted { $0.date > $1.date }
        phase = .loaded
    }

    private static func message(for error: Error) -> String {
        if let error = error as? LocalizedError, let description = error.errorDescription {
            return description
        }
        return "Please try again."
    }
}
