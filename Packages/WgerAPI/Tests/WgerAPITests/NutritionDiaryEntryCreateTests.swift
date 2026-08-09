import Foundation
import Testing

@testable import WgerAPI

struct NutritionDiaryEntryCreateTests {
    @Test
    func encodesServerFieldNamesAndExplicitNulls() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-08-05T12:30:00Z"))
        let entry = NutritionDiaryEntryCreate(
            plan: "plan-id",
            ingredient: 42,
            amount: "150",
            weightUnit: nil,
            datetime: date,
            meal: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["plan"] as? String == "plan-id")
        #expect(json["ingredient"] as? Int == 42)
        #expect(json["amount"] as? String == "150")
        #expect(json["weight_unit"] is NSNull)
        #expect(json["datetime"] as? String == "2026-08-05T12:30:00Z")
        #expect(json["meal"] is NSNull)
    }
}
