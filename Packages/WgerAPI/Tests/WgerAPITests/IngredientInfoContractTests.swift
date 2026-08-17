import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct IngredientInfoContractTests {
    @Test
    func decodesIngredientWithoutImage() async throws {
        let ingredient = try await ingredient(from: Self.ingredientWithoutImage)

        #expect(ingredient.name == "Fixture ingredient")
        #expect(ingredient.image == nil)
        #expect(ingredient.thumbnails == nil)
    }

    @Test
    func decodesTypedIngredientImageAndThumbnails() async throws {
        let ingredient = try await ingredient(from: Self.ingredientWithImage)

        #expect(ingredient.image?.value1.image == "https://wger.example/media/ingredient.png")
        #expect(ingredient.thumbnails?.value1.small == "https://wger.example/thumb-small.png")
        #expect(ingredient.thumbnails?.value1.medium == "https://wger.example/thumb-medium.png")
    }

    private func ingredient(from body: String) async throws -> Components.Schemas.IngredientInfo {
        let client = Client(
            serverURL: URL(string: "https://wger.example")!,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: IngredientFixtureTransport(body: body)
        )

        let response = try await client.ingredientinfoList(query: .init(limit: 1))
        let page: Components.Schemas.PaginatedIngredientInfoList
        switch response {
        case .ok(let response):
            page = try response.body.json
        case .undocumented(let statusCode, _):
            Issue.record("Unexpected response status: \(statusCode)")
            throw WgerAPIError.unexpectedStatus(statusCode)
        }

        return try #require(page.results.first)
    }

    private static let ingredientWithoutImage = #"""
        {
          "count": 1,
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
              "full_name": "English",
              "full_name_en": "English"
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

    private static let ingredientWithImage =
        ingredientWithoutImage
        .replacingOccurrences(
            of: #""image": null"#,
            with: #"""
                "image": {
                  "id": 10,
                  "uuid": "dc8297f7-5a20-4d6d-a8ee-e61c7962b544",
                  "ingredient_id": 1,
                  "ingredient_uuid": "7908c204-907f-4b1e-ad4e-f482e9769ade",
                  "image": "https://wger.example/media/ingredient.png",
                  "created": "2026-08-17T12:00:00Z",
                  "last_update": "2026-08-17T12:00:00Z",
                  "size": 1024,
                  "width": 640,
                  "height": 480
                }
                """#
        )
        .replacingOccurrences(
            of: #""thumbnails": null"#,
            with: #"""
                "thumbnails": {
                  "small": "https://wger.example/thumb-small.png",
                  "medium": "https://wger.example/thumb-medium.png"
                }
                """#
        )
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
