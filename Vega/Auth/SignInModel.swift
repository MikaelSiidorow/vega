import Foundation
import Observation
import WgerAPI

protocol ConnectionChecking: Sendable {
    func nutritionPlanCount(
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> Int
}

struct WgerConnectionChecker: ConnectionChecking {
    func nutritionPlanCount(
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> Int {
        try await WgerAPIModule.nutritionPlanCount(
            serverURL: instance.url,
            accessToken: session.accessToken
        )
    }
}

struct ConnectedAccount: Equatable, Sendable {
    let instance: InstanceURL
    let nutritionPlanCount: Int
}

@MainActor
@Observable
final class SignInModel {
    var instanceAddress = "https://wger.de"
    var username = ""
    var password = ""

    private(set) var connectedAccount: ConnectedAccount?
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let authenticationClient: any AuthenticationClient
    private let connectionChecker: any ConnectionChecking
    private var session: AuthenticationSession?

    init(
        authenticationClient: any AuthenticationClient = AllauthClient(),
        connectionChecker: any ConnectionChecking = WgerConnectionChecker()
    ) {
        self.authenticationClient = authenticationClient
        self.connectionChecker = connectionChecker
    }

    var canSignIn: Bool {
        !isSigningIn
            && !instanceAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    func signIn() async {
        guard canSignIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let instance = try InstanceURL(instanceAddress)
            let session = try await authenticationClient.signIn(
                instance: instance,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            let planCount = try await connectionChecker.nutritionPlanCount(
                instance: instance,
                session: session
            )

            self.session = session
            connectedAccount = ConnectedAccount(
                instance: instance,
                nutritionPlanCount: planCount
            )
            password = ""
        } catch {
            session = nil
            connectedAccount = nil
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Sign-in failed. Please try again."
        }
    }

    func signOut() {
        session = nil
        connectedAccount = nil
        password = ""
        errorMessage = nil
    }
}
