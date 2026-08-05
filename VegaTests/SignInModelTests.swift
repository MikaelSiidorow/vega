import Testing

@testable import Vega

@MainActor
struct SignInModelTests {
    @Test
    func defaultsToThePublicWgerService() {
        let model = SignInModel()

        #expect(model.instanceAddress == "https://wger.de")
    }

    @Test
    func provesConnectionPersistsSessionAndClearsSecrets() async throws {
        let credentialStore = InMemorySessionCredentialStore()
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(
                result: .success(
                    AuthenticationSession(accessToken: "access", refreshToken: "refresh")
                )
            ),
            connectionChecker: StubConnectionChecker(result: .success(2)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(result: .failure(.expiredSession)),
                credentialStore: credentialStore
            )
        )
        model.instanceAddress = "wger.example"
        model.username = "test-user"
        model.password = "secret"

        await model.signIn()

        #expect(model.connectedAccount?.nutritionPlanCount == 2)
        #expect(model.password.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(
            await credentialStore.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    refreshToken: "refresh"
                )
        )

        await model.signOut()
        #expect(model.connectedAccount == nil)
        #expect(await credentialStore.session == nil)
    }

    @Test
    func restoresAndRotatesSavedSession() async throws {
        let credentialStore = InMemorySessionCredentialStore(
            session: StoredSession(
                instanceAddress: "https://wger.example/",
                refreshToken: "old-refresh"
            )
        )
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(result: .failure(.expiredSession)),
            connectionChecker: StubConnectionChecker(result: .success(3)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(
                    result: .success(
                        AuthenticationSession(
                            accessToken: "new-access",
                            refreshToken: "new-refresh"
                        )
                    )
                ),
                credentialStore: credentialStore
            )
        )

        await model.restoreSession()

        #expect(model.connectedAccount?.nutritionPlanCount == 3)
        #expect(model.instanceAddress == "https://wger.example/")
        #expect(model.errorMessage == nil)
        #expect(
            await credentialStore.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    refreshToken: "new-refresh"
                )
        )
    }

    @Test
    func rejectedRefreshClearsSavedSession() async throws {
        let credentialStore = InMemorySessionCredentialStore(
            session: StoredSession(
                instanceAddress: "https://wger.example/",
                refreshToken: "expired"
            )
        )
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(result: .failure(.expiredSession)),
            connectionChecker: StubConnectionChecker(result: .success(0)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(result: .failure(.expiredSession)),
                credentialStore: credentialStore
            )
        )

        await model.restoreSession()

        #expect(model.connectedAccount == nil)
        #expect(model.errorMessage == AuthenticationError.expiredSession.errorDescription)
        #expect(await credentialStore.session == nil)
    }

    @Test
    func transientRefreshFailureKeepsSavedSession() async throws {
        let storedSession = StoredSession(
            instanceAddress: "https://wger.example/",
            refreshToken: "refresh"
        )
        let credentialStore = InMemorySessionCredentialStore(session: storedSession)
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(result: .failure(.expiredSession)),
            connectionChecker: StubConnectionChecker(result: .success(0)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(result: .failure(.network)),
                credentialStore: credentialStore
            )
        )

        await model.restoreSession()

        #expect(model.connectedAccount == nil)
        #expect(model.errorMessage == AuthenticationError.network.errorDescription)
        #expect(await credentialStore.session == storedSession)
    }

    @Test
    func proofFailureKeepsRotatedCredential() async throws {
        let credentialStore = InMemorySessionCredentialStore(
            session: StoredSession(
                instanceAddress: "https://wger.example/",
                refreshToken: "old-refresh"
            )
        )
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(result: .failure(.expiredSession)),
            connectionChecker: StubConnectionChecker(result: .failure(.failed)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(
                    result: .success(
                        AuthenticationSession(
                            accessToken: "new-access",
                            refreshToken: "new-refresh"
                        )
                    )
                ),
                credentialStore: credentialStore
            )
        )

        await model.restoreSession()

        #expect(model.connectedAccount == nil)
        #expect(
            await credentialStore.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    refreshToken: "new-refresh"
                )
        )
    }
}

private nonisolated struct StubAuthenticationClient: AuthenticationClient {
    let result: Result<AuthenticationSession, AuthenticationError>

    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession {
        try result.get()
    }
}

private nonisolated struct StubSessionRefresher: SessionRefreshing {
    let result: Result<AuthenticationSession, AuthenticationError>

    func refresh(
        instance: InstanceURL,
        refreshToken: String
    ) async throws -> AuthenticationSession {
        try result.get()
    }
}

private nonisolated struct StubConnectionChecker: ConnectionChecking {
    let result: Result<Int, StubConnectionError>

    func nutritionPlanCount(
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> Int {
        try result.get()
    }
}

private actor InMemorySessionCredentialStore: SessionCredentialStoring {
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

private nonisolated enum StubConnectionError: Error {
    case failed
}
