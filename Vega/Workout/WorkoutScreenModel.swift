import Foundation
import Observation

@MainActor
@Observable
final class WorkoutScreenModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded(WorkoutDashboard)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var mutatingLogID: String?
    private(set) var isCreatingSet = false
    var mutationErrorMessage: String?

    private let dashboardFetcher: any WorkoutDashboardFetching
    private let setCreator: any WorkoutSetCreating
    private let setUpdater: any WorkoutSetUpdating
    private let setDeleter: any WorkoutSetDeleting
    private let calendar: Calendar
    private let now: @Sendable () -> Date

    init(
        dashboardFetcher: any WorkoutDashboardFetching,
        setCreator: any WorkoutSetCreating,
        setUpdater: any WorkoutSetUpdating,
        setDeleter: any WorkoutSetDeleting,
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.dashboardFetcher = dashboardFetcher
        self.setCreator = setCreator
        self.setUpdater = setUpdater
        self.setDeleter = setDeleter
        self.calendar = calendar
        self.now = now
    }

    var dashboard: WorkoutDashboard? {
        guard case .loaded(let dashboard) = phase else { return nil }
        return dashboard
    }

    func load() async {
        phase = .loading
        do {
            phase = .loaded(try await dashboardFetcher.dashboard(for: now(), calendar: calendar))
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    func createSet(
        for plan: WorkoutExercisePlan,
        day: PlannedWorkoutDay,
        input: WorkoutSetInput
    ) async -> Bool {
        guard !isCreatingSet else { return false }
        isCreatingSet = true
        mutationErrorMessage = nil
        defer { isCreatingSet = false }
        do {
            try await setCreator.createSet(for: plan, day: day, input: input)
            try await reload()
            return true
        } catch is CancellationError {
            return false
        } catch {
            mutationErrorMessage = Self.message(for: error)
            return false
        }
    }

    func updateSet(id: String, input: WorkoutSetInput) async -> Bool {
        guard mutatingLogID == nil else { return false }
        mutatingLogID = id
        mutationErrorMessage = nil
        defer { mutatingLogID = nil }
        do {
            try await setUpdater.updateSet(id: id, input: input)
            try await reload()
            return true
        } catch is CancellationError {
            return false
        } catch {
            mutationErrorMessage = Self.message(for: error)
            return false
        }
    }

    func deleteSet(id: String) async {
        guard mutatingLogID == nil else { return }
        mutatingLogID = id
        mutationErrorMessage = nil
        defer { mutatingLogID = nil }
        do {
            try await setDeleter.deleteSet(id: id)
            try await reload()
        } catch is CancellationError {
            return
        } catch {
            mutationErrorMessage = Self.message(for: error)
        }
    }

    private func reload() async throws {
        phase = .loaded(try await dashboardFetcher.dashboard(for: now(), calendar: calendar))
    }

    private static func message(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "The workout service returned an unknown error." : message
    }
}
