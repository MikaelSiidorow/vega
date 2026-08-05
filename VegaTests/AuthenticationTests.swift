import Foundation
import Testing

@testable import Vega

struct AuthenticationTests {
    @Test
    func normalizesInstanceAndDecodesSuccessfulLogin() async throws {
        let recorder = RequestRecorder()
        let client = AllauthClient(
            transport: StubHTTPTransport { request in
                await recorder.record(request)
                return try response(
                    status: 200,
                    body: #"{"meta":{"access_token":"access","refresh_token":"refresh"}}"#
                )
            }
        )

        let instance = try InstanceURL("  wger.example/  ")
        let session = try await client.signIn(
            instance: instance,
            username: "test-user",
            password: "secret"
        )

        #expect(instance.url.absoluteString == "https://wger.example/")
        #expect(session == AuthenticationSession(accessToken: "access", refreshToken: "refresh"))

        let request = try #require(await recorder.request)
        #expect(request.url?.absoluteString == "https://wger.example/allauth/app/v1/auth/login")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(payload?["username"] == "test-user")
        #expect(payload?["password"] == "secret")
    }

    @Test
    func rejectsNonHTTPSInstances() {
        #expect(throws: AuthenticationError.invalidInstanceURL) {
            try InstanceURL("http://wger.example")
        }
    }

    @Test
    func reportsInvalidCredentials() async throws {
        let client = AllauthClient(
            transport: StubHTTPTransport { _ in
                try response(
                    status: 401,
                    body: #"{"errors":[{"message":"Invalid credentials."}]}"#
                )
            }
        )

        await #expect(throws: AuthenticationError.invalidCredentials("Invalid credentials.")) {
            try await client.signIn(
                instance: InstanceURL("https://wger.example"),
                username: "test-user",
                password: "wrong"
            )
        }
    }

    @Test
    func reportsPendingMFAChallenge() async throws {
        let client = AllauthClient(
            transport: StubHTTPTransport { _ in
                try response(
                    status: 401,
                    body:
                        #"{"data":{"flows":[{"id":"mfa_authenticate","types":["totp","recovery_codes"],"is_pending":true}]},"meta":{"session_token":"mfa-session"}}"#
                )
            }
        )

        await #expect(
            throws: AuthenticationError.mfaRequired(
                MFAChallenge(
                    sessionToken: "mfa-session",
                    methods: ["totp", "recovery_codes"]
                )
            )
        ) {
            try await client.signIn(
                instance: InstanceURL("https://wger.example"),
                username: "test-user",
                password: "secret"
            )
        }
    }

    @Test
    func reportsRateLimitRetryAfter() async throws {
        let client = AllauthClient(
            transport: StubHTTPTransport { _ in
                try response(status: 429, headers: ["Retry-After": "60"])
            }
        )

        await #expect(throws: AuthenticationError.rateLimited(retryAfter: "60")) {
            try await client.signIn(
                instance: InstanceURL("https://wger.example"),
                username: "test-user",
                password: "secret"
            )
        }
    }

    @Test
    func rejectsSuccessfulResponseWithoutAccessToken() async throws {
        let client = AllauthClient(
            transport: StubHTTPTransport { _ in
                try response(status: 200, body: #"{"meta":{}}"#)
            }
        )

        await #expect(throws: AuthenticationError.malformedResponse) {
            try await client.signIn(
                instance: InstanceURL("https://wger.example"),
                username: "test-user",
                password: "secret"
            )
        }
    }
}

private struct StubHTTPTransport: HTTPTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

private func response(
    status: Int,
    headers: [String: String] = [:],
    body: String = ""
) throws -> (Data, HTTPURLResponse) {
    let response = try #require(
        HTTPURLResponse(
            url: URL(string: "https://wger.example")!,
            statusCode: status,
            httpVersion: nil,
            headerFields: headers
        )
    )
    return (Data(body.utf8), response)
}
