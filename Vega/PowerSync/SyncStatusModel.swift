import Foundation
import Observation

@MainActor
@Observable
final class SyncStatusModel {
    typealias StatusReader = @Sendable () async -> VegaSyncStatus
    typealias Reconnector = @Sendable () async throws -> Void
    typealias Sleeper = @Sendable () async throws -> Void

    private(set) var status: VegaSyncStatus = .unavailable
    private(set) var isRetrying = false

    private let readStatus: StatusReader
    private let reconnect: Reconnector
    private let sleep: Sleeper

    convenience init(powerSync: any PowerSyncDatabaseProviding) {
        self.init(
            readStatus: { await powerSync.status() },
            reconnect: { try await powerSync.reconnect() }
        )
    }

    init(
        readStatus: @escaping StatusReader,
        reconnect: @escaping Reconnector,
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds(2)) }
    ) {
        self.readStatus = readStatus
        self.reconnect = reconnect
        self.sleep = sleep
    }

    func monitor() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await sleep()
            } catch {
                return
            }
        }
    }

    func refresh() async {
        status = await readStatus()
    }

    func retry() async {
        guard !isRetrying else { return }
        isRetrying = true
        defer { isRetrying = false }
        do {
            try await reconnect()
        } catch {
            // The controller exposes the connection error through its next status snapshot.
        }
        await refresh()
    }
}
