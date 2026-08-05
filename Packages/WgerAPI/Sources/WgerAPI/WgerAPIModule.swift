import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// Namespace for handwritten helpers around the generated wger API.
public enum WgerAPIModule {
    /// Creates a generated client that authenticates every request with a JWT.
    public static func authenticatedClient(
        serverURL: URL,
        accessToken: String
    ) -> Client {
        Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [BearerAuthenticationMiddleware(accessToken: accessToken)]
        )
    }

    /// Proves that a token is accepted by requesting one authenticated resource.
    public static func nutritionPlanCount(
        serverURL: URL,
        accessToken: String
    ) async throws -> Int {
        let client = authenticatedClient(serverURL: serverURL, accessToken: accessToken)
        let response = try await client.nutritionplanList(query: .init(limit: 1))

        switch response {
        case .ok(let response):
            return try response.body.json.count
        case .undocumented(let statusCode, _):
            throw WgerAPIError.unexpectedStatus(statusCode)
        }
    }
}

/// Injects a bearer token into requests made by the generated wger client.
public struct BearerAuthenticationMiddleware: ClientMiddleware {
    private let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }

    public func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next:
            @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (
                HTTPResponse, HTTPBody?
            )
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.authorization] = "Bearer \(accessToken)"
        return try await next(request, body, baseURL)
    }
}

public enum WgerAPIError: Error, Equatable, Sendable {
    case unexpectedStatus(Int)
}
