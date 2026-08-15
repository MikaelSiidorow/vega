import Foundation

nonisolated struct ActiveSession: Equatable, Sendable {
    let instance: InstanceURL
    let credentials: AuthenticationSession
}

nonisolated enum SessionCoordinatorError: Error, Equatable, Sendable {
    case noSession
}

nonisolated protocol SessionCoordinating: Sendable {
    func establish(instance: InstanceURL, credentials: AuthenticationSession) async throws
    func restore() async throws -> ActiveSession?
    func current() async -> ActiveSession?
    func refresh() async throws -> ActiveSession
    func clear() async throws
}

actor SessionCoordinator: SessionCoordinating {
    private let sessionRefresher: any SessionRefreshing
    private let credentialStore: any SessionCredentialStoring

    private var activeSession: ActiveSession?
    private var refreshTask: Task<ActiveSession, Error>?
    private var generation = 0

    init(
        sessionRefresher: any SessionRefreshing = AllauthClient(),
        credentialStore: any SessionCredentialStoring = KeychainSessionCredentialStore()
    ) {
        self.sessionRefresher = sessionRefresher
        self.credentialStore = credentialStore
    }

    func establish(instance: InstanceURL, credentials: AuthenticationSession) async throws {
        guard let refreshToken = credentials.refreshToken else {
            throw AuthenticationError.malformedResponse
        }

        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        try await credentialStore.save(
            StoredSession(
                instanceAddress: instance.url.absoluteString,
                accessToken: credentials.accessToken,
                refreshToken: refreshToken
            )
        )
        activeSession = ActiveSession(instance: instance, credentials: credentials)
    }

    func restore() async throws -> ActiveSession? {
        guard let storedSession = try await credentialStore.load() else { return nil }

        let instance: InstanceURL
        do {
            instance = try InstanceURL(storedSession.instanceAddress)
        } catch {
            try? await clear()
            throw error
        }

        if let accessToken = storedSession.accessToken {
            let restored = ActiveSession(
                instance: instance,
                credentials: AuthenticationSession(
                    accessToken: accessToken,
                    refreshToken: storedSession.refreshToken
                )
            )
            activeSession = restored
            return restored
        }

        return try await refresh(
            instance: instance,
            refreshToken: storedSession.refreshToken
        )
    }

    func current() -> ActiveSession? {
        activeSession
    }

    func refresh() async throws -> ActiveSession {
        guard let activeSession, let refreshToken = activeSession.credentials.refreshToken else {
            throw SessionCoordinatorError.noSession
        }
        return try await refresh(instance: activeSession.instance, refreshToken: refreshToken)
    }

    func clear() async throws {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        activeSession = nil
        try await credentialStore.clear()
    }

    private func refresh(
        instance: InstanceURL,
        refreshToken: String
    ) async throws -> ActiveSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        let taskGeneration = generation
        let sessionRefresher = sessionRefresher
        let credentialStore = credentialStore
        let task = Task {
            let credentials = try await sessionRefresher.refresh(
                instance: instance,
                refreshToken: refreshToken
            )
            try Task.checkCancellation()
            guard let rotatedRefreshToken = credentials.refreshToken else {
                throw AuthenticationError.malformedResponse
            }
            try await credentialStore.save(
                StoredSession(
                    instanceAddress: instance.url.absoluteString,
                    accessToken: credentials.accessToken,
                    refreshToken: rotatedRefreshToken
                )
            )
            try Task.checkCancellation()
            return ActiveSession(instance: instance, credentials: credentials)
        }
        refreshTask = task

        do {
            let refreshedSession = try await task.value
            guard generation == taskGeneration else { throw CancellationError() }
            activeSession = refreshedSession
            refreshTask = nil
            return refreshedSession
        } catch {
            if generation == taskGeneration {
                refreshTask = nil
                if error as? AuthenticationError == .expiredSession {
                    try? await clear()
                }
            }
            throw error
        }
    }
}
