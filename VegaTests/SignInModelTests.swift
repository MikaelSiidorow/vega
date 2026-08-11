import Foundation
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
    func acceptsAPreviouslyUsedInstanceAddress() {
        let model = SignInModel(instanceAddress: "https://wger.example/")

        #expect(model.instanceAddress == "https://wger.example/")
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
    func completesMFAAndPersistsSession() async throws {
        let challenge = MFAChallenge(
            sessionToken: "mfa-session",
            methods: ["totp", "recovery_codes"]
        )
        let credentialStore = InMemorySessionCredentialStore()
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(
                result: .failure(.mfaRequired(challenge)),
                mfaResult: .success(
                    AuthenticationSession(accessToken: "access", refreshToken: "refresh")
                )
            ),
            connectionChecker: StubConnectionChecker(result: .success(1)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(result: .failure(.expiredSession)),
                credentialStore: credentialStore
            )
        )
        model.instanceAddress = "wger.example"
        model.username = "test-user"
        model.password = "secret"

        await model.signIn()

        #expect(model.pendingMFAChallenge == challenge)
        #expect(model.password.isEmpty)
        #expect(model.connectedAccount == nil)

        model.mfaCode = "123456"
        await model.verifyMFA()

        #expect(model.pendingMFAChallenge == nil)
        #expect(model.mfaCode.isEmpty)
        #expect(model.connectedAccount?.nutritionPlanCount == 1)
        #expect(
            await credentialStore.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    refreshToken: "refresh"
                )
        )
    }

    @Test
    func rejectedMFACodeKeepsChallengeOpen() async {
        let challenge = MFAChallenge(sessionToken: "mfa-session", methods: ["totp"])
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(
                result: .failure(.mfaRequired(challenge)),
                mfaResult: .failure(.invalidMFACode("Incorrect code."))
            )
        )
        model.instanceAddress = "wger.example"
        model.username = "test-user"
        model.password = "secret"

        await model.signIn()
        model.mfaCode = "000000"
        await model.verifyMFA()

        #expect(model.pendingMFAChallenge == challenge)
        #expect(model.errorMessage == "Incorrect code.")
    }

    @Test
    func completesWebSignInFromValidatedCallback() async throws {
        let credentialStore = InMemorySessionCredentialStore()
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(result: .failure(.expiredSession)),
            webSessionRefresher: StubSessionRefresher(
                result: .success(
                    AuthenticationSession(accessToken: "access", refreshToken: "rotated")
                )
            ),
            connectionChecker: StubConnectionChecker(result: .success(1)),
            sessionCoordinator: SessionCoordinator(
                sessionRefresher: StubSessionRefresher(result: .failure(.expiredSession)),
                credentialStore: credentialStore
            )
        )
        model.instanceAddress = "wger.example"
        let request = try model.makeWebAuthenticationRequest()
        let callback = try #require(
            URL(string: "wger://app-auth#token=issued-refresh&state=\(request.state)")
        )

        await model.completeWebSignIn(request: request, callbackURL: callback)

        #expect(model.connectedAccount?.nutritionPlanCount == 1)
        #expect(model.errorMessage == nil)
        #expect(
            await credentialStore.session
                == StoredSession(
                    instanceAddress: "https://wger.example/",
                    refreshToken: "rotated"
                )
        )
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
    let mfaResult: Result<AuthenticationSession, AuthenticationError>?

    init(
        result: Result<AuthenticationSession, AuthenticationError>,
        mfaResult: Result<AuthenticationSession, AuthenticationError>? = nil
    ) {
        self.result = result
        self.mfaResult = mfaResult
    }

    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession {
        try result.get()
    }

    func completeMFA(
        instance: InstanceURL,
        challenge: MFAChallenge,
        code: String
    ) async throws -> AuthenticationSession {
        try (mfaResult ?? result).get()
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
