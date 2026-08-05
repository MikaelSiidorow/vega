import Testing
import WgerAPI

@testable import Vega

nonisolated struct AuthenticatedAPIClientTests {
    @Test
    func requiresAnActiveSession() async {
        let client = AuthenticatedAPIClient(
            sessionCoordinator: APIClientSessionCoordinator()
        )

        await #expect(throws: SessionCoordinatorError.noSession) {
            try await client.perform { _, _ in "unused" }
        }
    }

    @Test
    func returnsSuccessfulRequestWithoutRefreshing() async throws {
        let coordinator = APIClientSessionCoordinator()
        await coordinator.set(
            ActiveSession(
                instance: try InstanceURL("wger.example"),
                credentials: AuthenticationSession(
                    accessToken: "access",
                    refreshToken: "refresh"
                )
            )
        )
        let client = AuthenticatedAPIClient(sessionCoordinator: coordinator)

        let accessToken = try await client.perform { _, credentials in
            credentials.accessToken
        }

        #expect(accessToken == "access")
        #expect(await coordinator.refreshCount == 0)
    }

    @Test
    func refreshesAndReplaysOnceAfterUnauthorizedResponse() async throws {
        let coordinator = APIClientSessionCoordinator()
        await coordinator.set(
            ActiveSession(
                instance: try InstanceURL("wger.example"),
                credentials: AuthenticationSession(
                    accessToken: "old-access",
                    refreshToken: "old-refresh"
                )
            )
        )
        let attempts = APIClientAttemptRecorder()
        let client = AuthenticatedAPIClient(sessionCoordinator: coordinator)

        let accessToken = try await client.perform { _, credentials in
            let attempt = await attempts.record()
            if attempt == 1 {
                throw WgerAPIError.unexpectedStatus(401)
            }
            return credentials.accessToken
        }

        #expect(accessToken == "new-access")
        #expect(await attempts.count == 2)
        #expect(await coordinator.refreshCount == 1)
    }

    @Test
    func doesNotRefreshOtherFailures() async throws {
        let coordinator = APIClientSessionCoordinator()
        await coordinator.set(
            ActiveSession(
                instance: try InstanceURL("wger.example"),
                credentials: AuthenticationSession(
                    accessToken: "access",
                    refreshToken: "refresh"
                )
            )
        )
        let client = AuthenticatedAPIClient(sessionCoordinator: coordinator)

        await #expect(throws: WgerAPIError.unexpectedStatus(500)) {
            try await client.perform { _, _ in
                throw WgerAPIError.unexpectedStatus(500)
            }
        }
        #expect(await coordinator.refreshCount == 0)
    }
}

private actor APIClientSessionCoordinator: SessionCoordinating {
    private var session: ActiveSession?
    private(set) var refreshCount = 0

    func set(_ session: ActiveSession) {
        self.session = session
    }

    func establish(instance: InstanceURL, credentials: AuthenticationSession) {
        session = ActiveSession(instance: instance, credentials: credentials)
    }

    func restore() -> ActiveSession? {
        session
    }

    func current() -> ActiveSession? {
        session
    }

    func refresh() throws -> ActiveSession {
        refreshCount += 1
        guard let session else { throw SessionCoordinatorError.noSession }
        let refreshed = ActiveSession(
            instance: session.instance,
            credentials: AuthenticationSession(
                accessToken: "new-access",
                refreshToken: "new-refresh"
            )
        )
        self.session = refreshed
        return refreshed
    }

    func clear() {
        session = nil
    }
}

private actor APIClientAttemptRecorder {
    private(set) var count = 0

    func record() -> Int {
        count += 1
        return count
    }
}
