import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct IngredientInfoContractTests {
    @Test
    func decodesIngredientWithoutImage() async throws {
        let client = Client(
            serverURL: URL(string: "https://wger.example")!,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: IngredientFixtureTransport(body: Self.ingredientWithoutImage)
        )

        let response = try await client.ingredientinfoList(query: .init(limit: 1))
        let page: Components.Schemas.PaginatedIngredientInfoList
        switch response {
        case .ok(let response):
            page = try response.body.json
        case .undocumented(let statusCode, _):
            Issue.record("Unexpected response status: \(statusCode)")
            return
        }

        let ingredient = try #require(page.results.first)
        #expect(ingredient.name == "Fixture ingredient")
        #expect(ingredient.image == nil)
        #expect(ingredient.thumbnails == nil)
    }

    private static let ingredientWithoutImage = #"""
        {
          "next": null,
          "previous": null,
          "results": [{
            "id": 1,
            "uuid": "7908c204-907f-4b1e-ad4e-f482e9769ade",
            "name": "Fixture ingredient",
            "created": "2013-04-14T02:00:00+02:00",
            "last_update": "2025-11-17T15:35:10.208163+01:00",
            "last_imported": null,
            "energy": 100,
            "protein": "10.000",
            "carbohydrates": "20.000",
            "fat": "5.000",
            "weight_units": [],
            "language": {
              "id": 2,
              "short_name": "en",
              "full_name": "English"
            },
            "license": {
              "id": 1,
              "short_name": "CC-BY-SA 3",
              "full_name": "Creative Commons Attribution Share Alike 3"
            },
            "image": null,
            "thumbnails": null
          }]
        }
        """#
}

private struct IngredientFixtureTransport: ClientTransport {
    let body: String

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        (
            HTTPResponse(
                status: .ok,
                headerFields: [.contentType: "application/json"]
            ),
            HTTPBody(self.body)
        )
    }
}
