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
    func provesConnectionAndClearsSecrets() async throws {
        let model = SignInModel(
            authenticationClient: StubAuthenticationClient(
                result: .success(
                    AuthenticationSession(accessToken: "access", refreshToken: "refresh")
                )
            ),
            connectionChecker: StubConnectionChecker(result: .success(2))
        )
        model.instanceAddress = "wger.example"
        model.username = "test-user"
        model.password = "secret"

        await model.signIn()

        #expect(model.connectedAccount?.nutritionPlanCount == 2)
        #expect(model.password.isEmpty)
        #expect(model.errorMessage == nil)

        model.signOut()
        #expect(model.connectedAccount == nil)
    }
}

private struct StubAuthenticationClient: AuthenticationClient {
    let result: Result<AuthenticationSession, AuthenticationError>

    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession {
        try result.get()
    }
}

private struct StubConnectionChecker: ConnectionChecking {
    let result: Result<Int, StubConnectionError>

    func nutritionPlanCount(
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> Int {
        try result.get()
    }
}

private enum StubConnectionError: Error {
    case failed
}
