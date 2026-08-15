import Foundation

#if canImport(Security)
    import Security
#endif

nonisolated struct StoredSession: Equatable, Sendable {
    let instanceAddress: String
    let accessToken: String?
    let refreshToken: String

    init(instanceAddress: String, accessToken: String? = nil, refreshToken: String) {
        self.instanceAddress = instanceAddress
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

nonisolated enum SessionPersistenceError: Error, Equatable, Sendable {
    case unavailable
    case keychain(Int32)
}

extension SessionPersistenceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Secure session storage is unavailable on this device."
        case .keychain:
            return "Vega could not access the saved session securely."
        }
    }
}

nonisolated protocol SessionCredentialStoring: Sendable {
    func load() async throws -> StoredSession?
    func save(_ session: StoredSession) async throws
    func clear() async throws
}

#if canImport(Security)
    actor KeychainSessionCredentialStore: SessionCredentialStoring {
        private struct StoredCredentials: Codable {
            let accessToken: String?
            let refreshToken: String
        }

        private let service: String
        private let account: String
        private let instanceAddressKey: String
        private let defaults: UserDefaults

        init(
            service: String = Bundle.main.bundleIdentifier ?? "Vega",
            account: String = "refresh-token",
            instanceAddressKey: String = "session.instance-address",
            defaults: UserDefaults = .standard
        ) {
            self.service = service
            self.account = account
            self.instanceAddressKey = instanceAddressKey
            self.defaults = defaults
        }

        func load() throws -> StoredSession? {
            let instanceAddress = defaults.string(forKey: instanceAddressKey)
            let credentials = try readCredentials()

            guard let instanceAddress, let credentials else {
                if instanceAddress != nil || credentials != nil {
                    try clear()
                }
                return nil
            }

            return StoredSession(
                instanceAddress: instanceAddress,
                accessToken: credentials.accessToken,
                refreshToken: credentials.refreshToken
            )
        }

        func save(_ session: StoredSession) throws {
            try writeCredentials(
                StoredCredentials(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken
                )
            )
            defaults.set(session.instanceAddress, forKey: instanceAddressKey)
        }

        func clear() throws {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SessionPersistenceError.keychain(status)
            }
            defaults.removeObject(forKey: instanceAddressKey)
        }

        private var baseQuery: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
        }

        private func readCredentials() throws -> StoredCredentials? {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound {
                return nil
            }
            guard status == errSecSuccess, let data = result as? Data else {
                throw SessionPersistenceError.keychain(status)
            }
            if let credentials = try? JSONDecoder().decode(StoredCredentials.self, from: data) {
                return credentials
            }
            guard let legacyRefreshToken = String(data: data, encoding: .utf8) else {
                throw SessionPersistenceError.keychain(errSecDecode)
            }
            return StoredCredentials(accessToken: nil, refreshToken: legacyRefreshToken)
        }

        private func writeCredentials(_ credentials: StoredCredentials) throws {
            let data = try JSONEncoder().encode(credentials)
            let updateStatus = SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )

            if updateStatus == errSecSuccess {
                return
            }
            guard updateStatus == errSecItemNotFound else {
                throw SessionPersistenceError.keychain(updateStatus)
            }

            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SessionPersistenceError.keychain(addStatus)
            }
        }
    }
#else
    actor KeychainSessionCredentialStore: SessionCredentialStoring {
        func load() throws -> StoredSession? {
            throw SessionPersistenceError.unavailable
        }

        func save(_ session: StoredSession) throws {
            throw SessionPersistenceError.unavailable
        }

        func clear() throws {
            throw SessionPersistenceError.unavailable
        }
    }
#endif
