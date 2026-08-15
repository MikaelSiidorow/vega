import Foundation
import Testing

@testable import Vega

@MainActor
struct SyncStatusModelTests {
    @Test
    func refreshesOfflineQueueAndReconnects() async {
        let probe = SyncStatusProbe(
            status: VegaSyncStatus(
                connected: false,
                connecting: false,
                downloading: false,
                uploading: false,
                hasSynced: true,
                lastSyncedAt: nil,
                pendingUploads: 2,
                errorMessage: nil,
                rejection: nil
            )
        )
        let model = SyncStatusModel(
            readStatus: { await probe.currentStatus() },
            reconnect: { await probe.reconnect() }
        )

        await model.refresh()
        #expect(model.status.pendingUploads == 2)
        #expect(!model.status.connected)

        await model.retry()

        let reconnectCount = await probe.reconnectCount
        #expect(reconnectCount == 1)
        #expect(model.status.connected)
        #expect(model.status.pendingUploads == 0)
        #expect(!model.isRetrying)
    }

    @Test
    func ignoresOverlappingReconnects() async {
        let gate = AsyncGate()
        let model = SyncStatusModel(
            readStatus: { .unavailable },
            reconnect: { await gate.wait() }
        )

        let first = Task { await model.retry() }
        while await gate.waitCount == 0 {
            await Task.yield()
        }
        await model.retry()
        await gate.open()
        await first.value

        let waitCount = await gate.waitCount
        #expect(waitCount == 1)
    }
}

private actor SyncStatusProbe {
    private var status: VegaSyncStatus
    private(set) var reconnectCount = 0

    init(status: VegaSyncStatus) {
        self.status = status
    }

    func currentStatus() -> VegaSyncStatus {
        status
    }

    func reconnect() {
        reconnectCount += 1
        status = VegaSyncStatus(
            connected: true,
            connecting: false,
            downloading: false,
            uploading: false,
            hasSynced: true,
            lastSyncedAt: Date(timeIntervalSince1970: 1_786_838_400),
            pendingUploads: 0,
            errorMessage: nil,
            rejection: nil
        )
    }
}

private actor AsyncGate {
    private(set) var waitCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        waitCount += 1
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
