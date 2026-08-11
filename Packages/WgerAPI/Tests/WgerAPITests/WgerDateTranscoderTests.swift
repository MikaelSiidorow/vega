import Foundation
import Testing

@testable import WgerAPI

struct WgerDateTranscoderTests {
    @Test(
        "decodes wger timestamps",
        arguments: [
            "2026-08-11T12:34:56Z",
            "2026-08-11T12:34:56.123456Z",
            "2026-08-11T15:34:56.123456+03:00",
        ]
    )
    func decodesWgerTimestamp(_ timestamp: String) throws {
        let date = try WgerDateTranscoder().decode(timestamp)
        let expected = timestamp.contains(".") ? 1_786_451_696.123456 : 1_786_451_696

        #expect(abs(date.timeIntervalSince1970 - expected) < 0.001)
    }
}
