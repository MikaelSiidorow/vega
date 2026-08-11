import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct NutritionPlanValuesContractTests {
    @Test
    func decodesNutritionalValuesFromPlanAction() async throws {
        let client = Client(
            serverURL: URL(string: "https://wger.example")!,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: NutritionPlanValuesFixtureTransport()
        )

        let response = try await client.nutritionplanNutritionalValuesRetrieve(
            path: .init(id: "00000000-0000-0000-0000-000000000001")
        )
        let values: Components.Schemas.NutritionalValues
        switch response {
        case .ok(let response):
            values = try response.body.json
        case .undocumented(let statusCode, _):
            Issue.record("Unexpected response status: \(statusCode)")
            return
        }

        #expect(values.energy == 2_150)
        #expect(values.protein == 130)
        #expect(values.carbohydrates == 240)
        #expect(values.fat == 70)
    }
}

private struct NutritionPlanValuesFixtureTransport: ClientTransport {
    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(operationID == "nutritionplan_nutritional_values_retrieve")
        #expect(
            request.path
                == "/api/v2/nutritionplan/00000000-0000-0000-0000-000000000001/nutritional_values/"
        )
        return (
            HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
            HTTPBody(Self.body)
        )
    }

    private static let body = #"""
        {
          "energy": 2150,
          "protein": 130,
          "carbohydrates": 240,
          "carbohydrates_sugar": 45,
          "fat": 70,
          "fat_saturated": 20,
          "fiber": 32,
          "sodium": 2.1
        }
        """#
}
