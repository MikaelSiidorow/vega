import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct PowerSyncContractTests {
    @Test
    func decodesTypedCredentials() async throws {
        let recorder = PowerSyncRequestRecorder()
        let client = fixtureClient(
            recorder: recorder,
            response: #"{"token":"signed-token","powersync_url":"https://sync.example"}"#
        )

        let credentials = try await WgerAPIModule.powerSyncCredentials(client: client)

        #expect(credentials == .init(token: "signed-token", endpoint: "https://sync.example"))
        #expect(await recorder.requests.map(\.method) == ["GET"])
    }

    @Test(arguments: [
        WgerPowerSyncUploadMethod.put,
        .patch,
        .delete,
    ])
    func sendsTypedUploadEnvelope(method: WgerPowerSyncUploadMethod) async throws {
        let recorder = PowerSyncRequestRecorder()
        let client = fixtureClient(recorder: recorder, response: #"{"status":"ok"}"#)
        let request = Components.Schemas.PowersyncUploadRequest(
            table: "weight_weightentry",
            data: try .init(
                unvalidatedValue: [
                    "id": "weight-1" as any Sendable,
                    "weight": 79.5 as any Sendable,
                ]
            )
        )

        let result = try await WgerAPIModule.uploadPowerSyncData(
            client: client,
            method: method,
            request: request
        )

        #expect(result == .init(statusCode: 200))
        let captured = try #require(await recorder.requests.first)
        #expect(captured.method == method.rawValue)
        let object = try #require(
            JSONSerialization.jsonObject(with: captured.body) as? [String: Any]
        )
        #expect(object["table"] as? String == "weight_weightentry")
        let data = try #require(object["data"] as? [String: Any])
        #expect(data["id"] as? String == "weight-1")
        #expect(data["weight"] as? Double == 79.5)
    }

    @Test
    func decodesTypedUploadRejection() async throws {
        let client = fixtureClient(
            recorder: PowerSyncRequestRecorder(),
            response: #"{"error":"invalid data","details":"weight is required"}"#
        )
        let request = Components.Schemas.PowersyncUploadRequest(
            table: "weight_weightentry",
            data: try .init(unvalidatedValue: ["id": "weight-1" as any Sendable])
        )

        let result = try await WgerAPIModule.uploadPowerSyncData(
            client: client,
            method: .put,
            request: request
        )

        #expect(
            result
                == .init(
                    statusCode: 200,
                    error: "invalid data",
                    details: "weight is required"
                )
        )
    }

    private func fixtureClient(
        recorder: PowerSyncRequestRecorder,
        response: String
    ) -> Client {
        Client(
            serverURL: URL(string: "https://wger.example")!,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: PowerSyncFixtureTransport(recorder: recorder, response: response)
        )
    }
}

private struct CapturedPowerSyncRequest: Sendable {
    let method: String
    let body: Data
}

private actor PowerSyncRequestRecorder {
    private(set) var requests: [CapturedPowerSyncRequest] = []

    func record(_ request: CapturedPowerSyncRequest) {
        requests.append(request)
    }
}

private struct PowerSyncFixtureTransport: ClientTransport {
    let recorder: PowerSyncRequestRecorder
    let response: String

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let data: Data
        if let body {
            data = try await Data(collecting: body, upTo: 1_048_576)
        } else {
            data = Data()
        }
        await recorder.record(
            .init(method: request.method.rawValue, body: data)
        )
        return (
            HTTPResponse(
                status: .ok,
                headerFields: [.contentType: "application/json"]
            ),
            HTTPBody(response)
        )
    }
}
