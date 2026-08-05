import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct BearerAuthenticationMiddlewareTests {
    @Test
    func addsBearerTokenToGeneratedClientRequests() async throws {
        let middleware = BearerAuthenticationMiddleware(accessToken: "access-token")
        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v2/")

        _ = try await middleware.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://wger.example")!,
            operationID: "test"
        ) { request, _, _ in
            #expect(request.headerFields[.authorization] == "Bearer access-token")
            return (HTTPResponse(status: .ok), nil)
        }
    }
}
