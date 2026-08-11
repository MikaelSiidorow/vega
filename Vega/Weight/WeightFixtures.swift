import Foundation

actor FixtureWeightStore:
    WeightHistoryFetching,
    WeightEntryCreating,
    WeightEntryUpdating,
    WeightEntryDeleting
{
    private var entries: [WgerWeightEntry]
    private var nextID: Int

    init(entries: [WgerWeightEntry] = FixtureWeightStore.sampleEntries) {
        self.entries = entries
        nextID = (entries.map(\.id).max() ?? 0) + 1
    }

    func weightHistory() -> [WgerWeightEntry] {
        entries.sorted { $0.date > $1.date }
    }

    func createWeightEntry(date: Date, weight: String) throws {
        entries.append(
            WgerWeightEntry(id: nextID, date: date, weight: try Self.decimal(weight))
        )
        nextID += 1
    }

    func updateWeightEntry(id: Int, date: Date, weight: String) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index] = WgerWeightEntry(id: id, date: date, weight: try Self.decimal(weight))
    }

    func deleteWeightEntry(id: Int) {
        entries.removeAll { $0.id == id }
    }

    private static let sampleEntries: [WgerWeightEntry] = [
        entry(14, "2026-08-10T07:30:00Z", 79.6),
        entry(13, "2026-08-09T07:25:00Z", 80.1),
        entry(12, "2026-08-08T07:40:00Z", 79.8),
        entry(11, "2026-08-07T07:20:00Z", 80.3),
        entry(10, "2026-08-06T07:35:00Z", 80.0),
        entry(9, "2026-08-05T07:30:00Z", 80.4),
        entry(8, "2026-08-03T07:35:00Z", 80.0),
        entry(7, "2026-07-27T07:20:00Z", 80.4),
        entry(6, "2026-07-13T07:40:00Z", 81.1),
        entry(5, "2026-06-29T07:25:00Z", 81.5),
        entry(4, "2026-05-18T07:30:00Z", 82.2),
        entry(3, "2026-02-09T07:30:00Z", 83.0),
        entry(2, "2025-11-10T07:30:00Z", 83.5),
        entry(1, "2025-08-11T07:30:00Z", 84.1),
    ]

    private static func entry(_ id: Int, _ date: String, _ weight: Decimal) -> WgerWeightEntry {
        WgerWeightEntry(
            id: id,
            date: ISO8601DateFormatter().date(from: date)!,
            weight: weight
        )
    }

    private static func decimal(_ value: String) throws -> Decimal {
        guard let value = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else {
            throw WgerModelError.invalidWeight(value)
        }
        return value
    }
}
