import Foundation

nonisolated struct ProductBarcode: Equatable, Sendable {
    enum Format: Equatable, Sendable {
        case ean8
        case upcA
        case ean13
        case gtin14
    }

    let value: String
    let format: Format

    init?(_ candidate: String) {
        let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }

        let format: Format
        switch value.count {
        case 8:
            format = .ean8
        case 12:
            format = .upcA
        case 13:
            format = .ean13
        case 14:
            format = .gtin14
        default:
            return nil
        }

        self.value = value
        self.format = format
    }
}

nonisolated struct BarcodeScanGate {
    private(set) var acceptedBarcode: ProductBarcode?

    mutating func accept(_ candidate: String) -> ProductBarcode? {
        guard acceptedBarcode == nil, let barcode = ProductBarcode(candidate) else { return nil }
        acceptedBarcode = barcode
        return barcode
    }
}
