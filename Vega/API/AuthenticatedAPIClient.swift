import Foundation
import WgerAPI

nonisolated protocol AuthenticatedRequestExecuting: Sendable {
    func perform<Value: Sendable>(
        _ operation: @Sendable (InstanceURL, AuthenticationSession) async throws -> Value
    ) async throws -> Value
}

actor AuthenticatedAPIClient: AuthenticatedRequestExecuting {
    private let sessionCoordinator: any SessionCoordinating

    init(sessionCoordinator: any SessionCoordinating) {
        self.sessionCoordinator = sessionCoordinator
    }

    func perform<Value: Sendable>(
        _ operation: @Sendable (InstanceURL, AuthenticationSession) async throws -> Value
    ) async throws -> Value {
        guard let session = await sessionCoordinator.current() else {
            throw SessionCoordinatorError.noSession
        }

        do {
            return try await operation(session.instance, session.credentials)
        } catch {
            guard isUnauthorized(error) else { throw error }
        }

        let refreshedSession = try await sessionCoordinator.refresh()
        return try await operation(
            refreshedSession.instance,
            refreshedSession.credentials
        )
    }

    private func isUnauthorized(_ error: Error) -> Bool {
        guard let apiError = error as? WgerAPIError else { return false }
        return apiError == .unexpectedStatus(401)
    }
}
