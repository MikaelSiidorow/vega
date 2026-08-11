import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

nonisolated struct InstanceURL: Equatable, Sendable {
    let url: URL

    init(_ address: String) throws {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else {
            throw AuthenticationError.invalidInstanceURL
        }

        let addressWithScheme =
            trimmedAddress.contains("://")
            ? trimmedAddress : "https://\(trimmedAddress)"
        guard var components = URLComponents(string: addressWithScheme),
            components.scheme?.lowercased() == "https",
            components.host?.isEmpty == false,
            components.user == nil,
            components.password == nil,
            components.query == nil,
            components.fragment == nil
        else {
            throw AuthenticationError.invalidInstanceURL
        }

        components.scheme = "https"
        if components.path.isEmpty {
            components.path = "/"
        } else {
            while components.path.count > 1 && components.path.hasSuffix("/") {
                components.path.removeLast()
            }
        }

        guard let normalizedURL = components.url else {
            throw AuthenticationError.invalidInstanceURL
        }
        url = normalizedURL
    }

    func appending(path: String) -> URL {
        url.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}

nonisolated struct AuthenticationSession: Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
}

nonisolated struct MFAChallenge: Equatable, Sendable {
    let sessionToken: String
    let methods: [String]
}

nonisolated enum AuthenticationError: Error, Equatable, Sendable {
    case invalidInstanceURL
    case invalidCredentials(String?)
    case mfaRequired(MFAChallenge)
    case invalidMFACode(String?)
    case expiredMFAChallenge
    case rateLimited(retryAfter: String?)
    case malformedResponse
    case expiredSession
    case unexpectedStatus(Int, String?)
    case network
}

extension AuthenticationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidInstanceURL:
            return "Enter a valid HTTPS address for your wger instance."
        case .invalidCredentials(let message):
            return message ?? "The username or password was not accepted."
        case .mfaRequired:
            return "Enter a code to finish signing in."
        case .invalidMFACode(let message):
            return message ?? "The verification code was not accepted."
        case .expiredMFAChallenge:
            return "This verification attempt has expired. Sign in again."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Too many sign-in attempts. Try again after \(retryAfter)."
            }
            return "Too many sign-in attempts. Please wait and try again."
        case .malformedResponse:
            return "The server returned an unexpected sign-in response."
        case .expiredSession:
            return "Your saved session has expired. Sign in again."
        case .unexpectedStatus(_, let message):
            return message ?? "The server could not complete sign-in."
        case .network:
            return "Could not reach the wger instance. Check the address and your connection."
        }
    }
}

nonisolated protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

nonisolated struct URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw AuthenticationError.malformedResponse
        }
        return (data, response)
    }
}

nonisolated protocol AuthenticationClient: Sendable {
    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession

    func completeMFA(
        instance: InstanceURL,
        challenge: MFAChallenge,
        code: String
    ) async throws -> AuthenticationSession
}

nonisolated protocol SessionRefreshing: Sendable {
    func refresh(
        instance: InstanceURL,
        refreshToken: String
    ) async throws -> AuthenticationSession
}

