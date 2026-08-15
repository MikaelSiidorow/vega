import Foundation
import Testing

@testable import Vega

nonisolated struct SessionCoordinatorTests {
    @Test
    func establishesAndPersistsSession() async throws {
        let store = CoordinatorCredentialStore()
        let coordinator = SessionCoordinator(
            sessionRefresher: CoordinatorSessionRefresher(
                result: .failure(.expiredSession)
            ),
            credentialStore: store
        )
        let instance = try InstanceURL("wger.example")
        let credentials = AuthenticationSession(
            accessToken: "access",
            refreshToken: "refresh"
        )

        try await coordinator.establish(instance: instance, credentials: credentials)

        #expect(
            await coordinator.current()
                == ActiveSession(instance: instance, credentials: credentials)
        )
        #expect(
            await store.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    accessToken: "access",
                    refreshToken: "refresh"
                )
        )
    }

    @Test
    func restoresCachedAccessWithoutNetwork() async throws {
        let stored = StoredSession(
            instanceAddress: "https://wger.example/",
            accessToken: "cached-access",
            refreshToken: "refresh"
        )
        let store = CoordinatorCredentialStore(session: stored)
        let refresher = CoordinatorSessionRefresher(result: .failure(.network))
        let coordinator = SessionCoordinator(
            sessionRefresher: refresher,
            credentialStore: store
        )

        let restored = try await coordinator.restore()

        #expect(restored?.credentials.accessToken == "cached-access")
        #expect(await refresher.callCount == 0)
        #expect(await store.session == stored)
    }

    @Test
    func concurrentRefreshesShareOneRotation() async throws {
        let store = CoordinatorCredentialStore()
        let refresher = CoordinatorSessionRefresher(
            result: .success(
                AuthenticationSession(
                    accessToken: "new-access",
                    refreshToken: "new-refresh"
                )
            ),
            delayNanoseconds: 50_000_000
        )
        let coordinator = SessionCoordinator(
            sessionRefresher: refresher,
            credentialStore: store
        )
        try await coordinator.establish(
            instance: InstanceURL("wger.example"),
            credentials: AuthenticationSession(
                accessToken: "old-access",
                refreshToken: "old-refresh"
            )
        )

        async let first = coordinator.refresh()
        async let second = coordinator.refresh()
        let sessions = try await [first, second]

        #expect(sessions[0] == sessions[1])
        #expect(sessions[0].credentials.accessToken == "new-access")
        #expect(await refresher.callCount == 1)
        #expect(
            await store.session?.refreshToken == "new-refresh"
        )
    }

    @Test
    func rejectedRefreshClearsSession() async throws {
        let store = CoordinatorCredentialStore()
        let coordinator = SessionCoordinator(
            sessionRefresher: CoordinatorSessionRefresher(
                result: .failure(.expiredSession)
            ),
            credentialStore: store
        )
        try await coordinator.establish(
            instance: InstanceURL("wger.example"),
            credentials: AuthenticationSession(
                accessToken: "access",
                refreshToken: "expired"
            )
        )

        await #expect(throws: AuthenticationError.expiredSession) {
            try await coordinator.refresh()
        }

        #expect(await coordinator.current() == nil)
        #expect(await store.session == nil)
    }
}

private actor CoordinatorSessionRefresher: SessionRefreshing {
    let result: Result<AuthenticationSession, AuthenticationError>
    let delayNanoseconds: UInt64
    private(set) var callCount = 0

    init(
        result: Result<AuthenticationSession, AuthenticationError>,
        delayNanoseconds: UInt64 = 0
    ) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func refresh(
        instance: InstanceURL,
        refreshToken: String
    ) async throws -> AuthenticationSession {
        callCount += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }
}

private actor CoordinatorCredentialStore: SessionCredentialStoring {
    private(set) var session: StoredSession?

    init(session: StoredSession? = nil) {
        self.session = session
    }

    func load() -> StoredSession? {
        session
    }

    func save(_ session: StoredSession) {
        self.session = session
    }

    func clear() {
        session = nil
    }
}
