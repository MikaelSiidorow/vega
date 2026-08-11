import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import WgerAPI

struct WorkoutDayPlanContractTests {
    @Test
    func decodesResolvedGymSequence() async throws {
        let client = Client(
            serverURL: URL(string: "https://wger.example")!,
            configuration: .init(dateTranscoder: WgerDateTranscoder()),
            transport: WorkoutDayPlanFixtureTransport()
        )

        let response = try await client.routineDateSequenceGymRetrieve(path: .init(id: 42))
        let days: [Components.Schemas.WorkoutDayPlan]
        switch response {
        case .ok(let response):
            days = try response.body.json
        case .undocumented(let statusCode, _):
            Issue.record("Unexpected response status: \(statusCode)")
            return
        }

        let day = try #require(days.first)
        let set = try #require(day.slots.first?.sets.first)
        #expect(day.date == "2026-08-12")
        #expect(day.day.name == "Upper body")
        #expect(set.slotEntryId == 7)
        #expect(set.exercise == 123)
        #expect(set.sets == 3)
        #expect(set.repetitions == "8.00")
        #expect(set.weight == "60.00")
    }
}

private struct WorkoutDayPlanFixtureTransport: ClientTransport {
    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        #expect(operationID == "routine_date_sequence_gym_retrieve")
        #expect(request.path == "/api/v2/routine/42/date-sequence-gym/")
        return (
            HTTPResponse(status: .ok, headerFields: [.contentType: "application/json"]),
            HTTPBody(Self.body)
        )
    }

    private static let body = #"""
        [{
          "iteration": 2,
          "date": "2026-08-12",
          "label": "Week 1",
          "day": {
            "id": 3,
            "routine": 42,
            "order": 1,
            "name": "Upper body",
            "description": "Press and pull",
            "is_rest": false,
            "need_logs_to_advance": true,
            "type": "custom",
            "config": null
          },
          "slots": [{
            "comment": "Main lift",
            "is_superset": false,
            "exercises": [123],
            "sets": [{
              "slot_entry_id": 7,
              "exercise": 123,
              "sets": 3,
              "max_sets": null,
              "weight": "60.00",
              "max_weight": null,
              "weight_unit": 1,
              "weight_rounding": "2.50",
              "repetitions": "8.00",
              "max_repetitions": null,
              "repetitions_unit": 1,
              "repetitions_rounding": "1.00",
              "rir": "2.0",
              "max_rir": null,
              "rpe": "8.0",
              "rest": "120",
              "max_rest": null,
              "type": "normal",
              "text_repr": "3 Sets, 8 × 60 kg @ 2 RiR 120s rest",
              "comment": "Controlled reps"
            }]
          }]
        }]
        """#
}