nonisolated struct AllauthClient: AuthenticationClient, SessionRefreshing {
    private let transport: any HTTPTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(transport: any HTTPTransport = URLSessionHTTPTransport()) {
        self.transport = transport
    }

    func signIn(
        instance: InstanceURL,
        username: String,
        password: String
    ) async throws -> AuthenticationSession {
        var request = URLRequest(url: instance.appending(path: "allauth/app/v1/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(LoginRequest(username: username, password: password))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.network
        }

        let envelope = try? decoder.decode(LoginEnvelope.self, from: data)
        switch response.statusCode {
        case 200...299:
            guard let accessToken = envelope?.meta?.accessToken, !accessToken.isEmpty else {
                throw AuthenticationError.malformedResponse
            }
            return AuthenticationSession(
                accessToken: accessToken,
                refreshToken: envelope?.meta?.refreshToken
            )
        case 401:
            if let challenge = envelope?.mfaChallenge {
                throw AuthenticationError.mfaRequired(challenge)
            }
            throw AuthenticationError.invalidCredentials(envelope?.firstErrorMessage)
        case 429:
            throw AuthenticationError.rateLimited(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
            )
        default:
            throw AuthenticationError.unexpectedStatus(
                response.statusCode,
                envelope?.firstErrorMessage
            )
        }
    }

    func completeMFA(
        instance: InstanceURL,
        challenge: MFAChallenge,
        code: String
    ) async throws -> AuthenticationSession {
        var request = URLRequest(
            url: instance.appending(path: "allauth/app/v1/auth/2fa/authenticate")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(challenge.sessionToken, forHTTPHeaderField: "X-Session-Token")
        request.httpBody = try encoder.encode(MFARequest(code: code))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.network
        }

        let envelope = try? decoder.decode(LoginEnvelope.self, from: data)
        switch response.statusCode {
        case 200...299:
            guard let accessToken = envelope?.meta?.accessToken, !accessToken.isEmpty else {
                throw AuthenticationError.malformedResponse
            }
            return AuthenticationSession(
                accessToken: accessToken,
                refreshToken: envelope?.meta?.refreshToken
            )
        case 400:
            throw AuthenticationError.invalidMFACode(envelope?.firstErrorMessage)
        case 401:
            throw AuthenticationError.expiredMFAChallenge
        case 429:
            throw AuthenticationError.rateLimited(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
            )
        default:
            throw AuthenticationError.unexpectedStatus(
                response.statusCode,
                envelope?.firstErrorMessage
            )
        }
    }

    func refresh(
        instance: InstanceURL,
        refreshToken: String
    ) async throws -> AuthenticationSession {
        var request = URLRequest(url: instance.appending(path: "allauth/app/v1/tokens/refresh"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch let error as AuthenticationError {
            throw error
        } catch {
            throw AuthenticationError.network
        }

        let envelope = try? decoder.decode(RefreshEnvelope.self, from: data)
        switch response.statusCode {
        case 200...299:
            guard let accessToken = envelope?.data.accessToken,
                let refreshToken = envelope?.data.refreshToken,
                !accessToken.isEmpty,
                !refreshToken.isEmpty
            else {
                throw AuthenticationError.malformedResponse
            }
            return AuthenticationSession(
                accessToken: accessToken,
                refreshToken: refreshToken
            )
        case 401:
            throw AuthenticationError.expiredSession
        case 429:
            throw AuthenticationError.rateLimited(
                retryAfter: response.value(forHTTPHeaderField: "Retry-After")
            )
        default:
            throw AuthenticationError.unexpectedStatus(
                response.statusCode,
                envelope?.firstErrorMessage
            )
        }
    }
}

private nonisolated struct LoginRequest: Encodable {
    let username: String
    let password: String
}

private nonisolated struct MFARequest: Encodable {
    let code: String
}

private nonisolated struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

private nonisolated struct RefreshEnvelope: Decodable {
    struct DataPayload: Decodable {
        let accessToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    struct APIError: Decodable {
        let message: String?
    }

    let data: DataPayload
    let errors: [APIError]?

    var firstErrorMessage: String? {
        errors?.compactMap(\.message).first
    }
}

private nonisolated struct LoginEnvelope: Decodable {
    struct Meta: Decodable {
        let accessToken: String?
        let refreshToken: String?
        let sessionToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case sessionToken = "session_token"
        }
    }

    struct DataPayload: Decodable {
        let flows: [Flow]?
    }

    struct Flow: Decodable {
        let id: String
        let types: [String]?
        let isPending: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case types
            case isPending = "is_pending"
        }
    }

    struct APIError: Decodable {
        let message: String?
    }

    let data: DataPayload?
    let meta: Meta?
    let errors: [APIError]?

    var firstErrorMessage: String? {
        errors?.compactMap(\.message).first
    }

    var mfaChallenge: MFAChallenge? {
        guard let sessionToken = meta?.sessionToken,
            let flow = data?.flows?.first(where: {
                $0.id == "mfa_authenticate" && $0.isPending != false
            })
        else {
            return nil
        }
        return MFAChallenge(sessionToken: sessionToken, methods: flow.types ?? [])
    }
}
