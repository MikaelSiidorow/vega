import Foundation

nonisolated enum PowerSyncValueCodec {
    static func encodeDateTime(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func decodeDateTime(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func double(_ value: String, field: String) throws -> Double {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
        else { throw DiaryDomainError.invalidDecimal(field: field, value: value) }
        return NSDecimalNumber(decimal: decimal).doubleValue
    }

    static func decimalString(_ value: Double) -> String {
        NSDecimalNumber(decimal: Decimal(value)).stringValue
    }

    static func integerID(_ value: String) throws -> Int {
        guard let id = Int(value) else { throw WgerModelError.invalidIdentifier(value) }
        return id
    }
}
