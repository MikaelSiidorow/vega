import Foundation
import Observation
import WgerAPI

nonisolated protocol ConnectionChecking: Sendable {
    func nutritionPlanCount(
        instance: InstanceURL,
        session: AuthenticationSession
    ) async throws -> Int
}

nonisolated struct WgerConnectionChecker: ConnectionChecking {
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

nonisolated struct ConnectedAccount: Equatable, Sendable {
    let instance: InstanceURL
    let nutritionPlanCount: Int
}

@MainActor
@Observable
final class SignInModel {
    var instanceAddress = "https://wger.de"
    var username = ""
    var password = ""
    var mfaCode = ""

    private(set) var connectedAccount: ConnectedAccount?
    private(set) var pendingMFAChallenge: MFAChallenge?
    private(set) var isSigningIn = false
    private(set) var isVerifyingMFA = false
    private(set) var isRestoringSession = false
    private(set) var errorMessage: String?

    private let authenticationClient: any AuthenticationClient
    private let webSessionRefresher: any SessionRefreshing
    private let connectionChecker: any ConnectionChecking
    private let sessionCoordinator: any SessionCoordinating
    private var session: AuthenticationSession?
    private var pendingMFAInstance: InstanceURL?
    private var hasAttemptedRestore = false

    init(
        authenticationClient: any AuthenticationClient = AllauthClient(),
        webSessionRefresher: any SessionRefreshing = AllauthClient(),
        connectionChecker: any ConnectionChecking = WgerConnectionChecker(),
        sessionCoordinator: any SessionCoordinating = SessionCoordinator()
    ) {
        self.authenticationClient = authenticationClient
        self.webSessionRefresher = webSessionRefresher
        self.connectionChecker = connectionChecker
        self.sessionCoordinator = sessionCoordinator
    }

    var canSignIn: Bool {
        !isSigningIn
            && !isRestoringSession
            && !instanceAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var canVerifyMFA: Bool {
        pendingMFAChallenge != nil
            && pendingMFAInstance != nil
            && !isVerifyingMFA
            && !mfaCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            try await establish(session: session, instance: instance)
        } catch AuthenticationError.mfaRequired(let challenge) {
            pendingMFAChallenge = challenge
            pendingMFAInstance = try? InstanceURL(instanceAddress)
            password = ""
        } catch {
            session = nil
            connectedAccount = nil
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Sign-in failed. Please try again."
        }
    }

    func verifyMFA() async {
        guard canVerifyMFA,
            let challenge = pendingMFAChallenge,
            let instance = pendingMFAInstance
        else { return }

        isVerifyingMFA = true
        errorMessage = nil
        defer { isVerifyingMFA = false }

        do {
            let session = try await authenticationClient.completeMFA(
                instance: instance,
                challenge: challenge,
                code: mfaCode.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await establish(session: session, instance: instance)
        } catch AuthenticationError.expiredMFAChallenge {
            cancelMFA()
            errorMessage = AuthenticationError.expiredMFAChallenge.errorDescription
        } catch {
            session = nil
            connectedAccount = nil
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Verification failed. Please try again."
        }
    }

    func cancelMFA() {
        pendingMFAChallenge = nil
        pendingMFAInstance = nil
        mfaCode = ""
        errorMessage = nil
    }

    func makeWebAuthenticationRequest() throws -> WebAuthenticationRequest {
        errorMessage = nil
        return WebAuthenticationHandoff.makeRequest(instance: try InstanceURL(instanceAddress))
    }

    func completeWebSignIn(
        request: WebAuthenticationRequest,
        callbackURL: URL
    ) async {
        guard !isSigningIn else { return }

        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            let refreshToken = try WebAuthenticationHandoff.refreshToken(
                from: callbackURL,
                expectedState: request.state
            )
            let session = try await webSessionRefresher.refresh(
                instance: request.instance,
                refreshToken: refreshToken
            )
            try await establish(session: session, instance: request.instance)
        } catch {
            session = nil
            connectedAccount = nil
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Web sign-in failed. Please try again."
        }
    }

    func reportWebSignInFailure(_ error: Error) {
        errorMessage =
            (error as? LocalizedError)?.errorDescription
            ?? "Web sign-in failed. Please try again."
    }

    func restoreSession() async {
        guard !hasAttemptedRestore, connectedAccount == nil, !isSigningIn else { return }

        hasAttemptedRestore = true
        isRestoringSession = true
        errorMessage = nil
        defer { isRestoringSession = false }

        do {
            guard let activeSession = try await sessionCoordinator.restore() else { return }
            let instance = activeSession.instance
            let refreshedSession = activeSession.credentials
            let planCount = try await connectionChecker.nutritionPlanCount(
                instance: instance,
                session: refreshedSession
            )

            session = refreshedSession
            connectedAccount = ConnectedAccount(
                instance: instance,
                nutritionPlanCount: planCount
            )
            instanceAddress = instance.url.absoluteString
        } catch AuthenticationError.expiredSession {
            session = nil
            connectedAccount = nil
            errorMessage = AuthenticationError.expiredSession.errorDescription
        } catch AuthenticationError.invalidInstanceURL {
            session = nil
            connectedAccount = nil
            errorMessage = AuthenticationError.invalidInstanceURL.errorDescription
        } catch {
            session = nil
            connectedAccount = nil
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Session restoration failed. Please try again."
        }
    }

    func signOut() async {
        session = nil
        connectedAccount = nil
        password = ""
        errorMessage = nil
        do {
            try await sessionCoordinator.clear()
        } catch {
            errorMessage =
                (error as? LocalizedError)?.errorDescription
                ?? "Vega could not clear the saved session."
        }
    }
    private func establish(session: AuthenticationSession, instance: InstanceURL) async throws {
        let planCount = try await connectionChecker.nutritionPlanCount(
            instance: instance,
            session: session
        )
        try await sessionCoordinator.establish(instance: instance, credentials: session)

        self.session = session
        connectedAccount = ConnectedAccount(
            instance: instance,
            nutritionPlanCount: planCount
        )
        pendingMFAChallenge = nil
        pendingMFAInstance = nil
        password = ""
        mfaCode = ""
    }
}
